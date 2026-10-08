import Foundation

public struct LayoutStore {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent("Library/Application Support/MacLaunchpad", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    public func load() -> Layout? {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredLayout.self, from: data),
              let layout = stored.layout,
              !Self.containsDuplicateBundleID(layout) else {
            return nil
        }
        return layout
    }

    public func save(_ layout: Layout) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(StoredLayout(layout))
        try data.write(to: fileURL, options: .atomic)
    }

    static func containsDuplicateBundleID(_ layout: Layout) -> Bool {
        var seen = Set<String>()
        for page in layout.pages {
            for bundleID in page.flatMap(\.bundleIDs) where !seen.insert(bundleID).inserted {
                return true
            }
        }
        return false
    }
}

private struct StoredLayout: Codable {
    var pages: [StoredPage]

    init(_ layout: Layout) {
        pages = layout.pages.map { page in
            StoredPage(items: page.map(StoredItem.init))
        }
    }

    var layout: Layout? {
        var decoded: [[PageItem]] = []
        for page in pages {
            var items: [PageItem] = []
            for stored in page.items {
                guard let item = stored.pageItem else { return nil }
                items.append(item)
            }
            decoded.append(items)
        }
        return Layout(pages: decoded)
    }
}

private struct StoredPage: Codable {
    var items: [StoredItem]
}

private struct StoredItem: Codable {
    var type: String
    var bundleID: String?
    var id: UUID?
    var name: String?
    var items: [String]?

    init(_ item: PageItem) {
        switch item {
        case .app(let bundleID):
            type = "app"
            self.bundleID = bundleID
        case .folder(let folder):
            type = "folder"
            id = folder.id
            name = folder.name
            items = folder.bundleIDs
        }
    }

    var pageItem: PageItem? {
        switch type {
        case "app":
            guard let bundleID, !bundleID.isEmpty else { return nil }
            return .app(bundleID)
        case "folder":
            guard let id, let name, let items else { return nil }
            return .folder(FolderItem(id: id, name: name, bundleIDs: items))
        default:
            return nil
        }
    }
}
