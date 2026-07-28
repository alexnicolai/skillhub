import XCTest
@testable import SkillHub

final class TranscriptScannerTests: XCTestCase {
    var tmp: URL!
    var projects: URL!
    var scanner: TranscriptScanner!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-scan-\(UUID().uuidString)")
        projects = tmp.appendingPathComponent("projects")
        try FileManager.default.createDirectory(
            at: projects.appendingPathComponent("proj-a"), withIntermediateDirectories: true)
        scanner = TranscriptScanner(
            projectsDir: projects,
            cacheURL: tmp.appendingPathComponent("cache.json")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func skillLine(_ skill: String, ts: String = "2026-07-28T10:00:00.000Z") -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"\(skill)"}}]}}
        """
    }

    func testCountsSkillInvocations() throws {
        let file = projects.appendingPathComponent("proj-a/session1.jsonl")
        let content = [
            #"{"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}"#,
            skillLine("animate"),
            skillLine("animate", ts: "2026-07-28T11:00:00.000Z"),
            skillLine("quiz"),
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#,
            "not json at all",
        ].joined(separator: "\n") + "\n"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let cache = scanner.scan()
        let agg = cache.aggregated()
        XCTAssertEqual(agg["animate"]?.count, 2)
        XCTAssertEqual(agg["quiz"]?.count, 1)
        XCTAssertNil(agg["Bash"])
        XCTAssertEqual(
            agg["animate"]?.lastUsed,
            ISO8601DateFormatter().date(from: "2026-07-28T11:00:00Z")
        )
    }

    func testIncrementalAppendOnlyCountsNewLines() throws {
        let file = projects.appendingPathComponent("proj-a/session1.jsonl")
        try (skillLine("animate") + "\n").write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(scanner.scan().aggregated()["animate"]?.count, 1)

        // Append two more; prior counts must not double.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((skillLine("animate") + "\n" + skillLine("triage") + "\n").utf8))
        try handle.close()

        let agg = scanner.scan().aggregated()
        XCTAssertEqual(agg["animate"]?.count, 2)
        XCTAssertEqual(agg["triage"]?.count, 1)

        // Third scan with no changes: identical.
        let agg2 = scanner.scan().aggregated()
        XCTAssertEqual(agg2["animate"]?.count, 2)
    }

    func testPartialTrailingLineDeferred() throws {
        let file = projects.appendingPathComponent("proj-a/session1.jsonl")
        let full = skillLine("animate") + "\n"
        let partial = String(skillLine("quiz").prefix(40)) // no trailing newline
        try (full + partial).write(to: file, atomically: true, encoding: .utf8)

        var agg = scanner.scan().aggregated()
        XCTAssertEqual(agg["animate"]?.count, 1)
        XCTAssertNil(agg["quiz"])

        // Complete the partial line; only then does quiz count.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let remainder = String(skillLine("quiz").dropFirst(40)) + "\n"
        try handle.write(contentsOf: Data(remainder.utf8))
        try handle.close()

        agg = scanner.scan().aggregated()
        XCTAssertEqual(agg["quiz"]?.count, 1)
        XCTAssertEqual(agg["animate"]?.count, 1)
    }

    func testTruncatedFileRebuilds() throws {
        let file = projects.appendingPathComponent("proj-a/session1.jsonl")
        try (skillLine("animate") + "\n" + skillLine("animate") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(scanner.scan().aggregated()["animate"]?.count, 2)

        // Rewrite shorter (e.g. rotated): counts rebuild, not accumulate.
        try (skillLine("animate") + "\n").write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(scanner.scan().aggregated()["animate"]?.count, 1)
    }

    func testDeletedFileDropsFromAggregate() throws {
        let file = projects.appendingPathComponent("proj-a/session1.jsonl")
        try (skillLine("animate") + "\n").write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(scanner.scan().aggregated()["animate"]?.count, 1)

        try FileManager.default.removeItem(at: file)
        XCTAssertNil(scanner.scan().aggregated()["animate"])
    }
}
