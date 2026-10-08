import Foundation

public struct FolderItem: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var bundleIDs: [String]

    public init(id: UUID, name: String, bundleIDs: [String]) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
    }
}

public enum PageItem: Equatable, Sendable {
    case app(String)
    case folder(FolderItem)

    public var bundleIDs: [String] {
        switch self {
        case .app(let bundleID):
            return [bundleID]
        case .folder(let folder):
            return folder.bundleIDs
        }
    }
}

public struct Layout: Equatable, Sendable {
    public static let pageCapacity = 35
    public var pages: [[PageItem]]

    public init(pages: [[PageItem]]) {
        self.pages = pages
    }
}
