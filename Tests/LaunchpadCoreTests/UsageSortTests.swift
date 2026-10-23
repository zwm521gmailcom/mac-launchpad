import Foundation
import Testing
@testable import LaunchpadCore

struct UsageSortTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func mostUsedComeFirstAndUnusedKeepTheirOrder() {
        let layout = Layout(pages: [[.app("a"), .app("b")], [.app("c"), .app("d"), .app("e")]])
        let usage = [
            "d": LaunchUsage(count: 50, lastUsed: now),
            "b": LaunchUsage(count: 5, lastUsed: now)
        ]
        let sorted = UsageSort.arrange(layout, usage: usage, capacity: 2)
        #expect(sorted.pages.map { $0.flatMap(\.bundleIDs) } == [["d", "b"], ["a", "c"], ["e"]])
        #expect(layout.pages.flatMap { $0 }.flatMap(\.bundleIDs) == ["a", "b", "c", "d", "e"])
    }

    @Test func tiesGoToTheMostRecentlyUsed() {
        let layout = Layout(pages: [[.app("old"), .app("new")]])
        let usage = [
            "old": LaunchUsage(count: 3, lastUsed: now.addingTimeInterval(-86_400)),
            "new": LaunchUsage(count: 3, lastUsed: now)
        ]
        #expect(UsageSort.arrange(layout, usage: usage, capacity: 10).pages[0].flatMap(\.bundleIDs) == ["new", "old"])
    }

    @Test func foldersRankByTheirMembersTotal() {
        let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        let folder = FolderItem(id: folderID, name: "工具", bundleIDs: ["x", "y"])
        let layout = Layout(pages: [[.app("solo"), .folder(folder)]])
        let usage = [
            "solo": LaunchUsage(count: 10, lastUsed: now),
            "x": LaunchUsage(count: 6, lastUsed: now),
            "y": LaunchUsage(count: 6, lastUsed: now)
        ]
        let first = UsageSort.arrange(layout, usage: usage, capacity: 10).pages[0][0]
        #expect(first == .folder(folder))
    }

    @Test func mergeKeepsLargerCountAndLaterDate() {
        let early = now.addingTimeInterval(-100)
        let merged = UsageSort.merge(
            ["a": LaunchUsage(count: 9, lastUsed: early), "b": LaunchUsage(count: 1, lastUsed: now)],
            ["a": LaunchUsage(count: 2, lastUsed: now)]
        )
        #expect(merged["a"] == LaunchUsage(count: 9, lastUsed: now))
        #expect(merged["b"]?.count == 1)
    }

    @Test func emptyLayoutStaysEmpty() {
        #expect(UsageSort.arrange(Layout(pages: []), usage: [:], capacity: 5).pages.isEmpty)
    }
}
