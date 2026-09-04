import Foundation

/// The AI coding tools Skill Library distributes skills to.
enum Tool: String, CaseIterable, Codable, Identifiable, Comparable {
    case claude, cursor, codex, opencode, gemini, kiro, grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .gemini: return "Gemini CLI"
        case .kiro: return "Kiro"
        case .grok: return "Grok"
        }
    }

    /// What else reads this tool's skills folder — shown in Settings so users
    /// know e.g. the ChatGPT desktop app is covered by the Codex folder.
    var subtitle: String {
        switch self {
        case .claude: return "CLI, IDE extensions"
        case .cursor: return "Agent & Composer"
        case .codex: return "CLI, IDE extension, ChatGPT app"
        case .opencode: return "CLI"
        case .gemini: return "CLI"
        case .kiro: return "IDE & CLI"
        case .grok: return "CLI (grok)"
        }
    }

    /// Short label for compact UI chips.
    var shortName: String {
        switch self {
        case .claude: return "CL"
        case .cursor: return "CU"
        case .codex: return "CX"
        case .opencode: return "OC"
        case .gemini: return "GM"
        case .kiro: return "KI"
        case .grok: return "GK"
        }
    }

    /// The tool's skills directory (the one Skill Library manages).
    var skillsDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude: return home.appendingPathComponent(".claude/skills")
        case .cursor: return home.appendingPathComponent(".cursor/skills")
        case .codex: return home.appendingPathComponent(".codex/skills")
        case .opencode: return home.appendingPathComponent(".config/opencode/skills")
        case .gemini: return home.appendingPathComponent(".gemini/skills")
        case .kiro: return home.appendingPathComponent(".kiro/skills")
        case .grok: return home.appendingPathComponent(".grok/skills")
        }
    }

    /// Entries inside skillsDir that SkillHub must never touch.
    var protectedEntries: Set<String> {
        switch self {
        case .codex: return [".system", "codex-primary-runtime", ".codex-system-skills.marker"]
        default: return []
        }
    }

    // MARK: - Installation detection

    /// Where CLI binaries land on a Mac: package managers, language version
    /// managers, and the tool's own installer. GUI apps get a minimal PATH,
    /// so the login shell's PATH can't be trusted here.
    private static var binaryDirs: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.yarn/bin",
            "\(home)/.npm-global/bin", "\(home)/.cargo/bin",
        ]
        // nvm / fnm keep one bin dir per Node version.
        for root in ["\(home)/.nvm/versions/node", "\(home)/.fnm/node-versions"] {
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: root) {
                dirs += versions.map { "\(root)/\($0)/bin" }
                dirs += versions.map { "\(root)/\($0)/installation/bin" }
            }
        }
        return dirs
    }

    /// True when the tool itself appears to be installed — its binary, app
    /// bundle, or usage artifacts. A bare config/skills folder does NOT count:
    /// third-party installers create those on machines that never ran the tool.
    var isDetected: Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        func binary(_ name: String) -> Bool {
            Tool.binaryDirs.contains { fm.fileExists(atPath: "\($0)/\(name)") }
        }
        switch self {
        case .claude:
            return binary("claude") || fm.fileExists(atPath: "\(home)/.claude/projects")
        case .cursor:
            return fm.fileExists(atPath: "/Applications/Cursor.app")
                || fm.fileExists(atPath: "\(home)/Library/Application Support/Cursor")
        case .codex:
            return binary("codex") || fm.fileExists(atPath: "\(home)/.codex/logs_2.sqlite")
                || fm.fileExists(atPath: "\(home)/.codex/sessions")
                || fm.fileExists(atPath: "/Applications/ChatGPT.app")
        case .opencode:
            return binary("opencode") || fm.fileExists(atPath: "\(home)/.local/share/opencode")
        case .gemini:
            return binary("gemini") || fm.fileExists(atPath: "\(home)/.gemini/oauth_creds.json")
        case .kiro:
            return fm.fileExists(atPath: "/Applications/Kiro.app") || binary("kiro")
                || binary("kiro-cli")
        case .grok:
            return binary("grok") || fm.fileExists(atPath: "\(home)/.grok/bin/grok")
                || fm.fileExists(atPath: "\(home)/.grok/auth.json")
        }
    }

    // MARK: - Manual overrides

    /// Settings can force a tool on (not detected but wanted, e.g. a portable
    /// install) or off (detected but unused). nil = follow detection.
    private static let overridesKey = "toolOverrides"

    static var overrides: [Tool: Bool] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Bool] ?? [:]
            var out: [Tool: Bool] = [:]
            for (key, value) in raw { if let tool = Tool(rawValue: key) { out[tool] = value } }
            return out
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            UserDefaults.standard.set(raw, forKey: overridesKey)
        }
    }

    var override: Bool? {
        get { Tool.overrides[self] }
        nonmutating set {
            var all = Tool.overrides
            all[self] = newValue
            Tool.overrides = all
        }
    }

    /// Detection plus the user's override.
    var isActive: Bool { override ?? isDetected }

    /// Kept for call sites that only care about the effective answer.
    var isInstalled: Bool { isActive }

    /// Tools shown in UI: what's installed on this machine (or forced on).
    /// (Sync/drift machinery still handles all cases — absent dirs are inert.)
    static var active: [Tool] {
        allCases.filter(\.isActive)
    }

    static func < (lhs: Tool, rhs: Tool) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How a tool receives skills from the canonical store. Only `.symlink` is
/// implemented; the field survives in the manifest for forward compatibility.
enum LinkMode: String, Codable {
    case symlink   // tool dir entry is a symlink into ~/ai-skills/skills/<name>
    case copy      // tool dir entry is a real copy, hash-compared for drift
}
