import Foundation
import Testing
@testable import LaunchpadCore

struct LayoutModelTests {
    @Test func pageItemExposesMemberIDsInOrder() {
        let folder = FolderItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "文件夹",
            bundleIDs: ["com.b", "com.a"]
        )
        #expect(PageItem.app("com.a").bundleIDs == ["com.a"])
        #expect(PageItem.folder(folder).bundleIDs == ["com.b", "com.a"])
        #expect(Layout.pageCapacity == 35)
    }
}
