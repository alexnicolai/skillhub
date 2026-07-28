import XCTest
@testable import SkillHub

/// Integration smoke tests against the real ~/ai-skills checkout.
/// Skipped automatically if the repo isn't present (e.g. CI).
final class CatalogSmokeTests: XCTestCase {

    func testLoadsRealCatalog() throws {
        let repo = AppPaths.repoRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: repo.path), "no ~/ai-skills")

        let folders = CatalogService.skillFolders()
        XCTAssertFalse(folders.isEmpty, "expected skills in the repo")

        let skills = CatalogService.loadCatalog(manifest: (try? ManifestIO.load()) ?? .empty())
        XCTAssertEqual(skills.count, folders.count)

        // Every skill parsed a non-empty description from its SKILL.md.
        let missingDescriptions = skills.filter { $0.description.isEmpty }.map(\.name)
        XCTAssertEqual(missingDescriptions, [], "skills with unparsed descriptions")

        // Frontmatter name should match folder name for well-formed skills.
        for skill in skills.prefix(5) {
            let fm = FrontmatterParser.parse(fileURL: skill.folderURL.appendingPathComponent("SKILL.md"))
            XCTAssertEqual(fm.name, skill.name, "frontmatter/folder name mismatch")
        }

        print("Catalog smoke: \(skills.count) skills loaded, migrated=\(CatalogService.isMigrated)")
    }

    func testHashDeterminism() throws {
        let folders = CatalogService.skillFolders()
        guard let sample = folders.values.first else { throw XCTSkip("no skills") }
        let h1 = try HashService.hashFolder(sample)
        let h2 = try HashService.hashFolder(sample)
        XCTAssertEqual(h1, h2)
        XCTAssertTrue(h1.hasPrefix("sha256:"))
    }
}
