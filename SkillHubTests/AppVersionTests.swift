import XCTest
@testable import SkillHub

final class AppVersionTests: XCTestCase {
    func testIsNewer() {
        XCTAssertTrue(AppVersion.isNewer("v99.0.0"))
        XCTAssertTrue(AppVersion.isNewer("99.0"))
        XCTAssertFalse(AppVersion.isNewer(AppVersion.current))
        XCTAssertFalse(AppVersion.isNewer("v" + AppVersion.current))
        XCTAssertFalse(AppVersion.isNewer("0.9.9"))
        XCTAssertFalse(AppVersion.isNewer("1.0.0"))   // current is 1.0.1+
        XCTAssertTrue(AppVersion.isNewer("1.0.2"))
        XCTAssertTrue(AppVersion.isNewer("1.1"))
    }
}
