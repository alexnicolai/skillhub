import Foundation

/// Parked divergent copies (skills/.conflicts/<skill>-<origin>) surfaced for
/// resolution: keep the store's version, or take the parked one.
enum ConflictsService {
    struct Conflict: Identifiable, Equatable {
        let entryName: String    // e.g. "animate-cursor"
        let skillName: String    // "animate"
        let origin: String       // "cursor", "imported", …
        let folderURL: URL
        var id: String { entryName }
    }

    static func conflictsDir(store: URL) -> URL {
        store.appendingPathComponent(".conflicts")
    }

    static func list(store: URL) -> [Conflict] {
        let dir = conflictsDir(store: store)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { folder in
            let entry = folder.lastPathComponent
            guard FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("SKILL.md").path) else { return nil }
            // "<skill>-<origin>": origin is the last hyphen component.
            let parts = entry.split(separator: "-")
            let origin = parts.count > 1 ? String(parts.last!) : "unknown"
            let skill = parts.count > 1 ? parts.dropLast().joined(separator: "-") : entry
            return Conflict(entryName: entry, skillName: skill, origin: origin, folderURL: folder)
        }
        .sorted { $0.entryName < $1.entryName }
    }

    /// Keep the store's version: just delete the parked copy.
    static func keepMine(_ conflict: Conflict) throws {
        try FileManager.default.removeItem(at: conflict.folderURL)
    }

    /// Replace the canonical folder with the parked copy.
    static func takeTheirs(_ conflict: Conflict, store: URL) throws {
        let canonical = store.appendingPathComponent(conflict.skillName)
        let fm = FileManager.default
        if fm.fileExists(atPath: canonical.path) {
            try fm.removeItem(at: canonical)
        }
        try fm.moveItem(at: conflict.folderURL, to: canonical)
    }

    /// Unified diff between the parked copy and the canonical version.
    static func diff(_ conflict: Conflict, store: URL) -> String {
        let canonical = store.appendingPathComponent(conflict.skillName)
        return GitService(repoRoot: store).diffNoIndex(canonical.path, conflict.folderURL.path)
    }
}
