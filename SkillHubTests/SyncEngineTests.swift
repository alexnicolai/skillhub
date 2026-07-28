import XCTest
@testable import SkillHub

/// SyncEngine tested against a scratch repo + fake tool dirs — never the real system.
final class SyncEngineTests: XCTestCase {
    var tmp: URL!
    var repo: URL!
    var engine: SyncEngine!
    var git: GitService!
    var claudeDir: URL!
    var cursorDir: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-sync-\(UUID().uuidString)")
        repo = tmp.appendingPathComponent("repo")
        claudeDir = tmp.appendingPathComponent("claude-tool")
        cursorDir = tmp.appendingPathComponent("cursor-tool")
        let fm = FileManager.default
        try fm.createDirectory(at: repo, withIntermediateDirectories: true)
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: cursorDir, withIntermediateDirectories: true)

        git = GitService(repoRoot: repo)
        try git.run(["init", "-b", "main"])
        try git.run(["config", "user.email", "t@e.com"])
        try git.run(["config", "user.name", "T"])

        let fakeAgents = tmp.appendingPathComponent("agents/skills")
        try fm.createDirectory(at: fakeAgents, withIntermediateDirectories: true)
        engine = SyncEngine(
            repoRoot: repo,
            toolDirs: [.claude: claudeDir, .cursor: cursorDir],
            agentsDir: fakeAgents
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeSkill(_ base: URL, _ name: String, body: String = "content") throws {
        let dir = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        ---
        name: \(name)
        description: Test skill \(name).
        ---
        # \(name)
        \(body)
        """.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func testFullMigrationAndConversion() throws {
        let fm = FileManager.default
        // Legacy layout: shared (identical), claude-only, cursor-only, conflicting.
        let legacyClaude = repo.appendingPathComponent("claude-skills")
        let legacyCursor = repo.appendingPathComponent("cursor-skills")
        try makeSkill(legacyClaude, "shared")
        try makeSkill(legacyCursor, "shared")
        try makeSkill(legacyClaude, "claude-only")
        try makeSkill(legacyCursor, "cursor-only")
        try makeSkill(legacyClaude, "clash", body: "claude version")
        try makeSkill(legacyCursor, "clash", body: "cursor version")
        try git.commitAll(message: "legacy")

        // Tool dirs: identical copy, divergent copy, tool-only skill.
        try makeSkill(claudeDir, "shared")
        try makeSkill(claudeDir, "clash", body: "claude version")
        try makeSkill(cursorDir, "shared", body: "cursor local edit!")   // divergent
        try makeSkill(cursorDir, "cursor-tool-only")                     // needs import

        // --- Migrate ---
        try engine.migrateRepoLayout(git: git)
        let skills = repo.appendingPathComponent("skills")
        XCTAssertTrue(fm.fileExists(atPath: skills.appendingPathComponent("shared/SKILL.md").path))
        XCTAssertTrue(fm.fileExists(atPath: skills.appendingPathComponent("claude-only/SKILL.md").path))
        XCTAssertTrue(fm.fileExists(atPath: skills.appendingPathComponent("cursor-only/SKILL.md").path))
        XCTAssertTrue(fm.fileExists(atPath: skills.appendingPathComponent("clash/SKILL.md").path))
        // Conflict parked, claude version canonical.
        XCTAssertTrue(fm.fileExists(atPath: skills.appendingPathComponent(".conflicts/clash-cursor/SKILL.md").path))
        let clashBody = try String(contentsOf: skills.appendingPathComponent("clash/SKILL.md"), encoding: .utf8)
        XCTAssertTrue(clashBody.contains("claude version"))
        XCTAssertFalse(fm.fileExists(atPath: legacyCursor.path))
        XCTAssertFalse(fm.fileExists(atPath: legacyClaude.path))

        // --- Import external ---
        let imported = try engine.importExternalSkills(git: git)
        XCTAssertTrue(imported.contains("cursor-tool-only"))
        // Divergent "shared" in cursor tool dir parked, not imported over canonical.
        XCTAssertTrue(fm.fileExists(atPath: skills.appendingPathComponent(".conflicts/shared-imported/SKILL.md").path))

        // --- Convert tools ---
        let claudeReport = try engine.convertTool(.claude, backupStamp: "TEST")
        XCTAssertEqual(Set(claudeReport.linked), ["shared", "clash"])
        XCTAssertTrue(claudeReport.issues.isEmpty)
        let cursorReport = try engine.convertTool(.cursor, backupStamp: "TEST")
        XCTAssertEqual(Set(cursorReport.linked), ["shared", "cursor-tool-only"])
        XCTAssertEqual(cursorReport.conflictsParked, ["shared"])

        // Backups exist and contain originals.
        XCTAssertTrue(fm.fileExists(
            atPath: repo.appendingPathComponent(".backups/TEST/claude/shared/SKILL.md").path))

        // Everything is now a symlink into the store.
        XCTAssertEqual(engine.verifyTool(.claude), [])
        XCTAssertEqual(engine.verifyTool(.cursor), [])
        let scan = engine.scanTool(.cursor)
        XCTAssertEqual(scan.realDirs, [])
        XCTAssertEqual(scan.linkedSkills["shared"], "shared")

        // Reading through the link sees canonical content.
        let throughLink = try String(
            contentsOf: cursorDir.appendingPathComponent("shared/SKILL.md"), encoding: .utf8)
        XCTAssertFalse(throughLink.contains("cursor local edit!"))

        // --- Manifest ---
        let manifest = try engine.buildManifest()
        XCTAssertNotNil(manifest.skills["shared"])
        XCTAssertTrue(manifest.skills["shared"]!.isEnabled(for: .claude))
        XCTAssertTrue(manifest.skills["shared"]!.isEnabled(for: .cursor))
        XCTAssertTrue(manifest.skills["cursor-tool-only"]!.isEnabled(for: .cursor))
        XCTAssertFalse(manifest.skills["cursor-tool-only"]!.isEnabled(for: .claude))
        // Hidden .conflicts dir is not a skill.
        XCTAssertNil(manifest.skills[".conflicts"])

        // --- Drift: clean now ---
        XCTAssertEqual(engine.detectDrift(manifest: manifest), [])

        // --- Idempotence: converting again is a no-op that stays green ---
        _ = try engine.convertTool(.claude, backupStamp: "TEST2")
        XCTAssertEqual(engine.verifyTool(.claude), [])
    }

    func testSidecarMergesIntoCanonical() throws {
        let fm = FileManager.default
        // Canonical skill exists; the "codex" tool copy adds agents/openai.yaml.
        try makeSkill(repo.appendingPathComponent("skills"), "animate")
        try git.commitAll(message: "skills")
        try makeSkill(cursorDir, "animate") // stands in for the codex dir in this fixture
        let sidecarDir = cursorDir.appendingPathComponent("animate/agents")
        try fm.createDirectory(at: sidecarDir, withIntermediateDirectories: true)
        try "interface:\n  display_name: Animate\n"
            .write(to: sidecarDir.appendingPathComponent("openai.yaml"), atomically: true, encoding: .utf8)

        // Import absorbs the sidecar instead of parking a conflict.
        try engine.importExternalSkills(git: git)
        let canonicalSidecar = repo.appendingPathComponent("skills/animate/agents/openai.yaml")
        XCTAssertTrue(fm.fileExists(atPath: canonicalSidecar.path))
        XCTAssertFalse(fm.fileExists(
            atPath: repo.appendingPathComponent("skills/.conflicts/animate-imported").path))

        // Conversion links without parking: the copy is now a subset of canonical.
        let report = try engine.convertTool(.cursor, backupStamp: "TEST")
        XCTAssertEqual(report.linked, ["animate"])
        XCTAssertEqual(report.conflictsParked, [])
        // Sidecar readable through the tool's symlink.
        XCTAssertTrue(fm.fileExists(
            atPath: cursorDir.appendingPathComponent("animate/agents/openai.yaml").path))
    }

    func testDriftDetection() throws {
        let fm = FileManager.default
        try makeSkill(repo.appendingPathComponent("skills"), "a")
        try makeSkill(repo.appendingPathComponent("skills"), "b")
        try git.commitAll(message: "skills")

        // claude: proper link for a; real dir for b; foreign link c; orphan link d.
        try engine.enable(skill: "a", for: .claude)
        try makeSkill(claudeDir, "b")
        let elsewhere = tmp.appendingPathComponent("elsewhere/c")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: claudeDir.appendingPathComponent("c"), withDestinationURL: elsewhere)
        try fm.createSymbolicLink(
            at: claudeDir.appendingPathComponent("d"),
            withDestinationURL: repo.appendingPathComponent("skills/deleted"))

        var manifest = try engine.buildManifest()
        // Intent: b enabled for cursor too (but cursor has nothing) → missingLink.
        manifest.skills["b"]?.tools["cursor"] = true

        let drift = engine.detectDrift(manifest: manifest)
        let kinds = Dictionary(grouping: drift, by: \.kind).mapValues { $0.map(\.entryName) }
        XCTAssertEqual(Set(kinds[.notSymlink] ?? []), ["b"])
        XCTAssertEqual(Set(kinds[.wrongTarget] ?? []), ["c"])
        XCTAssertEqual(Set(kinds[.missingLink] ?? []), ["b"])
        XCTAssertTrue(drift.contains { $0.kind == .orphanLink && $0.entryName == "d" })
    }

    func testEnableDisableToggles() throws {
        let fm = FileManager.default
        try makeSkill(repo.appendingPathComponent("skills"), "toggle-me")

        try engine.enable(skill: "toggle-me", for: .cursor)
        let entry = cursorDir.appendingPathComponent("toggle-me")
        let attrs = try fm.attributesOfItem(atPath: entry.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)

        try engine.disable(skill: "toggle-me", for: .cursor)
        XCTAssertFalse(fm.fileExists(atPath: entry.path))

        // Disabling a divergent real dir refuses rather than deleting data.
        try makeSkill(cursorDir, "toggle-me", body: "local changes")
        XCTAssertThrowsError(try engine.disable(skill: "toggle-me", for: .cursor))
        XCTAssertTrue(fm.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path))

        // Enabling for an unknown skill fails.
        XCTAssertThrowsError(try engine.enable(skill: "nope", for: .cursor))
    }
}

extension SyncEngineTests {
    func testRemoveSkill() throws {
        let fm = FileManager.default
        try makeSkill(repo.appendingPathComponent("skills"), "doomed")
        try git.commitAll(message: "skills")
        try engine.enable(skill: "doomed", for: .claude)
        try engine.enable(skill: "doomed", for: .cursor)

        let report = try engine.removeSkill("doomed")
        XCTAssertEqual(Set(report.removedFrom), [.claude, .cursor])
        XCTAssertTrue(report.divergentLeft.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: repo.appendingPathComponent("skills/doomed").path))
        XCTAssertFalse(fm.fileExists(atPath: claudeDir.appendingPathComponent("doomed").path))
        XCTAssertFalse(fm.fileExists(atPath: cursorDir.appendingPathComponent("doomed").path))

        // Removing again fails cleanly.
        XCTAssertThrowsError(try engine.removeSkill("doomed"))
    }

    func testRemoveSkillPreservesDivergentCopies() throws {
        let fm = FileManager.default
        try makeSkill(repo.appendingPathComponent("skills"), "kept")
        try engine.enable(skill: "kept", for: .claude)
        // cursor has a real, locally-edited copy — must survive removal.
        try makeSkill(cursorDir, "kept", body: "precious local edits")

        let report = try engine.removeSkill("kept")
        XCTAssertEqual(report.removedFrom, [.claude])
        XCTAssertEqual(report.divergentLeft, [.cursor])
        XCTAssertFalse(fm.fileExists(atPath: repo.appendingPathComponent("skills/kept").path))
        let surviving = try String(
            contentsOf: cursorDir.appendingPathComponent("kept/SKILL.md"), encoding: .utf8)
        XCTAssertTrue(surviving.contains("precious local edits"))
    }
}

extension SyncEngineTests {
    func testBuildManifestPreservesTags() throws {
        try makeSkill(repo.appendingPathComponent("skills"), "tagged")
        var manifest = try engine.buildManifest()
        manifest.skills["tagged"]?.tags = ["UI/UX"]
        let rebuilt = try engine.buildManifest(existing: manifest)
        XCTAssertEqual(rebuilt.skills["tagged"]?.tags, ["UI/UX"])
    }
}
