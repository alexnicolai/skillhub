import XCTest
@testable import SkillHub

/// A tool dir that symlinks into some other store (the `npx skills` layout:
/// ~/.claude/skills/x -> ../../.agents/skills/x) must be importable and then
/// relinkable — that's the case "Repair drift" used to leave untouched.
final class ForeignLinkImportTests: XCTestCase {
    var tmp: URL!
    var repo: URL!
    var engine: SyncEngine!
    var git: GitService!
    var claudeDir: URL!
    var otherStore: URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        tmp = fm.temporaryDirectory.appendingPathComponent("skillhub-foreign-\(UUID().uuidString)")
        repo = tmp.appendingPathComponent("repo")
        claudeDir = tmp.appendingPathComponent("claude-tool")
        otherStore = tmp.appendingPathComponent("other-store")
        for dir in [repo!, claudeDir!, otherStore!, repo.appendingPathComponent("skills")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        git = GitService(repoRoot: repo)
        try git.run(["init", "-b", "main"])
        try git.run(["config", "user.email", "t@e.com"])
        try git.run(["config", "user.name", "T"])
        let emptyAgents = tmp.appendingPathComponent("agents/skills")
        try fm.createDirectory(at: emptyAgents, withIntermediateDirectories: true)
        engine = SyncEngine(repoRoot: repo, toolDirs: [.claude: claudeDir], agentsDir: emptyAgents)

        // other-store/brandkit + a RELATIVE symlink from the tool dir.
        let skill = otherStore.appendingPathComponent("brandkit")
        try fm.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: brandkit\ndescription: Brand kits for tests.\n---\n# brandkit\n"
            .write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(
            atPath: claudeDir.appendingPathComponent("brandkit").path,
            withDestinationPath: "../other-store/brandkit")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testForeignLinkIsSeenAsExternalAndRepairRelinks() throws {
        // Scan classifies it as foreign; drift reports wrongTarget.
        let scan = engine.scanTool(.claude)
        XCTAssertEqual(scan.foreignLinks.keys.sorted(), ["brandkit"])
        XCTAssertEqual(engine.detectDrift(manifest: .empty()).map(\.kind), [.wrongTarget])

        // The link target counts as an importable external skill.
        XCTAssertEqual(engine.externalSkillFolders().keys.sorted(), ["brandkit"])

        // Import + convert = what repairDrift does.
        let imported = try engine.importExternalSkills(git: git)
        XCTAssertEqual(imported, ["brandkit"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: engine.canonicalFolder("brandkit").appendingPathComponent("SKILL.md").path))

        let report = try engine.convertTool(.claude, backupStamp: "stamp")
        XCTAssertEqual(report.linked, ["brandkit"])
        XCTAssertTrue(report.issues.isEmpty, "\(report.issues)")

        let after = engine.scanTool(.claude)
        XCTAssertEqual(after.linkedSkills["brandkit"], "brandkit")
        XCTAssertTrue(after.foreignLinks.isEmpty)
        let manifest = try engine.buildManifest()
        XCTAssertTrue(engine.detectDrift(manifest: manifest).isEmpty)
    }
}
