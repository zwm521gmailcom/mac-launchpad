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

public struct BundleFacts: Equatable, Sendable {
    public var bundleID: String?
    public var displayName: String?

    public init(bundleID: String?, displayName: String?) {
        self.bundleID = bundleID
        self.displayName = displayName
    }
}

public enum BundleDisplayNameReader {
    public static func resolve(displayName: String?, bundleName: String?, fileName: String) -> String {
        for raw in [displayName, bundleName, fileName] {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    public static func facts(at url: URL) -> BundleFacts? {
        guard let bundle = Bundle(url: url) else { return nil }
        let displayName = resolve(
            displayName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundleName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            fileName: url.deletingPathExtension().lastPathComponent
        )
        return BundleFacts(bundleID: bundle.bundleIdentifier, displayName: displayName)
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

    public static func scan(
        roots: [CatalogRoot],
        facts: (URL) -> BundleFacts?,
        fileManager: FileManager = .default
    ) -> [AppRecord] {
        scan(
            roots: roots,
            facts: facts,
            fileExists: { path, isDirectory in
                fileManager.fileExists(atPath: path, isDirectory: isDirectory)
            },
            contents: { directory in
                (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            }
        )
    }

    static func scan(
        roots: [CatalogRoot],
        facts: (URL) -> BundleFacts?,
        fileExists: (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
        contents: (URL) -> [URL]
    ) -> [AppRecord] {
        var candidates: [CatalogCandidate] = []
        for root in roots {
            var isDirectory = ObjCBool(false)
            guard fileExists(root.url.path, &isDirectory), isDirectory.boolValue else { continue }
            for url in appURLs(in: root, contents: contents) {
                guard let fact = facts(url), let bundleID = fact.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !bundleID.isEmpty else {
                    continue
                }
                let displayName = resolvedDisplayName(fact.displayName, url: url)
                guard !displayName.isEmpty else { continue }
                candidates.append(CatalogCandidate(
                    record: AppRecord(bundleID: bundleID, displayName: displayName, url: url),
                    priority: root.priority
                ))
            }
        }
        return dedupe(candidates)
    }

    private static func resolvedDisplayName(_ raw: String?, url: URL) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appURLs(in root: CatalogRoot, contents: (URL) -> [URL]) -> [URL] {
        switch root.kind {
        case .topLevel:
            return contents(root.url).filter { $0.pathExtension == "app" }
        case .caskroom:
            return contents(root.url).flatMap { cask in
                contents(cask).flatMap { version in
                    contents(version).filter { $0.pathExtension == "app" }
                }
            }
        }
    }
}
