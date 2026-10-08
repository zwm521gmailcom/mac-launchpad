import Foundation
import Testing
@testable import LaunchpadCore

struct AppRecordTests {
    @Test func identityIsBundleID() {
        let record = AppRecord(
            bundleID: "com.example.Safari",
            displayName: "Safari",
            url: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        #expect(record.id == "com.example.Safari")
    }
}
