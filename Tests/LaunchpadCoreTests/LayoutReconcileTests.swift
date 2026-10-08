import Foundation
import Testing
@testable import LaunchpadCore

struct LayoutReconcileTests {
    @Test func freshSortsByLocalizedNameThenBundleIDAndPagesBy35() {
        let records = [
            record("com.b", "beta"),
            record("com.a2", "Alpha"),
            record("com.a1", "alpha"),
        ] + (1...35).map { record("com.n\($0)", "n\($0)") }
        let layout = LayoutEdit.fresh(records: records)
        #expect(layout.pages[0].count == 35)
        #expect(layout.pages[1].count == 3)
        #expect(layout.pages[0].first == .app("com.a1"))
        #expect(layout.pages[0][1] == .app("com.a2"))
    }

    @Test func reconcileDropsMissingAppsAndEmptyFoldersThenFillsFirstGap() {
        let folder = FolderItem(id: fixedID, name: "文件夹", bundleIDs: ["gone.folder", "kept.folder"])
        let full = (0..<34).map { PageItem.app("keep.\($0)") } + [.folder(folder)]
        let layout = Layout(pages: [full, [.app("gone.page")], [.app("tail")]])
        let records = (0..<34).map { record("keep.\($0)", "K\($0)") }
            + [record("kept.folder", "Folder App"), record("tail", "Tail"), record("new.app", "New")]
        let next = LayoutEdit.reconcile(layout: layout, records: records)
        #expect(next.pages.count == 2)
        #expect(next.pages[0].count == 35)
        #expect(next.pages[0].last == .folder(FolderItem(id: fixedID, name: "文件夹", bundleIDs: ["kept.folder"])))
        #expect(next.pages[1].contains(.app("gone.page")) == false)
        #expect(next.pages[1].last == .app("new.app"))
    }

    @Test func newAppStartsAPageWhenExistingPagesAreFull() {
        let existing = (0..<35).map { record("a.\($0)", "A\($0)") }
        let layout = Layout(pages: [existing.map { .app($0.bundleID) }])
        let next = LayoutEdit.reconcile(layout: layout, records: existing + [record("new.app", "New")])
        #expect(next.pages.count == 2)
        #expect(next.pages[1] == [.app("new.app")])
    }

    private let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func record(_ bundleID: String, _ name: String) -> AppRecord {
        AppRecord(bundleID: bundleID, displayName: name, url: URL(fileURLWithPath: "/Applications/\(bundleID).app"))
    }
}
