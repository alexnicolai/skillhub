import XCTest
@testable import SkillHub

final class FeatureServicesTests: XCTestCase {
    var tmp: URL!
    var store: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-feat-\(UUID().uuidString)")
        store = tmp.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Scaffold

    func testScaffoldCreateAndValidate() throws {
        XCTAssertNotNil(SkillScaffold.validate(name: "Bad Name", store: store))
        XCTAssertNotNil(SkillScaffold.validate(name: "-leading", store: store))
        XCTAssertNil(SkillScaffold.validate(name: "my-skill2", store: store))

        let folder = try SkillScaffold.create(name: "my-skill", description: "Does things.", store: store)
        let fm = FrontmatterParser.parse(fileURL: folder.appendingPathComponent("SKILL.md"))
        XCTAssertEqual(fm.name, "my-skill")
        XCTAssertEqual(fm.description, "Does things.")
        // Duplicate refused.
        XCTAssertThrowsError(try SkillScaffold.create(name: "my-skill", description: "", store: store))
    }

    // MARK: - Doctor

    func testDoctorFindsProblems() throws {
        let folder = store.appendingPathComponent("sick")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
        ---
        name: wrong-name
        description: short
        ---
        # Doc
        See [the guide](missing/guide.md) and [site](https://ok.example).
        """.write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let issues = SkillDoctor.check(folder: folder, expectedName: "sick")
        let messages = issues.map(\.message).joined(separator: "|")
        XCTAssertTrue(messages.contains("wrong-name"))
        XCTAssertTrue(messages.contains("very short"))
        XCTAssertTrue(messages.contains("Broken link: missing/guide.md"))
        XCTAssertFalse(messages.contains("https://ok.example"))

        // Healthy skill: no findings.
        let good = store.appendingPathComponent("good")
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try """
        ---
        name: good
        description: A perfectly reasonable description of when to use this skill.
        ---
        # Fine
        """.write(to: good.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SkillDoctor.check(folder: good, expectedName: "good"), [])
    }

    // MARK: - Conflicts

    func testConflictsListAndResolve() throws {
        let fm = FileManager.default
        // canonical + parked variant
        for (path, body) in [("animate", "store version"), (".conflicts/animate-cursor", "parked version")] {
            let folder = store.appendingPathComponent(path)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try "---\nname: animate\ndescription: d.\n---\n\(body)"
                .write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        var conflicts = ConflictsService.list(store: store)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].skillName, "animate")
        XCTAssertEqual(conflicts[0].origin, "cursor")

        // Take theirs replaces canonical.
        try ConflictsService.takeTheirs(conflicts[0], store: store)
        let content = try String(
            contentsOf: store.appendingPathComponent("animate/SKILL.md"), encoding: .utf8)
        XCTAssertTrue(content.contains("parked version"))
        XCTAssertTrue(ConflictsService.list(store: store).isEmpty)

        // Keep mine deletes the parked copy.
        let park2 = store.appendingPathComponent(".conflicts/animate-imported")
        try fm.createDirectory(at: park2, withIntermediateDirectories: true)
        try "---\nname: animate\ndescription: d.\n---\nx"
            .write(to: park2.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        conflicts = ConflictsService.list(store: store)
        try ConflictsService.keepMine(conflicts[0])
        XCTAssertTrue(ConflictsService.list(store: store).isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: store.appendingPathComponent("animate/SKILL.md").path))
    }

    // MARK: - Inbox

    func testInboxSubmitApproveReject() throws {
        // Redirect the inbox into scratch via the store-collision check only;
        // submissions themselves land in the real app-support inbox dir, so use
        // unique names and clean up.
        let name = "test-inbox-\(Int.random(in: 10000...99999))"
        defer { try? FileManager.default.removeItem(at: InboxService.inboxDir.appendingPathComponent(name)) }

        XCTAssertEqual(InboxService.submit(name: "Bad/Name", skillMd: "x", tool: "t", store: store), .badName)
        XCTAssertNil(InboxService.submit(
            name: name, skillMd: "---\nname: \(name)\ndescription: d.\n---\nbody", tool: "claude", store: store))
        // Duplicate submission refused.
        XCTAssertEqual(InboxService.submit(name: name, skillMd: "x", tool: "t", store: store), .alreadyExists)

        let submission = InboxService.list().first { $0.name == name }
        XCTAssertNotNil(submission)
        XCTAssertEqual(submission?.tool, "claude")

        try InboxService.approve(submission!, store: store)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.appendingPathComponent("\(name)/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.appendingPathComponent("\(name)/.meta.json").path))
        XCTAssertNil(InboxService.list().first { $0.name == name })
    }

    // MARK: - Repo parsing + fuzzy ranking

    func testRepoParsing() {
        XCTAssertEqual(RepoBrowser.parseRepo("vercel-labs/skills"), "vercel-labs/skills")
        XCTAssertEqual(RepoBrowser.parseRepo("https://github.com/anthropics/skills.git"), "anthropics/skills")
        XCTAssertEqual(RepoBrowser.parseRepo("github.com/a/b/tree/main"), "a/b")
        XCTAssertNil(RepoBrowser.parseRepo("not a repo"))
        XCTAssertNil(RepoBrowser.parseRepo(""))
    }

    func testQuickOpenRanking() {
        func skill(_ name: String, usage: Int = 0) -> Skill {
            Skill(name: name, description: "", shortDescription: nil,
                  folderURL: URL(fileURLWithPath: "/tmp"), contentHash: "",
                  provenance: .local, intendedTools: [], liveTools: [],
                  updateAvailable: false, usageCount: usage, lastUsed: nil)
        }
        let skills = [skill("animate"), skill("animation-vocabulary"), skill("clerk-setup"), skill("quiz")]
        let ranked = QuickOpenView.rank(skills, query: "anim")
        XCTAssertEqual(ranked.first?.name, "animate")
        XCTAssertEqual(ranked.count, 2)
        // Subsequence match: "csp" → clerk-setup
        XCTAssertEqual(QuickOpenView.rank(skills, query: "csp").first?.name, "clerk-setup")
        // Empty query: usage order
        XCTAssertEqual(QuickOpenView.rank([skill("a"), skill("b", usage: 5)], query: "").first?.name, "b")
    }
}
