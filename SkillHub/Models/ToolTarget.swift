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

    /// True when the tool itself appears to be installed — its binary, app
    /// bundle, or usage artifacts. A bare config/skills folder does NOT count:
    /// third-party installers create those on machines that never ran the tool.
    var isInstalled: Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        func binary(_ name: String) -> Bool {
            ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
                .contains { fm.fileExists(atPath: "\($0)/\(name)") }
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
        case .opencode:
            return binary("opencode") || fm.fileExists(atPath: "\(home)/.local/share/opencode")
        case .gemini:
            return binary("gemini") || fm.fileExists(atPath: "\(home)/.gemini/oauth_creds.json")
        case .kiro:
            return fm.fileExists(atPath: "/Applications/Kiro.app") || binary("kiro")
        case .grok:
            return binary("grok") || fm.fileExists(atPath: "\(home)/.grok/auth.json")
        }
    }

    /// Tools shown in UI: only what's actually installed on this machine.
    /// (Sync/drift machinery still handles all cases — absent dirs are inert.)
    static var active: [Tool] {
        allCases.filter(\.isInstalled)
    }

    static func < (lhs: Tool, rhs: Tool) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How a tool receives skills from the canonical store.
enum LinkMode: String, Codable {
    case symlink   // tool dir entry is a symlink into ~/ai-skills/skills/<name>
    case copy      // tool dir entry is a real copy, hash-compared for drift
}
