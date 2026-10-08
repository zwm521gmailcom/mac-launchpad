import Foundation
import Testing
@testable import LaunchpadCore

struct FolderEditTests {
    private let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    @Test func dropOnAppCreatesFolderAtTarget() {
        let layout = Layout(pages: [[.app("a"), .app("b"), .app("c")]])
        let next = LayoutEdit.makeFolder(layout: layout, draggedBundleID: "a", ontoBundleID: "b", folderID: folderID)
        #expect(next.pages[0] == [
            .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["b", "a"])),
            .app("c"),
        ])
    }

    @Test func dropOnFolderAppendsAndRemovingLastMemberDeletesFolder() {
        let layout = Layout(pages: [[.app("a"), .folder(FolderItem(id: folderID, name: "工作", bundleIDs: ["b"]))]])
        let added = LayoutEdit.addToFolder(layout: layout, bundleID: "a", folderID: folderID)
        #expect(added.pages[0] == [
            .folder(FolderItem(id: folderID, name: "工作", bundleIDs: ["b", "a"])),
        ])
        let removed = LayoutEdit.moveOutOfFolder(layout: added, bundleID: "b", folderID: folderID)
        #expect(removed.pages == [[
            .folder(FolderItem(id: folderID, name: "工作", bundleIDs: ["a"])),
            .app("b"),
        ]])
        let emptied = LayoutEdit.moveOutOfFolder(layout: removed, bundleID: "a", folderID: folderID)
        #expect(emptied.pages == [[.app("b"), .app("a")]])
    }

    @Test func moveOutOfFullPageSpillsBeforeDeletingEmptyFolder() {
        var page = (0..<34).map { PageItem.app("a.\($0)") }
        page.append(.folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["inside"])))
        let next = LayoutEdit.moveOutOfFolder(layout: Layout(pages: [page]), bundleID: "inside", folderID: folderID)
        #expect(next.pages[0].count == 34)
        #expect(next.pages[1] == [.app("inside")])
    }

    @Test func blankRenameRestoresDefaultName() {
        let layout = Layout(pages: [[.folder(FolderItem(id: folderID, name: "工作", bundleIDs: ["a"]))]])
        let next = LayoutEdit.renameFolder(layout: layout, folderID: folderID, name: "  ")
        #expect(next.pages[0][0] == .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["a"])))
    }

    @Test func reorderInsideFolderDoesNotCreateAnotherFolder() {
        let layout = Layout(pages: [[.folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["a", "b", "c"]))]])
        let next = LayoutEdit.reorderFolder(layout: layout, folderID: folderID, fromIndex: 0, indexAfterRemoval: 1)
        #expect(next.pages[0][0] == .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["b", "a", "c"])))
    }
}
