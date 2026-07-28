import XCTest
@testable import SkillHub

final class FrontmatterParserTests: XCTestCase {

    func testFlatFrontmatter() {
        let fm = FrontmatterParser.parse("""
        ---
        name: my-skill
        description: Does a thing.
        ---
        # Body
        """)
        XCTAssertEqual(fm.name, "my-skill")
        XCTAssertEqual(fm.description, "Does a thing.")
        XCTAssertNil(fm.shortDescription)
    }

    func testMetadataShortDescription() {
        let fm = FrontmatterParser.parse("""
        ---
        name: css-animations
        description: Animate with CSS alone.
        metadata:
          short-description: Animate with CSS the way the course teaches
        ---
        """)
        XCTAssertEqual(fm.name, "css-animations")
        XCTAssertEqual(fm.shortDescription, "Animate with CSS the way the course teaches")
    }

    func testFoldedBlockScalar() {
        let fm = FrontmatterParser.parse("""
        ---
        name: clerk-cli
        description: >-
          Operate the Clerk CLI for authentication,
          user management, and API calls.
        ---
        """)
        XCTAssertEqual(fm.name, "clerk-cli")
        XCTAssertEqual(fm.description, "Operate the Clerk CLI for authentication, user management, and API calls.")
    }

    func testPlainMultilineScalar() {
        // The clerk-custom-ui case: continuation lines without >- markers.
        let fm = FrontmatterParser.parse("""
        ---
        name: clerk-custom-ui
        description: Custom authentication flows and component appearance - hooks (useSignIn,
          useSignUp), themes, colors, fonts, CSS. Use for custom sign-in/sign-up flows, appearance
          styling, visual customization, branding.
        allowed-tools: WebFetch
        license: MIT
        metadata:
          author: clerk
          version: 2.3.0
        ---
        # Body
        """)
        XCTAssertEqual(fm.name, "clerk-custom-ui")
        XCTAssertEqual(
            fm.description,
            "Custom authentication flows and component appearance - hooks (useSignIn, useSignUp), themes, colors, fonts, CSS. Use for custom sign-in/sign-up flows, appearance styling, visual customization, branding."
        )
        XCTAssertEqual(fm.fields.map(\.key), ["name", "description", "allowed-tools", "license", "metadata.author", "metadata.version"])
        XCTAssertEqual(fm.fields.first { $0.key == "metadata.version" }?.value, "2.3.0")
    }

    func testBodyStripsFrontmatter() {
        let text = """
        ---
        name: x
        description: y
        ---

        # Heading
        Content here.
        """
        XCTAssertEqual(FrontmatterParser.body(of: text), "# Heading\nContent here.")
        XCTAssertEqual(FrontmatterParser.body(of: "# No frontmatter"), "# No frontmatter")
    }

    func testQuotedValues() {
        let fm = FrontmatterParser.parse("""
        ---
        name: "quoted-skill"
        description: 'single quoted'
        ---
        """)
        XCTAssertEqual(fm.name, "quoted-skill")
        XCTAssertEqual(fm.description, "single quoted")
    }

    func testNoFrontmatter() {
        let fm = FrontmatterParser.parse("# Just a doc\nNo frontmatter here.")
        XCTAssertNil(fm.name)
        XCTAssertNil(fm.description)
    }

    func testManifestRoundTrip() throws {
        var manifest = Manifest.empty()
        manifest.skills["test"] = ManifestSkill(
            description: "d", shortDescription: "s",
            contentHash: "sha256:abc",
            source: Provenance(sourceType: .github, source: "o/r", sourceUrl: "https://github.com/o/r.git",
                               skillPath: "skills/test", upstreamHash: "deadbeef",
                               installedAt: Date(timeIntervalSince1970: 1_700_000_000),
                               updatedAt: nil),
            tools: ["claude": true, "cursor": false],
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(Manifest.self, from: data)
        XCTAssertEqual(back.skills["test"]?.contentHash, "sha256:abc")
        XCTAssertEqual(back.skills["test"]?.source.source, "o/r")
        XCTAssertTrue(back.skills["test"]?.isEnabled(for: .claude) ?? false)
        XCTAssertFalse(back.skills["test"]?.isEnabled(for: .cursor) ?? true)

        // Stable ordering: encoding twice yields identical bytes.
        XCTAssertEqual(data, try encoder.encode(manifest))
    }
}
