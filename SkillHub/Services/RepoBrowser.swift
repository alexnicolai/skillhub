import Foundation

/// Browses a GitHub repo for installable skills and installs a selection.
/// Discovery is API-only (one tree call + raw SKILL.md fetches); install is a
/// single shallow sparse clone of just the chosen folders.
struct RepoBrowser {
    struct RemoteSkill: Identifiable, Equatable {
        let name: String        // folder name
        let path: String        // folder path in repo
        let treeSha: String
        var description: String = ""
        var id: String { path }
    }

    /// Quick-picks shown in the install sheet.
    static let knownSources = [
        "anthropics/skills",
        "vercel-labs/skills",
        "readwiseio/readwise-skills",
        "remotion-dev/skills",
        "clerk/skills",
        "expo/skills",
    ]

    /// "owner/repo", full URLs, and .git suffixes all accepted.
    static func parseRepo(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s.removeLast(4) }
        if let range = s.range(of: "github.com/") {
            s = String(s[range.upperBound...])
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = s.split(separator: "/")
        guard parts.count >= 2,
              parts[0].range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil,
              parts[1].range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    let token: String?

    init(token: String? = nil) {
        self.token = token ?? TokenStore.get()
    }

    /// Every folder in the repo containing a SKILL.md, with descriptions.
    func discover(repo: String) async throws -> [RemoteSkill] {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/git/trees/HEAD?recursive=1")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "SkillHub", code: 11, userInfo: [NSLocalizedDescriptionKey:
                code == 404 ? "Repo not found (private repos need a token in Settings)"
                            : "GitHub returned HTTP \(code)"])
        }

        struct Tree: Decodable {
            struct Entry: Decodable { let path: String; let type: String; let sha: String }
            let tree: [Entry]
        }
        let tree = try JSONDecoder().decode(Tree.self, from: data)
        let folderShas = Dictionary(uniqueKeysWithValues:
            tree.tree.filter { $0.type == "tree" }.map { ($0.path, $0.sha) })

        var found: [RemoteSkill] = []
        for entry in tree.tree where entry.type == "blob" && entry.path.hasSuffix("/SKILL.md") {
            let folderPath = String(entry.path.dropLast("/SKILL.md".count))
            guard let sha = folderShas[folderPath] else { continue }
            let name = folderPath.split(separator: "/").last.map(String.init) ?? folderPath
            found.append(RemoteSkill(name: name, path: folderPath, treeSha: sha))
            if found.count >= 200 { break }
        }
        found.sort { $0.name < $1.name }

        // Fetch descriptions concurrently (small files, best effort).
        return await withTaskGroup(of: (Int, String).self) { group in
            for (index, skill) in found.enumerated() {
                group.addTask {
                    let url = URL(string: "https://raw.githubusercontent.com/\(repo)/HEAD/\(skill.path)/SKILL.md")!
                    guard let (data, _) = try? await URLSession.shared.data(from: url),
                          let text = String(data: data, encoding: .utf8) else { return (index, "") }
                    return (index, FrontmatterParser.parse(text).description ?? "")
                }
            }
            var out = found
            for await (index, description) in group {
                out[index].description = description
            }
            return out
        }
    }

    struct InstallResult {
        var installed: [String] = []
        var skipped: [String] = []   // name collisions with the store
    }

    /// Sparse-clone the repo once and copy the selected skill folders in.
    /// Caller updates the manifest and commits.
    func install(
        repo: String,
        skills: [RemoteSkill],
        into store: URL
    ) throws -> InstallResult {
        let fm = FileManager.default
        var result = InstallResult()
        let candidates = skills.filter { skill in
            if fm.fileExists(atPath: store.appendingPathComponent(skill.name).path) {
                result.skipped.append(skill.name)
                return false
            }
            return true
        }
        guard !candidates.isEmpty else { return result }

        let scratch = fm.temporaryDirectory.appendingPathComponent("skillhub-install-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let git = GitService(repoRoot: scratch)
        try git.run(["clone", "--depth", "1", "--filter=blob:none", "--sparse",
                     "https://github.com/\(repo).git", "clone"])
        let cloneGit = GitService(repoRoot: scratch.appendingPathComponent("clone"))
        try cloneGit.run(["sparse-checkout", "set"] + candidates.map(\.path))

        for skill in candidates {
            let src = scratch.appendingPathComponent("clone").appendingPathComponent(skill.path)
            guard fm.fileExists(atPath: src.appendingPathComponent("SKILL.md").path) else {
                result.skipped.append(skill.name)
                continue
            }
            try fm.copyItem(at: src, to: store.appendingPathComponent(skill.name))
            try? fm.removeItem(at: store.appendingPathComponent("\(skill.name)/.DS_Store"))
            result.installed.append(skill.name)
        }
        return result
    }

    /// Manifest provenance for an installed remote skill.
    static func provenance(repo: String, skill: RemoteSkill) -> Provenance {
        Provenance(
            sourceType: .github,
            source: repo,
            sourceUrl: "https://github.com/\(repo).git",
            skillPath: skill.path,
            upstreamHash: skill.treeSha,
            installedAt: Date(),
            updatedAt: Date()
        )
    }
}
