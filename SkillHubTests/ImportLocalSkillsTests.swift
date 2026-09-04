import XCTest
@testable import SkillHub

/// AppState.importLocalSkills against a scratch store (SKILLHUB_REPO) with
/// every tool forced off, so nothing outside the temp dir is touched.
@MainActor
final class ImportLocalSkillsTests: XCTestCase {
    var tmp: URL!
    var savedOverrides: [Tool: Bool] = [:]

    override func setUp() async throws {
        let fm = FileManager.default
        tmp = fm.temporaryDirectory.appendingPathComponent("skillhub-import-\(UUID().uuidString)")
        let repo = tmp.appendingPathComponent("repo")
        try fm.createDirectory(at: repo.appendingPathComponent("skills"), withIntermediateDirectories: true)
        let git = GitService(repoRoot: repo)
        try git.run(["init", "-b", "main"])
        try git.run(["config", "user.email", "t@e.com"])
        try git.run(["config", "user.name", "T"])
        setenv("SKILLHUB_REPO", repo.path, 1)
        try XCTSkipUnless(AppPaths.repoRoot.path == repo.path, "SKILLHUB_REPO override not honored in this process")
        savedOverrides = Tool.overrides
        Tool.overrides = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, false) })
    }

    override func tearDown() async throws {
        Tool.overrides = savedOverrides
        unsetenv("SKILLHUB_REPO")
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeSource(_ name: String, body: String) throws -> URL {
        let dir = tmp.appendingPathComponent("src/\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: Imported \(name) for testing purposes.\n---\n\(body)\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }

    func testImportsThenReplacesOnlyWhenAllowed() throws {
        let state = AppState()
        state.reload()
        XCTAssertTrue(state.activeTools.isEmpty)

        let v1 = try makeSource("zz-import", body: "# v1")
        let first = state.importLocalSkills([v1.appendingPathComponent("SKILL.md")], replaceExisting: false)
        XCTAssertEqual(first.imported, ["zz-import"])
        XCTAssertEqual(state.skills.map(\.name), ["zz-import"])
        XCTAssertEqual(state.manifest.skills["zz-import"]?.description, "Imported zz-import for testing purposes.")
        XCTAssertEqual(state.selectedSkillNames, ["zz-import"])

        // Same name again, no replace: skipped, file untouched.
        try FileManager.default.removeItem(at: v1)
        let v2 = try makeSource("zz-import", body: "# v2")
        let second = state.importLocalSkills([v2], replaceExisting: false)
        XCTAssertEqual(second.skipped.map(\.name), ["zz-import"])
        let store = AppPaths.skillsDir.appendingPathComponent("zz-import/SKILL.md")
        XCTAssertTrue(try String(contentsOf: store, encoding: .utf8).contains("# v1"))

        // Replace: new content lands, entry survives, history has a commit per step.
        let third = state.importLocalSkills([v2], replaceExisting: true)
        XCTAssertEqual(third.replaced, ["zz-import"])
        XCTAssertTrue(try String(contentsOf: store, encoding: .utf8).contains("# v2"))
        let log = try GitService().lastCommits(5)
        XCTAssertEqual(log.count, 2, "\(log)")

        // Bad inputs are reported, not thrown.
        let junk = tmp.appendingPathComponent("src/Not A Skill")
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        let fourth = state.importLocalSkills([junk], replaceExisting: true)
        XCTAssertEqual(fourth.skipped.first?.reason, "no SKILL.md inside")
    }
}
