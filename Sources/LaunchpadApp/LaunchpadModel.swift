import AppKit
import Combine
import LaunchpadCore

final class LaunchpadModel: ObservableObject {
    @Published private(set) var records: [AppRecord] = []
    @Published private(set) var layout = Layout(pages: [])
    @Published var query = ""
    @Published var pageIndex = 0
    @Published var openFolderID: UUID?
    @Published var launchError: String?
    @Published var iconSide: CGFloat
    @Published private(set) var gridMetrics = GridMetrics(icon: 120, columns: 7, rows: 5)
    @Published private(set) var sortByUsage: Bool

    /// 用户自己的排列，也是写进 layout.json 的那份；按常用排序时 `layout` 只是它的显示版本。
    private var memory: Layout?
    private let store: LayoutStore
    private let openURL: (URL) -> Bool
    private var errorGeneration = 0
    private var fittedWidth: CGFloat = 0
    private var fittedHeight: CGFloat = 0
    private var ownUsage: [String: LaunchUsage]
    private var usage: [String: LaunchUsage]
    private static let iconSideKey = "MacLaunchpad.iconSide"
    private static let usageKey = "MacLaunchpad.launchUsage"
    private static let sortByUsageKey = "MacLaunchpad.sortByUsage"

    init(
        store: LayoutStore = LayoutStore(fileURL: LayoutStore.defaultFileURL()),
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.store = store
        self.openURL = openURL
        let stored = UserDefaults.standard.double(forKey: Self.iconSideKey)
        iconSide = stored >= GridMetrics.minimumIcon ? CGFloat(stored) : 120
        let savedUsage = UserDefaults.standard.data(forKey: Self.usageKey)
        ownUsage = savedUsage.flatMap { try? JSONDecoder().decode([String: LaunchUsage].self, from: $0) } ?? [:]
        usage = ownUsage
        sortByUsage = UserDefaults.standard.bool(forKey: Self.sortByUsageKey)
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var searchResults: [AppRecord] {
        AppSearch.filter(layout: layout, records: records, query: query, usage: usage)
    }

    func record(_ bundleID: String) -> AppRecord? {
        records.first { $0.bundleID == bundleID }
    }

    func folder(_ id: UUID) -> FolderItem? {
        for page in layout.pages {
            for item in page {
                if case .folder(let folder) = item, folder.id == id { return folder }
            }
        }
        return nil
    }

    func windowDidShow() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        records = AppCatalog.scan(
            roots: AppCatalog.standardRoots(home: home),
            facts: BundleDisplayNameReader.facts(at:)
        )
        let stored = memory == nil ? store.load() : nil
        memory = SessionPolicy.layoutForShow(memory: memory, stored: stored, records: records)
        usage = UsageSort.merge(ownUsage, SystemUsageReader.usage(for: records))
        redisplay()
    }

    func setSortByUsage(_ on: Bool) {
        guard on != sortByUsage else { return }
        sortByUsage = on
        UserDefaults.standard.set(on, forKey: Self.sortByUsageKey)
        pageIndex = 0
        redisplay()
    }

    private func redisplay() {
        let manual = memory ?? Layout(pages: [])
        layout = sortByUsage ? UsageSort.arrange(manual, usage: usage, capacity: gridMetrics.capacity) : manual
        if layout.pages.isEmpty {
            pageIndex = 0
        } else if pageIndex >= layout.pages.count {
            pageIndex = layout.pages.count - 1
        }
    }

    func showPreviousPage() { shiftPage(-1) }
    func showNextPage() { shiftPage(1) }

