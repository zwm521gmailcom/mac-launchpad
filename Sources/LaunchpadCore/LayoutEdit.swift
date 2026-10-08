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

    static func displayNameOrder(_ lhs: AppRecord, _ rhs: AppRecord) -> Bool {
        let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if order == .orderedSame {
            return lhs.bundleID < rhs.bundleID
        }
        return order == .orderedAscending
    }
}
