import Foundation
import Testing
@testable import LaunchpadCore

struct AppCatalogDedupeTests {
    @Test func prefersLowerPriorityNumber() {
        let kept = AppCatalog.dedupe([
            candidate("com.app", "/System/Applications/App.app", priority: 5),
            candidate("com.app", "/Users/me/Applications/App.app", priority: 1),
            candidate("com.app", "/Applications/App.app", priority: 2),
            candidate("com.app", "/opt/homebrew/Caskroom/app/1/App.app", priority: 3)
        ])
        #expect(kept.map(\.url.path) == ["/Users/me/Applications/App.app"])
    }

    @Test func caskroomBeatsSystem() {
        let kept = AppCatalog.dedupe([
            candidate("com.app", "/System/Applications/App.app", priority: 5),
            candidate("com.app", "/opt/homebrew/Caskroom/app/1/App.app", priority: 3)
        ])
        #expect(kept.map(\.url.path) == ["/opt/homebrew/Caskroom/app/1/App.app"])
    }

    @Test func samePriorityKeepsLexicographicallySmallerPath() {
        let kept = AppCatalog.dedupe([
            candidate("com.app", "/opt/homebrew/Caskroom/app/2.0/App.app", priority: 3),
            candidate("com.app", "/opt/homebrew/Caskroom/app/1.0/App.app", priority: 3)
        ])
        #expect(kept.map(\.url.path) == ["/opt/homebrew/Caskroom/app/1.0/App.app"])
    }

    private func candidate(_ bundleID: String, _ path: String, priority: Int) -> CatalogCandidate {
        CatalogCandidate(
            record: AppRecord(bundleID: bundleID, displayName: "App", url: URL(fileURLWithPath: path)),
            priority: priority
        )
    }
}