    func launch(_ bundleID: String) -> Bool {
        guard let record = record(bundleID) else { return false }
        if openURL(record.url) {
            launchError = nil
            ownUsage = AppSearch.recordingLaunch(ownUsage, bundleID: bundleID, at: Date())
            usage = UsageSort.merge(usage, ownUsage)
            if let data = try? JSONEncoder().encode(ownUsage) {
                UserDefaults.standard.set(data, forKey: Self.usageKey)
            }
            return true
        }
        launchError = SessionPolicy.launchFailureMessage(displayName: record.displayName)
        errorGeneration += 1
        let generation = errorGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.errorGeneration == generation else { return }
            self.launchError = nil
        }
        return false
    }

    func renameFolder(id: UUID, to name: String) {
        commit(LayoutEdit.renameFolder(layout: manual, folderID: id, name: name))
    }

    func makeFolder(dragged: String, onto: String) {
        commit(LayoutEdit.makeFolder(layout: manual, draggedBundleID: dragged, ontoBundleID: onto, folderID: UUID()))
    }

    func addToFolder(bundleID: String, folderID: UUID) {
        commit(LayoutEdit.addToFolder(layout: manual, bundleID: bundleID, folderID: folderID))
    }

    func moveOut(bundleID: String, folderID: UUID) {
        commit(LayoutEdit.moveOutOfFolder(layout: manual, bundleID: bundleID, folderID: folderID, capacity: gridMetrics.capacity))
    }

    /// 页码和位置是按屏幕上看到的算的，按常用排序时和保存的排列对不上，所以不处理。
    func reorder(fromPage: Int, fromIndex: Int, toPage: Int, indexAfterRemoval: Int) {
        guard !sortByUsage else { return }
        commit(LayoutEdit.move(
            layout: manual,
            fromPage: fromPage,
            fromIndex: fromIndex,
            toPage: toPage,
            indexAfterRemoval: indexAfterRemoval,
            capacity: gridMetrics.capacity
        ))
    }

    private var manual: Layout { memory ?? layout }

    func setIconSide(_ side: CGFloat) {
        let next = min(GridMetrics.maximumIcon, max(GridMetrics.minimumIcon, side))
        iconSide = next
        UserDefaults.standard.set(Double(next), forKey: Self.iconSideKey)
        refit(width: fittedWidth, height: fittedHeight, reflow: true)
    }

    func refit(width: CGFloat, height: CGFloat, reflow: Bool) {
        guard width > 1, height > 1 else { return }
        fittedWidth = width
        fittedHeight = height
        let next = GridMetrics.fitting(width: width, height: height, icon: iconSide)
        guard next != gridMetrics else { return }
        let capacityChanged = next.capacity != gridMetrics.capacity
        gridMetrics = next
        guard reflow, capacityChanged, !manual.pages.isEmpty else { return }
        let anchor = anchorToken
        let reflowed = LayoutEdit.reflow(layout: manual, capacity: next.capacity)
        memory = reflowed
        redisplay()
        if let anchor, let page = pageIndex(containing: anchor) {
            pageIndex = page
        }
        try? store.save(reflowed)
    }

    private var anchorToken: String? {
        guard layout.pages.indices.contains(pageIndex), let item = layout.pages[pageIndex].first else { return nil }
        switch item {
        case .app(let bundleID):
            return "a:" + bundleID
        case .folder(let folder):
            return "f:" + folder.id.uuidString
        }
    }

    private func pageIndex(containing token: String) -> Int? {
        layout.pages.firstIndex { page in
            page.contains { item in
                switch item {
                case .app(let bundleID):
                    return token == "a:" + bundleID
                case .folder(let folder):
                    return token == "f:" + folder.id.uuidString
                }
            }
        }
    }

    func reorderFolderMember(folderID: UUID, fromIndex: Int, indexAfterRemoval: Int) {
        commit(LayoutEdit.reorderFolder(layout: manual, folderID: folderID, fromIndex: fromIndex, indexAfterRemoval: indexAfterRemoval))
    }

    func commit(_ newLayout: Layout) {
        memory = newLayout
        redisplay()
        try? store.save(newLayout)
    }

    private func shiftPage(_ delta: Int) {
        guard !layout.pages.isEmpty else { return }
        pageIndex = min(max(0, pageIndex + delta), layout.pages.count - 1)
    }
}
