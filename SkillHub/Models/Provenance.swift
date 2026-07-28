import Foundation

/// Where a skill came from, and enough state to check for upstream updates.
struct Provenance: Codable, Equatable {
    enum SourceType: String, Codable {
        case github   // installed from a GitHub repo; updates checkable
        case local    // authored locally / origin unknown
        case plugin   // came from a tool plugin/marketplace (e.g. animations.dev installer)
    }

    var sourceType: SourceType
    /// "owner/repo", e.g. "readwiseio/readwise-skills"
    var source: String?
    var sourceUrl: String?
    /// Path of the skill folder inside the upstream repo, e.g. "skills/book-review"
    var skillPath: String?
    /// Last-known upstream git tree hash of the skill folder.
    var upstreamHash: String?
    var installedAt: Date?
    var updatedAt: Date?

    static let local = Provenance(sourceType: .local)

    var badgeText: String {
        switch sourceType {
        case .github: return source ?? "github"
        case .local: return "local"
        case .plugin: return "plugin"
        }
    }
}
