import Foundation

/// Machine-local usage cache (~/Library/Application Support/SkillHub/usage-cache.json).
/// Counts are stored per transcript file so truncated/deleted files stay correct.
struct UsageCache: Codable {
    struct FileCursor: Codable, Equatable {
        var offset: Int64
        var mtime: Date
        var size: Int64
    }

    struct SkillHit: Codable {
        var count: Int
        var lastUsed: Date?
    }

    var version: Int = 1
    /// transcript path -> cursor
    var cursors: [String: FileCursor] = [:]
    /// transcript path -> (skill name -> hits)
    var counts: [String: [String: SkillHit]] = [:]

    /// Aggregate across all files.
    func aggregated() -> [String: SkillHit] {
        var out: [String: SkillHit] = [:]
        for perFile in counts.values {
            for (skill, hit) in perFile {
                var agg = out[skill] ?? SkillHit(count: 0, lastUsed: nil)
                agg.count += hit.count
                if let t = hit.lastUsed, agg.lastUsed.map({ t > $0 }) ?? true {
                    agg.lastUsed = t
                }
                out[skill] = agg
            }
        }
        return out
    }
}
