import Foundation

/// Incremental scanner over Claude Code transcripts (~/.claude/projects/*/*.jsonl)
/// counting Skill tool invocations per skill. Never materializes whole files:
/// each file is read from its last cursor to EOF, only complete lines consumed.
/// Counts are stored per file so truncation/deletion stays correct.
struct TranscriptScanner {
    let projectsDir: URL
    let cacheURL: URL
    /// Per-pass read budget so a huge backlog can't stall a scan cycle.
    let maxBytesPerPass: Int

    init(
        projectsDir: URL = AppPaths.claudeProjectsDir,
        cacheURL: URL = AppPaths.appSupport.appendingPathComponent("usage-cache.json"),
        maxBytesPerPass: Int = 50_000_000
    ) {
        self.projectsDir = projectsDir
        self.cacheURL = cacheURL
        self.maxBytesPerPass = maxBytesPerPass
    }

    // MARK: - Cache IO

    func loadCache() -> UsageCache {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(UsageCache.self, from: data) else {
            return UsageCache()
        }
        return cache
    }

    func saveCache(_ cache: UsageCache) {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: - Scan

    /// One incremental pass. Returns the updated cache (also persisted).
    @discardableResult
    func scan() -> UsageCache {
        var cache = loadCache()
        var budget = maxBytesPerPass
        let fm = FileManager.default

        let files = (try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ))?.flatMap { projectDir -> [URL] in
            (try? fm.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension == "jsonl" } ?? []
        } ?? []

        var livePaths = Set<String>()
        for file in files {
            guard budget > 0 else { break }
            let path = file.path
            livePaths.insert(path)

            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.int64Value,
                  let mtime = attrs[.modificationDate] as? Date else { continue }

            var cursor = cache.cursors[path] ?? UsageCache.FileCursor(offset: 0, mtime: .distantPast, size: 0)
            if cursor.mtime == mtime && cursor.size == size { continue } // unchanged
            if size < cursor.offset {
                // Truncated/rewritten: rebuild this file's contribution from scratch.
                cursor = UsageCache.FileCursor(offset: 0, mtime: .distantPast, size: 0)
                cache.counts[path] = nil
            }

            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: UInt64(cursor.offset))
            let toRead = min(Int(size - cursor.offset), budget)
            guard let data = try? handle.read(upToCount: toRead), !data.isEmpty else {
                cache.cursors[path] = UsageCache.FileCursor(offset: cursor.offset, mtime: mtime, size: size)
                continue
            }
            budget -= data.count

            // Only consume complete lines; leave a partial trailing line for next pass.
            var consumable = data
            var consumedBytes = data.count
            if data.last != UInt8(ascii: "\n") {
                if let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) {
                    consumable = data[data.startIndex...lastNewline]
                    consumedBytes = consumable.count
                } else {
                    consumable = Data()
                    consumedBytes = 0
                }
            }

            if !consumable.isEmpty {
                var perFile = cache.counts[path] ?? [:]
                for line in consumable.split(separator: UInt8(ascii: "\n")) {
                    for (skill, timestamp) in Self.skillInvocations(inLine: line) {
                        var hit = perFile[skill] ?? UsageCache.SkillHit(count: 0, lastUsed: nil)
                        hit.count += 1
                        if let t = timestamp, hit.lastUsed.map({ t > $0 }) ?? true {
                            hit.lastUsed = t
                        }
                        perFile[skill] = hit
                    }
                }
                cache.counts[path] = perFile.isEmpty ? cache.counts[path] : perFile
            }

            let newOffset = cursor.offset + Int64(consumedBytes)
            // Only mark "caught up to mtime/size" when we actually reached EOF.
            let reachedEOF = newOffset >= size
            cache.cursors[path] = UsageCache.FileCursor(
                offset: newOffset,
                mtime: reachedEOF ? mtime : .distantPast,
                size: reachedEOF ? size : 0
            )
        }

        // Drop cache entries for deleted transcripts (their counts vanish with them).
        cache.cursors = cache.cursors.filter { livePaths.contains($0.key) }
        cache.counts = cache.counts.filter { livePaths.contains($0.key) }

        saveCache(cache)
        return cache
    }

    // MARK: - Line parsing

    private struct TranscriptLine: Decodable {
        let type: String?
        let timestamp: String?
        let message: Message?
        struct Message: Decodable {
            let content: [Content]?
            struct Content: Decodable {
                let type: String?
                let name: String?
                let input: Input?
                struct Input: Decodable {
                    let skill: String?
                }
            }
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    /// Extract (skill, timestamp) pairs from one JSONL line. Lenient: malformed
    /// lines yield nothing.
    static func skillInvocations(inLine line: Data) -> [(String, Date?)] {
        // Cheap pre-filter before JSON decoding.
        guard line.range(of: Data("\"Skill\"".utf8)) != nil else { return [] }
        guard let parsed = try? JSONDecoder().decode(TranscriptLine.self, from: line),
              parsed.type == "assistant",
              let contents = parsed.message?.content else { return [] }

        let timestamp = parsed.timestamp.flatMap {
            isoFractional.date(from: $0) ?? iso.date(from: $0)
        }
        return contents.compactMap { content in
            guard content.type == "tool_use", content.name == "Skill",
                  let skill = content.input?.skill else { return nil }
            return (skill, timestamp)
        }
    }
}
