import XCTest
@testable import SkillHub

final class AppVersionTests: XCTestCase {
    func testIsNewerComparison() {
        XCTAssertTrue(AppVersion.isNewer("1.0.2", than: "1.0.1"))
        XCTAssertTrue(AppVersion.isNewer("v1.1", than: "1.0.9"))
        XCTAssertTrue(AppVersion.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(AppVersion.isNewer("1.0.1", than: "1.0.1"))
        XCTAssertFalse(AppVersion.isNewer("v1.0.1", than: "1.0.1"))
        XCTAssertFalse(AppVersion.isNewer("0.9.9", than: "1.0.0"))
        XCTAssertFalse(AppVersion.isNewer("1.0", than: "1.0.0"))
    }

    func testAgainstCurrent() {
        XCTAssertTrue(AppVersion.isNewer("v99.0.0"))
        XCTAssertFalse(AppVersion.isNewer(AppVersion.current))
        XCTAssertFalse(AppVersion.isNewer("0.0.1"))
    }
}
