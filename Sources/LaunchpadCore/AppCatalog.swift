import Foundation

public struct CatalogRoot: Equatable, Sendable {
    public enum Kind: Equatable, Sendable, CustomStringConvertible {
        case topLevel
        case caskroom

        public var description: String {
            switch self {
            case .topLevel: return "topLevel"
            case .caskroom: return "caskroom"
            }
        }
    }

    public var url: URL
    public var kind: Kind
    public var priority: Int

    public init(url: URL, kind: Kind, priority: Int) {
        self.url = url
        self.kind = kind
        self.priority = priority
    }
}

public struct CatalogCandidate: Equatable, Sendable {
    public var record: AppRecord
    public var priority: Int

    public init(record: AppRecord, priority: Int) {
        self.record = record
        self.priority = priority
    }
}

public enum AppCatalog {
    public static func dedupe(_ candidates: [CatalogCandidate]) -> [AppRecord] {
        var best: [String: CatalogCandidate] = [:]
        for candidate in candidates {
            guard let existing = best[candidate.record.bundleID] else {
                best[candidate.record.bundleID] = candidate
                continue
            }
            let betterPriority = candidate.priority < existing.priority
            let samePrioritySmallerPath = candidate.priority == existing.priority
                && candidate.record.url.path < existing.record.url.path
            if betterPriority || samePrioritySmallerPath {
                best[candidate.record.bundleID] = candidate
            }
        }
        return best.values.map(\.record).sorted { $0.bundleID < $1.bundleID }
    }

    public static func standardRoots(home: URL) -> [CatalogRoot] {
        [
            CatalogRoot(url: home.appendingPathComponent("Applications"), kind: .topLevel, priority: 1),
            CatalogRoot(url: URL(fileURLWithPath: "/Applications"), kind: .topLevel, priority: 2),
            CatalogRoot(url: URL(fileURLWithPath: "/opt/homebrew/Caskroom"), kind: .caskroom, priority: 3),
            CatalogRoot(url: URL(fileURLWithPath: "/usr/local/Caskroom"), kind: .caskroom, priority: 4),
            CatalogRoot(url: URL(fileURLWithPath: "/System/Applications"), kind: .topLevel, priority: 5),
            CatalogRoot(url: URL(fileURLWithPath: "/System/Applications/Utilities"), kind: .topLevel, priority: 5),
            CatalogRoot(url: URL(fileURLWithPath: "/Applications/Utilities"), kind: .topLevel, priority: 6)
        ]
    }
}
