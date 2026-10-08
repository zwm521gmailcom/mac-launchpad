import CoreGraphics
import Foundation

public struct GridCell: Equatable {
    public var index: Int
    public var bundleID: String?
    public var folderID: UUID?
    public var iconFrame: CGRect
    public var cellFrame: CGRect

    public init(index: Int, bundleID: String? = nil, folderID: UUID? = nil, iconFrame: CGRect, cellFrame: CGRect) {
        self.index = index
        self.bundleID = bundleID
        self.folderID = folderID
        self.iconFrame = iconFrame
        self.cellFrame = cellFrame
    }
}

public enum GridDrop: Equatable {
    case insert(displayedIndex: Int)
    case makeFolder(bundleID: String)
    case addToFolder(UUID)
}

public enum DragIndex {
    public static func afterRemoval(fromIndex: Int, displayedIndex: Int, sameList: Bool) -> Int {
        if sameList, fromIndex < displayedIndex { return displayedIndex - 1 }
        return displayedIndex
    }
}

public enum GridHit {
    public static func drop(
        at point: CGPoint,
        cells: [GridCell],
        draggedIsApp: Bool,
        allowsNewFolder: Bool
    ) -> GridDrop {
        if let cell = cells.first(where: { $0.iconFrame.contains(point) }),
           allowsNewFolder,
           draggedIsApp,
           center(of: cell.iconFrame).contains(point) {
            if let folderID = cell.folderID { return .addToFolder(folderID) }
            if let bundleID = cell.bundleID { return .makeFolder(bundleID: bundleID) }
        }
        if let cell = cells.first(where: { $0.cellFrame.contains(point) }) {
            let displayedIndex = point.x < cell.cellFrame.midX ? cell.index : cell.index + 1
            return .insert(displayedIndex: displayedIndex)
        }
        return .insert(displayedIndex: insertionIndex(point, cells))
    }

    private static func insertionIndex(_ point: CGPoint, _ cells: [GridCell]) -> Int {
        guard !cells.isEmpty else { return 0 }
        let nearestY = cells.map(\.cellFrame.midY).min { abs($0 - point.y) < abs($1 - point.y) } ?? point.y
        let row = cells.filter { abs($0.cellFrame.midY - nearestY) < 1 }.sorted { $0.cellFrame.minX < $1.cellFrame.minX }
        if let next = row.first(where: { $0.cellFrame.midX > point.x }) {
            return next.index
        }
        return (row.last?.index ?? -1) + 1
    }

    public static func edge(at point: CGPoint, in bounds: CGRect, inset: CGFloat = 24) -> Int? {
        if point.x <= bounds.minX + inset { return -1 }
        if point.x >= bounds.maxX - inset { return 1 }
        return nil
    }

    private static func center(of frame: CGRect) -> CGRect {
        frame.insetBy(dx: frame.width * 0.2, dy: frame.height * 0.2)
    }
}
