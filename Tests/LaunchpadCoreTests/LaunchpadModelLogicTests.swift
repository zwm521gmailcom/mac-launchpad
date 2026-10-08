import Foundation
import Testing
@testable import LaunchpadCore

struct LaunchpadModelLogicTests {
    @Test func nilStoreLayoutBecomesFreshAndMemoryLayoutIsKept() {
        let records = [
            AppRecord(bundleID: "com.app", displayName: "Zzz", url: URL(fileURLWithPath: "/Applications/App.app")),
            AppRecord(bundleID: "com.kept", displayName: "Aaa", url: URL(fileURLWithPath: "/Applications/Kept.app"))
        ]
        let fresh = SessionPolicy.layoutForShow(memory: nil, stored: nil, records: [records[0]])
        #expect(fresh.pages == [[.app("com.app")]])
        let memory = Layout(pages: [[.app("com.app"), .app("com.kept")]])
        let stored = Layout(pages: [[.app("com.stored")]])
        let kept = SessionPolicy.layoutForShow(memory: memory, stored: stored, records: records)
        #expect(kept.pages == [[.app("com.app"), .app("com.kept")]])
        let cold = SessionPolicy.layoutForShow(memory: nil, stored: memory, records: records)
        #expect(cold.pages == [[.app("com.app"), .app("com.kept")]])
    }

    @Test func launchFailureMessageUsesDisplayName() {
        #expect(SessionPolicy.launchFailureMessage(displayName: "Safari") == "无法打开Safari")
    }
}
