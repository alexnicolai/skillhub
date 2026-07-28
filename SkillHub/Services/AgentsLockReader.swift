import Foundation

/// Reads provenance from the vercel-labs skills CLI lock file
/// (~/.agents/.skill-lock.json, version 3) so absorbed skills keep their
/// source repo, upstream hash, and install dates for update checking.
enum AgentsLockReader {

    private struct LockFile: Decodable {
        let version: Int?
        let skills: [String: LockEntry]?
    }

    private struct LockEntry: Decodable {
        let source: String?
        let sourceType: String?
        let sourceUrl: String?
        let skillPath: String?
        let skillFolderHash: String?
        let installedAt: String?
        let updatedAt: String?
    }

    /// skill name -> Provenance
    static func read(from url: URL = AppPaths.agentsLockFile) -> [String: Provenance] {
        guard let data = try? Data(contentsOf: url),
              let lock = try? JSONDecoder().decode(LockFile.self, from: data),
              let entries = lock.skills else { return [:] }

        let iso = ISO8601DateFormatter()
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ s: String?) -> Date? {
            guard let s else { return nil }
            return iso.date(from: s) ?? isoFractional.date(from: s)
        }

        var out: [String: Provenance] = [:]
        for (name, entry) in entries {
            out[name] = Provenance(
                sourceType: entry.sourceType == "github" ? .github : .local,
                source: entry.source,
                sourceUrl: entry.sourceUrl,
                skillPath: (entry.skillPath as NSString?)?.deletingLastPathComponent,
                upstreamHash: entry.skillFolderHash,
                installedAt: date(entry.installedAt),
                updatedAt: date(entry.updatedAt)
            )
        }
        return out
    }
}
