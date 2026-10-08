import Foundation

public struct AppRecord: Equatable, Identifiable, Sendable {
    public var bundleID: String
    public var displayName: String
    public var url: URL

    public var id: String { bundleID }

    public init(bundleID: String, displayName: String, url: URL) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.url = url
    }
}
