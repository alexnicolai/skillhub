import Foundation

/// Runtime model of one skill, hydrated from disk + manifest + local caches.
struct Skill: Identifiable, Equatable {
    let name: String                    // folder name == frontmatter name
    var description: String
    var shortDescription: String?
    var folderURL: URL                  // canonical folder in the store
    var contentHash: String
    var provenance: Provenance
    /// Intent from the manifest (which tools should have it).
    var intendedTools: Set<Tool>
    /// Derived live: which tools actually expose it right now.
    var liveTools: Set<Tool>
    var updateAvailable: Bool
    var usageCount: Int
    var lastUsed: Date?
    /// User-defined grouping tags (no "#", sorted).
    var tags: [String] = []

    var id: String { name }

    /// One-line summary for list rows: prefer the short description.
    var summary: String {
        if let s = shortDescription, !s.isEmpty { return s }
        // Descriptions are often long trigger lists; take the first sentence.
        let firstSentence = description.split(separator: ".", maxSplits: 1).first.map(String.init) ?? description
        return firstSentence.count > 140 ? String(firstSentence.prefix(140)) + "…" : firstSentence
    }

    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.name == rhs.name && lhs.contentHash == rhs.contentHash
            && lhs.intendedTools == rhs.intendedTools && lhs.liveTools == rhs.liveTools
            && lhs.updateAvailable == rhs.updateAvailable && lhs.usageCount == rhs.usageCount
            && lhs.tags == rhs.tags
    }
}
