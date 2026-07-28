import Foundation

/// A single divergence between manifest intent and on-disk reality.
struct DriftItem: Identifiable, Equatable {
    enum Kind: String {
        case notSymlink    // real dir where a symlink is expected
        case wrongTarget   // symlink pointing somewhere other than canonical
        case missingLink   // manifest says enabled but tool dir has no entry
        case orphanLink    // symlink whose canonical target no longer exists
        case staleCopy     // copy-mode entry whose hash differs from canonical
    }

    let tool: Tool
    let entryName: String
    let kind: Kind
    var detail: String

    var id: String { "\(tool.rawValue)/\(entryName)/\(kind.rawValue)" }
}

/// Result of scanning one tool's skills directory.
struct ToolScanResult {
    let tool: Tool
    var exists: Bool
    /// Entries that are symlinks into the canonical store: name -> resolved skill name.
    var linkedSkills: [String: String]
    /// Entries that are real directories (not protected).
    var realDirs: [String]
    /// Entries that are symlinks pointing outside the canonical store.
    var foreignLinks: [String: String]  // name -> destination path
}
