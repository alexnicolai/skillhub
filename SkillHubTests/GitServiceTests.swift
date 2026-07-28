import XCTest
@testable import SkillHub

final class GitServiceTests: XCTestCase {
    var tmp: URL!
    var repo: URL!
    var git: GitService!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-git-\(UUID().uuidString)")
        repo = tmp.appendingPathComponent("work")
        let origin = tmp.appendingPathComponent("origin.git")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)

        // Bare origin + working clone wired to it.
        try shell(["git", "init", "--bare", "-b", "main", origin.path])
        git = GitService(repoRoot: repo)
        try git.run(["init", "-b", "main"])
        try git.run(["config", "user.email", "test@example.com"])
        try git.run(["config", "user.name", "Test"])
        try git.run(["remote", "add", "origin", origin.path])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func shell(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }

    func testStatusCommitPushCycle() throws {
        // Untracked file shows up in status.
        try "hello".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        var status = try git.status()
        XCTAssertEqual(status.entries.map(\.path), ["a.txt"])
        XCTAssertEqual(status.entries.first?.code, "??")

        // Commit + push to the bare origin.
        try git.commitAll(message: "first")
        try git.push()
        status = try git.status()
        XCTAssertTrue(status.isClean)
        XCTAssertEqual(status.ahead, 0)

        // Second commit without push → ahead 1.
        try "more".write(to: repo.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try git.commitAll(message: "second")
        status = try git.status()
        XCTAssertEqual(status.ahead, 1)
        XCTAssertEqual(status.branch, "main")

        XCTAssertEqual(try git.lastCommits(5).count, 2)
        XCTAssertFalse(try git.hasMergeConflicts())
    }

    func testErrorSurfacesStderr() {
        XCTAssertThrowsError(try git.run(["nonsense-subcommand"])) { error in
            guard let gitError = error as? GitService.GitError else {
                return XCTFail("wrong error type")
            }
            XCTAssertNotEqual(gitError.exitCode, 0)
            XCTAssertFalse(gitError.stderr.isEmpty)
        }
    }
}
