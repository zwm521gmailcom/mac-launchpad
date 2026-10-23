import Foundation

public enum UsageSort {
    /// 按使用次数从多到少重排整张网格；次数相同看最近一次使用，再相同保持原排列顺序。
    /// 文件夹作为一个整体参与排序，次数取里面所有应用之和。只生成显示用的布局，不改保存的排列。
    public static func arrange(_ layout: Layout, usage: [String: LaunchUsage], capacity: Int) -> Layout {
        let items = layout.pages.flatMap { $0 }
        guard !items.isEmpty else { return Layout(pages: []) }
        let ranked = items.enumerated()
            .map { (offset: $0.offset, item: $0.element, key: key(for: $0.element, usage: usage)) }
            .sorted { a, b in
                if a.key.count != b.key.count { return a.key.count > b.key.count }
                if a.key.last != b.key.last { return a.key.last > b.key.last }
                return a.offset < b.offset
            }
            .map(\.item)
        let size = max(1, capacity)
        let pages = stride(from: 0, to: ranked.count, by: size).map {
            Array(ranked[$0..<min($0 + size, ranked.count)])
        }
        return Layout(pages: pages)
    }

    /// 合并两份记录：次数取较大的一份，时间取较近的一次。
    public static func merge(_ a: [String: LaunchUsage], _ b: [String: LaunchUsage]) -> [String: LaunchUsage] {
        a.merging(b) { left, right in
            LaunchUsage(count: max(left.count, right.count), lastUsed: max(left.lastUsed, right.lastUsed))
        }
    }

    private static func key(for item: PageItem, usage: [String: LaunchUsage]) -> (count: Int, last: Date) {
        var count = 0
        var last = Date.distantPast
        for bundleID in item.bundleIDs {
            guard let entry = usage[bundleID] else { continue }
            count += entry.count
            last = max(last, entry.lastUsed)
        }
        return (count, last)
    }
}
