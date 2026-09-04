import XCTest
@testable import SkillHub

final class SkillModelTests: XCTestCase {
    private func skill(description: String, short: String? = nil) -> Skill {
        Skill(name: "x", description: description, shortDescription: short,
              folderURL: URL(fileURLWithPath: "/tmp/x"), contentHash: "", provenance: .local,
              intendedTools: [], liveTools: [], updateAvailable: false, usageCount: 0, lastUsed: nil)
    }

    func testSummaryKeepsAbbreviationsAndDomains() {
        XCTAssertEqual(skill(description: "Use for hovers, e.g. buttons (animations.dev course). Triggers on x.").summary,
                       "Use for hovers, e.g. buttons (animations.dev course)")
        XCTAssertEqual(skill(description: "Single sentence without trailing period").summary,
                       "Single sentence without trailing period")
        XCTAssertEqual(skill(description: "Ends with a period.").summary, "Ends with a period")
        XCTAssertEqual(skill(description: "Long", short: "Short wins").summary, "Short wins")
    }

    func testToolOverrideRoundTrip() {
        let original = Tool.overrides
        defer { Tool.overrides = original }
        Tool.kiro.override = true
        XCTAssertEqual(Tool.kiro.override, true)
        XCTAssertTrue(Tool.kiro.isActive)
        Tool.kiro.override = nil
        XCTAssertNil(Tool.kiro.override)
        XCTAssertEqual(Tool.kiro.isActive, Tool.kiro.isDetected)
    }
}
