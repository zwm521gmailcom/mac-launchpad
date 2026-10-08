import Foundation

public enum LayoutEdit {
    public static let defaultFolderName = "文件夹"

    public static func fresh(records: [AppRecord]) -> Layout {
        let items = records.sorted(by: displayNameOrder).map { PageItem.app($0.bundleID) }
        let pages = stride(from: 0, to: items.count, by: Layout.pageCapacity).map { start in
            Array(items[start..<min(start + Layout.pageCapacity, items.count)])
        }
        return Layout(pages: pages)
    }

    public static func reconcile(layout: Layout, records: [AppRecord]) -> Layout {
        let known = Set(records.map(\.bundleID))
        var placed = Set<String>()
        var pages: [[PageItem]] = []
        for page in layout.pages {
            var next: [PageItem] = []
            for item in page {
                switch item {
                case .app(let bundleID):
                    if known.contains(bundleID), placed.insert(bundleID).inserted {
                        next.append(.app(bundleID))
                    }
                case .folder(var folder):
                    folder.bundleIDs = folder.bundleIDs.filter { known.contains($0) && placed.insert($0).inserted }
                    if !folder.bundleIDs.isEmpty {
                        next.append(.folder(folder))
                    }
                }
            }
            if !next.isEmpty {
                pages.append(next)
            }
        }
        let newcomers = records.filter { !placed.contains($0.bundleID) }.sorted(by: displayNameOrder)
        for record in newcomers {
            if let index = pages.firstIndex(where: { $0.count < Layout.pageCapacity }) {
                pages[index].append(.app(record.bundleID))
            } else {
                pages.append([.app(record.bundleID)])
            }
        }
        return Layout(pages: pages)
    }

    public static func move(
        layout: Layout,
        fromPage: Int,
        fromIndex: Int,
        toPage: Int,
        indexAfterRemoval: Int
    ) -> Layout {
        var pages = layout.pages
        guard pages.indices.contains(fromPage), pages[fromPage].indices.contains(fromIndex) else {
            return layout
        }
        let item = pages[fromPage].remove(at: fromIndex)
        if toPage == pages.count {
            pages.append([])
        }
        guard pages.indices.contains(toPage) else { return layout }
        let bounded = min(max(indexAfterRemoval, 0), pages[toPage].count)
        pages[toPage].insert(item, at: bounded)
        pages = spill(pages)
        pages.removeAll { $0.isEmpty }
        return Layout(pages: pages)
    }

    private static func spill(_ pages: [[PageItem]]) -> [[PageItem]] {
        var pages = pages
        var index = 0
        while index < pages.count {
            while pages[index].count > Layout.pageCapacity {
                let extra = pages[index].removeLast()
                if index + 1 == pages.count {
                    pages.append([])
                }
                pages[index + 1].insert(extra, at: 0)
            }
            index += 1
        }
        return pages
    }

    static func displayNameOrder(_ lhs: AppRecord, _ rhs: AppRecord) -> Bool {
        let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if order == .orderedSame {
            return lhs.bundleID < rhs.bundleID
        }
        return order == .orderedAscending
    }
}
