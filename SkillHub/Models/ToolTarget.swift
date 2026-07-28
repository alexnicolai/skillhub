import Foundation

/// The AI coding tools SkillHub distributes skills to.
enum Tool: String, CaseIterable, Codable, Identifiable, Comparable {
    case claude, cursor, codex, opencode, gemini, kiro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .gemini: return "Gemini CLI"
        case .kiro: return "Kiro"
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
        }
    }

    /// The tool's skills directory (the one SkillHub manages).
    var skillsDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude: return home.appendingPathComponent(".claude/skills")
        case .cursor: return home.appendingPathComponent(".cursor/skills")
        case .codex: return home.appendingPathComponent(".codex/skills")
        case .opencode: return home.appendingPathComponent(".config/opencode/skills")
        case .gemini: return home.appendingPathComponent(".gemini/skills")
        case .kiro: return home.appendingPathComponent(".kiro/skills")
        }
    }

    /// Entries inside skillsDir that SkillHub must never touch.
    var protectedEntries: Set<String> {
        switch self {
        case .codex: return [".system", "codex-primary-runtime", ".codex-system-skills.marker"]
        default: return []
        }
    }

    static func < (lhs: Tool, rhs: Tool) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How a tool receives skills from the canonical store.
enum LinkMode: String, Codable {
    case symlink   // tool dir entry is a symlink into ~/ai-skills/skills/<name>
    case copy      // tool dir entry is a real copy, hash-compared for drift
}
