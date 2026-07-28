import Foundation

/// Checks GitHub-sourced skills for upstream changes without cloning:
/// one `git/trees/HEAD?recursive=1` call per distinct repo (ETag-cached),
/// comparing each skill folder's tree sha against the stored upstreamHash.
/// One-click update uses a shallow sparse clone of just the skill's folder.
struct UpdateChecker {
    struct RepoCache: Codable {
        var etag: String?
        var fetchedAt: Date?
        /// path in repo -> tree sha
        var treeShaByPath: [String: String] = [:]
    }

    struct CheckResult {
        /// skill name -> latest upstream tree sha (differs from stored hash)
        var updatesAvailable: [String: String] = [:]
        var errors: [String] = []
    }

    let cacheURL: URL
    let token: String?
    /// Re-fetch a repo's tree at most this often unless forced.
    let maxCacheAge: TimeInterval

    init(
        cacheURL: URL = AppPaths.appSupport.appendingPathComponent("update-cache.json"),
        token: String? = nil,
        maxCacheAge: TimeInterval = 6 * 3600
    ) {
        self.cacheURL = cacheURL
        self.token = token ?? UserDefaults.standard.string(forKey: "githubToken")
        self.maxCacheAge = maxCacheAge
    }

    // MARK: - Check

    func check(manifest: Manifest, force: Bool = false) async -> CheckResult {
        var result = CheckResult()

        // Group github-sourced skills by repo.
        var byRepo: [String: [(name: String, skill: ManifestSkill)]] = [:]
        for (name, skill) in manifest.skills
        where skill.source.sourceType == .github && skill.source.source != nil && skill.source.skillPath != nil {
            byRepo[skill.source.source!, default: []].append((name, skill))
        }

        var caches = loadCaches()
        for (repo, skills) in byRepo.sorted(by: { $0.key < $1.key }) {
            var cache = caches[repo] ?? RepoCache()
            let stale = force
                || cache.fetchedAt == nil
                || Date().timeIntervalSince(cache.fetchedAt!) > maxCacheAge
            if stale {
                do {
                    cache = try await fetchTree(repo: repo, cache: cache)
                    caches[repo] = cache
                } catch {
                    result.errors.append("\(repo): \(error.localizedDescription)")
                    continue
                }
            }
            for (name, skill) in skills {
                guard let path = skill.source.skillPath,
                      let upstream = cache.treeShaByPath[path] else { continue }
                if upstream != skill.source.upstreamHash {
                    result.updatesAvailable[name] = upstream
                }
            }
        }
        saveCaches(caches)
        return result
    }

    private func fetchTree(repo: String, cache: RepoCache) async throws -> RepoCache {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/git/trees/HEAD?recursive=1")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let etag = cache.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        var updated = cache
        switch http.statusCode {
        case 304:
            updated.fetchedAt = Date()
            return updated
        case 200:
            struct Tree: Decodable {
                struct Entry: Decodable { let path: String; let type: String; let sha: String }
                let tree: [Entry]
                let truncated: Bool?
            }
            let tree = try JSONDecoder().decode(Tree.self, from: data)
            updated.treeShaByPath = Dictionary(
                uniqueKeysWithValues: tree.tree.filter { $0.type == "tree" }.map { ($0.path, $0.sha) }
            )
            updated.etag = http.value(forHTTPHeaderField: "ETag")
            updated.fetchedAt = Date()
            return updated
        case 403, 429:
            throw NSError(domain: "SkillHub", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub rate limited — add a token in Settings"])
        default:
            throw NSError(domain: "SkillHub", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub HTTP \(http.statusCode)"])
        }
    }

    // MARK: - One-click update

    /// Replace the canonical folder with the upstream version via shallow sparse
    /// clone, preserving tool-specific sidecar files (agents/) the upstream lacks.
    /// Caller is responsible for the locally-modified guard and the git commit.
    func update(
        skillName: String,
        skill: ManifestSkill,
        canonicalFolder: URL,
        newUpstreamSha: String
    ) throws -> ManifestSkill {
        guard let url = skill.source.sourceUrl, let skillPath = skill.source.skillPath else {
            throw NSError(domain: "SkillHub", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "\(skillName) has no upstream URL"])
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("skillhub-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }

        let git = GitService(repoRoot: scratch)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        try git.run(["clone", "--depth", "1", "--filter=blob:none", "--sparse", url, "clone"])
        let cloneGit = GitService(repoRoot: scratch.appendingPathComponent("clone"))
        try cloneGit.run(["sparse-checkout", "set", skillPath])

        let upstreamFolder = scratch.appendingPathComponent("clone").appendingPathComponent(skillPath)
        guard fm.fileExists(atPath: upstreamFolder.appendingPathComponent("SKILL.md").path) else {
            throw NSError(domain: "SkillHub", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Upstream \(skillPath) has no SKILL.md"])
        }

        // Preserve local-only sidecars (e.g. agents/openai.yaml) upstream doesn't ship.
        let localFiles = (try? HashService.fileHashes(canonicalFolder)) ?? [:]
        let upstreamFiles = (try? HashService.fileHashes(upstreamFolder)) ?? [:]
        let sidecars = localFiles.keys.filter { $0.hasPrefix("agents/") && upstreamFiles[$0] == nil }

        let staging = scratch.appendingPathComponent("staged")
        try fm.copyItem(at: upstreamFolder, to: staging)
        for rel in sidecars {
            let dst = staging.appendingPathComponent(rel)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: canonicalFolder.appendingPathComponent(rel), to: dst)
        }

        // Swap into place.
        try fm.removeItem(at: canonicalFolder)
        try fm.copyItem(at: staging, to: canonicalFolder)
        try? fm.removeItem(at: canonicalFolder.appendingPathComponent(".DS_Store"))

        var updated = skill
        updated.contentHash = (try? HashService.hashFolder(canonicalFolder)) ?? updated.contentHash
        updated.source.upstreamHash = newUpstreamSha
        updated.source.updatedAt = Date()
        updated.description = FrontmatterParser
            .parse(fileURL: canonicalFolder.appendingPathComponent("SKILL.md")).description ?? updated.description
        return updated
    }

    // MARK: - Cache IO

    private func loadCaches() -> [String: RepoCache] {
        guard let data = try? Data(contentsOf: cacheURL),
              let caches = try? JSONDecoder().decode([String: RepoCache].self, from: data) else { return [:] }
        return caches
    }

    private func saveCaches(_ caches: [String: RepoCache]) {
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(caches) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
