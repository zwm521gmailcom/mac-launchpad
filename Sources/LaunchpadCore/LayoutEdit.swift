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

    public static func makeFolder(
        layout: Layout,
        draggedBundleID: String,
        ontoBundleID: String,
        folderID: UUID
    ) -> Layout {
        guard draggedBundleID != ontoBundleID,
              let dragged = locateApp(layout, draggedBundleID),
              let target = locateApp(layout, ontoBundleID) else { return layout }
        var pages = layout.pages
        pages[dragged.page].remove(at: dragged.index)
        var targetIndex = target.index
        if dragged.page == target.page, dragged.index < target.index {
            targetIndex -= 1
        }
        guard pages[target.page].indices.contains(targetIndex),
              case .app(let bundleID) = pages[target.page][targetIndex],
              bundleID == ontoBundleID else { return layout }
        pages[target.page][targetIndex] = .folder(FolderItem(
            id: folderID,
            name: defaultFolderName,
            bundleIDs: [ontoBundleID, draggedBundleID]
        ))
        pages.removeAll { $0.isEmpty }
        return Layout(pages: pages)
    }

    public static func addToFolder(layout: Layout, bundleID: String, folderID: UUID) -> Layout {
        guard let app = locateApp(layout, bundleID), let folder = locateFolder(layout, folderID) else { return layout }
        var pages = layout.pages
        pages[app.page].remove(at: app.index)
        var folderIndex = folder.index
        if app.page == folder.page, app.index < folder.index {
            folderIndex -= 1
        }
        guard pages[folder.page].indices.contains(folderIndex),
              case .folder(var item) = pages[folder.page][folderIndex],
              item.id == folderID else { return layout }
        item.bundleIDs.append(bundleID)
        pages[folder.page][folderIndex] = .folder(item)
        pages.removeAll { $0.isEmpty }
        return Layout(pages: pages)
    }

    public static func moveOutOfFolder(layout: Layout, bundleID: String, folderID: UUID) -> Layout {
        guard let located = locateFolder(layout, folderID),
              case .folder(var folder) = layout.pages[located.page][located.index],
              folder.bundleIDs.contains(bundleID) else { return layout }
        var pages = layout.pages
        folder.bundleIDs.removeAll { $0 == bundleID }
        pages[located.page][located.index] = .folder(folder)
        pages[located.page].insert(.app(bundleID), at: pages[located.page].count)
        pages = spill(pages)
        if folder.bundleIDs.isEmpty, let again = locateFolder(Layout(pages: pages), folderID) {
            pages[again.page].remove(at: again.index)
        }
        pages.removeAll { $0.isEmpty }
        return Layout(pages: pages)
    }

    public static func reorderFolder(
        layout: Layout,
        folderID: UUID,
        fromIndex: Int,
        indexAfterRemoval: Int
    ) -> Layout {
        guard let located = locateFolder(layout, folderID),
              case .folder(var folder) = layout.pages[located.page][located.index],
              folder.bundleIDs.indices.contains(fromIndex) else { return layout }
        let bundleID = folder.bundleIDs.remove(at: fromIndex)
        let index = min(max(indexAfterRemoval, 0), folder.bundleIDs.count)
        folder.bundleIDs.insert(bundleID, at: index)
        var pages = layout.pages
        pages[located.page][located.index] = .folder(folder)
        return Layout(pages: pages)
    }

    public static func renameFolder(layout: Layout, folderID: UUID, name: String) -> Layout {
        guard let located = locateFolder(layout, folderID),
              case .folder(var folder) = layout.pages[located.page][located.index] else { return layout }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.name = trimmed.isEmpty ? defaultFolderName : trimmed
        var pages = layout.pages
        pages[located.page][located.index] = .folder(folder)
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

    private struct Location { var page: Int; var index: Int }

    private static func locateApp(_ layout: Layout, _ bundleID: String) -> Location? {
        for (pageIndex, page) in layout.pages.enumerated() {
            if let index = page.firstIndex(where: { if case .app(let id) = $0 { return id == bundleID }; return false }) {
                return Location(page: pageIndex, index: index)
            }
        }
        return nil
    }

    private static func locateFolder(_ layout: Layout, _ folderID: UUID) -> Location? {
        for (pageIndex, page) in layout.pages.enumerated() {
            if let index = page.firstIndex(where: { if case .folder(let folder) = $0 { return folder.id == folderID }; return false }) {
                return Location(page: pageIndex, index: index)
            }
        }
        return nil
    }
}
