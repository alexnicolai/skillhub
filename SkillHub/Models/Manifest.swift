import Foundation

/// Codable schema for ~/ai-skills/skillhub.json — the git-tracked source of truth.
/// Skills are keyed by name; encoding uses .sortedKeys for stable, mergeable diffs.
/// Machine-local state (usage counts, backups) deliberately lives elsewhere.
struct Manifest: Codable {
    var version: Int
    var skills: [String: ManifestSkill]
    var toolSettings: [String: ToolSettings]?

    static let currentVersion = 1

    static func empty() -> Manifest {
        Manifest(version: currentVersion, skills: [:], toolSettings: nil)
    }

    func linkMode(for tool: Tool) -> LinkMode {
        toolSettings?[tool.rawValue]?.linkMode ?? .symlink
    }
}

struct ManifestSkill: Codable {
    var description: String
    var shortDescription: String?
    /// "sha256:<hex>" over sorted relative paths + file contents.
    var contentHash: String
    var source: Provenance
    /// Intent: which tools should have this skill. Live symlink state is derived;
    /// a mismatch between the two is drift.
    var tools: [String: Bool]
    /// User-defined tags for grouping (e.g. "UI/UX"). Stored sorted, no "#".
    var tags: [String]?
    var addedAt: Date

    func isEnabled(for tool: Tool) -> Bool {
        tools[tool.rawValue] ?? false
    }
}

enum Tags {
    /// Normalize user input: trim, strip leading '#'. Nil when empty.
    static func normalize(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") { t.removeFirst() }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

struct ToolSettings: Codable {
    var linkMode: LinkMode?
}

enum ManifestIO {
    static var manifestURL: URL {
        AppPaths.repoRoot.appendingPathComponent("skillhub.json")
    }

    static func load() throws -> Manifest {
        let url = manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty()
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Manifest.self, from: data)
    }

    static func save(_ manifest: Manifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }
}

/// Central path constants.
enum AppPaths {
    static let defaultsKey = "repoRootPath"

    /// The skill-store repo root. Priority: SKILLHUB_REPO env (tests/CI) →
    /// user's chosen location (onboarding) → ~/ai-skills default.
    static var repoRoot: URL {
        if let override = ProcessInfo.processInfo.environment["SKILLHUB_REPO"] {
            return URL(fileURLWithPath: override)
        }
        if let chosen = UserDefaults.standard.string(forKey: defaultsKey), !chosen.isEmpty {
            return URL(fileURLWithPath: (chosen as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ai-skills")
    }

    /// Canonical unified skill store (post-migration).
    static var skillsDir: URL { repoRoot.appendingPathComponent("skills") }

    /// Pre-migration legacy collections, read if skills/ does not exist yet.
    static var legacyDirs: [URL] {
        [repoRoot.appendingPathComponent("claude-skills"),
         repoRoot.appendingPathComponent("cursor-skills")]
    }

    static var backupsDir: URL { repoRoot.appendingPathComponent(".backups") }

    static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkillHub")
    }

    static var agentsSkillsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills")
    }

    static var agentsLockFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/.skill-lock.json")
    }

    static var claudeProjectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }
}
