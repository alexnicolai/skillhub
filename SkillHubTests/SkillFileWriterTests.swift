import XCTest
@testable import SkillHub

final class SkillFileWriterTests: XCTestCase {

    func testWriteThroughSymlinkLandsInCanonicalFile() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("skillhub-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }

        // canonical/skill/SKILL.md  +  tooldir/skill -> canonical/skill
        let canonicalSkill = tmp.appendingPathComponent("canonical/skill")
        let toolDir = tmp.appendingPathComponent("tooldir")
        try fm.createDirectory(at: canonicalSkill, withIntermediateDirectories: true)
        try fm.createDirectory(at: toolDir, withIntermediateDirectories: true)
        let canonicalFile = canonicalSkill.appendingPathComponent("SKILL.md")
        try "original".write(to: canonicalFile, atomically: true, encoding: .utf8)
        let link = toolDir.appendingPathComponent("skill")
        try fm.createSymbolicLink(at: link, withDestinationURL: canonicalSkill)

        // Write via the symlinked path.
        let written = try SkillFileWriter.write("edited", to: link.appendingPathComponent("SKILL.md"))

        // The canonical file changed, and the write resolved to the canonical path.
        XCTAssertEqual(try String(contentsOf: canonicalFile, encoding: .utf8), "edited")
        XCTAssertEqual(written.resolvingSymlinksInPath().path, canonicalFile.resolvingSymlinksInPath().path)

        // The symlink is still a symlink (atomic write didn't replace it with a file).
        let attrs = try fm.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
    }
}
