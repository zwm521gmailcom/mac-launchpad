import Foundation
import Testing
@testable import LaunchpadCore

struct LayoutStoreTests {
    @Test func missingInvalidAndDuplicateFilesReadAsNoLayout() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("layout.json")
        let store = LayoutStore(fileURL: url)
        #expect(store.load() == nil)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)
        #expect(store.load() == nil)

        let duplicate = """
        {"pages":[{"items":[
          {"type":"app","bundleID":"com.app"},
          {"type":"app","bundleID":"com.app"}
        ]}]}
        """
        try Data(duplicate.utf8).write(to: url)
        #expect(store.load() == nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func roundTripPreservesFolderOrder() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("layout.json")
        let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let layout = Layout(pages: [[
            .app("com.safari"),
            .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["com.mail", "com.maps"]))
        ]])
        let store = LayoutStore(fileURL: url)
        try store.save(layout)
        #expect(store.load() == layout)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func defaultURLLivesInApplicationSupport() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(
            LayoutStore.defaultFileURL(home: home).path
                == "/Users/me/Library/Application Support/MacLaunchpad/layout.json"
        )
    }
}
