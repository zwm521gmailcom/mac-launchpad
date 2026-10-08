import XCTest
@testable import LaunchpadCore

final class AppRecordTests: XCTestCase {
    func testIdentityIsBundleID() {
        let record = AppRecord(
            bundleID: "com.example.Safari",
            displayName: "Safari",
            url: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        XCTAssertEqual(record.id, "com.example.Safari")
    }
}
