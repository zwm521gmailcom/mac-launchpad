import Foundation

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
}
