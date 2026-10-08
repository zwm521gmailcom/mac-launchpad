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

    private var memory: Layout?
    private let store: LayoutStore
    private let openURL: (URL) -> Bool
    private var errorGeneration = 0

    init(
        store: LayoutStore = LayoutStore(fileURL: LayoutStore.defaultFileURL()),
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.store = store
        self.openURL = openURL
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var searchResults: [AppRecord] {
        AppSearch.filter(layout: layout, records: records, query: query)
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
        layout = SessionPolicy.layoutForShow(memory: memory, stored: stored, records: records)
        memory = layout
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
        commit(LayoutEdit.renameFolder(layout: layout, folderID: id, name: name))
    }

    func commit(_ newLayout: Layout) {
        layout = newLayout
        memory = newLayout
        if pageIndex >= layout.pages.count {
            pageIndex = max(0, layout.pages.count - 1)
        }
        try? store.save(newLayout)
    }

    private func shiftPage(_ delta: Int) {
        guard !layout.pages.isEmpty else { return }
        pageIndex = min(max(0, pageIndex + delta), layout.pages.count - 1)
    }
}
