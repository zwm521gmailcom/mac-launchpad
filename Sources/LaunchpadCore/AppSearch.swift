import Foundation

public enum AppSearch {
    public static func filter(layout: Layout, records: [AppRecord], query: String) -> [AppRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.bundleID, $0) })
        var matches: [AppRecord] = []
        for page in layout.pages {
            for item in page {
                for bundleID in item.bundleIDs {
                    guard let record = byID[bundleID],
                          record.displayName.range(of: needle, options: [.caseInsensitive]) != nil else { continue }
                    matches.append(record)
                }
            }
        }
        return matches
    }
}
