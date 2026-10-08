import Foundation
import Testing
@testable import LaunchpadCore

struct AppSearchTests {
    @Test func filtersInLayoutOrderWithoutChangingLayoutOrTruncating() {
        let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let folderMembers = ["com.mail", "com.maps"]
        let layout = Layout(pages: [[
            .app("com.notes"),
            .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: folderMembers)),
            .app("com.music")
        ]])
        let records = [
            record("com.music", "Music"),
            record("com.mail", "Mail"),
            record("com.notes", "Notes"),
            record("com.maps", "Maps")
        ]
        let matches = AppSearch.filter(layout: layout, records: records, query: "ma")
        #expect(matches.map(\.bundleID) == ["com.mail", "com.maps"])
        #expect(layout.pages[0].count == 3)
        let manyIDs = (1...36).map { "com.item.\($0)" }
        let manyLayout = Layout(pages: [manyIDs.map { .app($0) }])
        let manyRecords = manyIDs.map { record($0, "Gamma \($0)") }
        #expect(AppSearch.filter(layout: manyLayout, records: manyRecords, query: "gamma").count == 36)
    }

    private func record(_ bundleID: String, _ name: String) -> AppRecord {
        AppRecord(bundleID: bundleID, displayName: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }
}
