import CoreGraphics
import Foundation
import Testing
@testable import LaunchpadCore

struct GridHitTests {
    @Test func iconCenterCreatesFolderAndHalvesReorder() {
        let cells = [
            GridCell(index: 0, bundleID: "com.a", iconFrame: CGRect(x: 0, y: 0, width: 100, height: 100), cellFrame: CGRect(x: 0, y: 0, width: 100, height: 120)),
            GridCell(index: 1, bundleID: "com.b", iconFrame: CGRect(x: 120, y: 0, width: 100, height: 100), cellFrame: CGRect(x: 120, y: 0, width: 100, height: 120)),
        ]
        let center = GridHit.drop(at: CGPoint(x: 170, y: 50), cells: cells, draggedIsApp: true, allowsNewFolder: true)
        #expect(center == .makeFolder(bundleID: "com.b"))
        let front = GridHit.drop(at: CGPoint(x: 130, y: 50), cells: cells, draggedIsApp: true, allowsNewFolder: true)
        #expect(front == .insert(displayedIndex: 1))
        let folderDraggedOverCenter = GridHit.drop(at: CGPoint(x: 170, y: 50), cells: cells, draggedIsApp: false, allowsNewFolder: true)
        #expect(folderDraggedOverCenter == .insert(displayedIndex: 2))
    }

    @Test func secondRowGapUsesThatRow() {
        let cells = [
            GridCell(index: 0, bundleID: "a", iconFrame: CGRect(x: 0, y: 0, width: 80, height: 80), cellFrame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            GridCell(index: 1, bundleID: "b", iconFrame: CGRect(x: 120, y: 0, width: 80, height: 80), cellFrame: CGRect(x: 120, y: 0, width: 100, height: 100)),
            GridCell(index: 2, bundleID: "c", iconFrame: CGRect(x: 0, y: 140, width: 80, height: 80), cellFrame: CGRect(x: 0, y: 140, width: 100, height: 100)),
            GridCell(index: 3, bundleID: "d", iconFrame: CGRect(x: 120, y: 140, width: 80, height: 80), cellFrame: CGRect(x: 120, y: 140, width: 100, height: 100)),
        ]
        let drop = GridHit.drop(at: CGPoint(x: 110, y: 180), cells: cells, draggedIsApp: true, allowsNewFolder: true)
        #expect(drop == .insert(displayedIndex: 3))
    }

    @Test func folderIconCenterAddsToFolder() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!
        let cell = GridCell(index: 0, folderID: id, iconFrame: CGRect(x: 0, y: 0, width: 100, height: 100), cellFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let drop = GridHit.drop(at: CGPoint(x: 50, y: 50), cells: [cell], draggedIsApp: true, allowsNewFolder: true)
        #expect(drop == .addToFolder(id))
    }

    @Test func folderPageNeverCreatesFolder() {
        let cell = GridCell(index: 0, iconFrame: CGRect(x: 0, y: 0, width: 100, height: 100), cellFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let drop = GridHit.drop(at: CGPoint(x: 50, y: 50), cells: [cell], draggedIsApp: true, allowsNewFolder: false)
        #expect(drop == .insert(displayedIndex: 1))
    }

    @Test func sameListIndexMovesBackByOneAfterRemoval() {
        #expect(DragIndex.afterRemoval(fromIndex: 0, displayedIndex: 2, sameList: true) == 1)
        #expect(DragIndex.afterRemoval(fromIndex: 2, displayedIndex: 0, sameList: true) == 0)
    }

    @Test func screenEdgeUses24PointInset() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(GridHit.edge(at: CGPoint(x: 10, y: 40), in: bounds) == -1)
        #expect(GridHit.edge(at: CGPoint(x: 990, y: 40), in: bounds) == 1)
        #expect(GridHit.edge(at: CGPoint(x: 100, y: 40), in: bounds) == nil)
    }
}
