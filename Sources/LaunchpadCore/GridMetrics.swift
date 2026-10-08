import CoreGraphics
import Foundation

public struct GridMetrics: Equatable, Sendable {
    public static let labelBlock: CGFloat = 22
    public static let minimumIcon: CGFloat = 64
    public static let maximumIcon: CGFloat = 168
    public var icon: CGFloat
    public var columns: Int
    public var rows: Int

    public var capacity: Int { columns * rows }

    public init(icon: CGFloat, columns: Int, rows: Int) {
        self.icon = icon
        self.columns = columns
        self.rows = rows
    }

    /// 按图标边长估算这一页能排下多少列、多少行。调用方再用剩余空间把间距拉开，让整页铺满。
    public static func fitting(width: CGFloat, height: CGFloat, icon: CGFloat) -> GridMetrics {
        let icon = min(maximumIcon, max(minimumIcon, icon))
        let columnPitch = icon * 2.15
        let rowPitch = icon + labelBlock + icon * 0.38
        let columns = max(1, min(11, Int(max(width, 1) / columnPitch)))
        let rows = max(1, min(7, Int(max(height, 1) / rowPitch)))
        return GridMetrics(icon: icon, columns: columns, rows: rows)
    }
}
