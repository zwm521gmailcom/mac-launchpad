import Foundation

/// 某个应用从启动台打开过几次、最近一次是什么时候。
public struct LaunchUsage: Codable, Equatable, Sendable {
    public var count: Int
    public var lastUsed: Date

    public init(count: Int, lastUsed: Date) {
        self.count = count
        self.lastUsed = lastUsed
    }
}

public enum AppSearch {
    /// 按匹配程度排序；匹配程度接近时，常用、最近用过的排前面；再相同就按排列顺序。
    public static func filter(
        layout: Layout,
        records: [AppRecord],
        query: String,
        usage: [String: LaunchUsage] = [:],
        now: Date = Date()
    ) -> [AppRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.bundleID, $0) })
        var scored: [(record: AppRecord, score: Int, order: Int)] = []
        for page in layout.pages {
            for item in page {
                for bundleID in item.bundleIDs {
                    guard let record = byID[bundleID], let match = bestMatch(record, query: needle) else { continue }
                    let score = match + usageBonus(usage[bundleID], now: now)
                    scored.append((record, score, scored.count))
                }
            }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .map(\.record)
    }

    /// 显示名和 .app 文件名都参与匹配，例如显示为「微信」的应用也能用 wechat 找到。
    static func bestMatch(_ record: AppRecord, query: String) -> Int? {
        let fileName = record.url.deletingPathExtension().lastPathComponent
        let names = fileName == record.displayName ? [record.displayName] : [record.displayName, fileName]
        return names.compactMap { matchScore(name: $0, query: query) }.max()
    }

    /// 完全相同 > 开头相同 > 某个词开头相同 > 中间包含 > 各词首字母 > 字母按顺序出现。
    public static func matchScore(name: String, query: String) -> Int? {
        let hay = fold(name)
        let needle = fold(query)
        guard !hay.isEmpty, !needle.isEmpty else { return nil }
        if hay == needle { return 1000 }
        if hay.hasPrefix(needle) { return 800 }
        let words = words(in: name).map(fold)
        if words.contains(where: { $0.hasPrefix(needle) }) { return 650 }
        if hay.contains(needle) { return 500 }
        let compact = needle.filter { !$0.isWhitespace }
        if compact.count >= 2, words.count >= 2 {
            let initials = String(words.compactMap(\.first))
            if initials.hasPrefix(compact) { return 400 }
        }
        // 只打两个字母时按顺序匹配会命中太多应用，至少三个字母才启用。
        if compact.count >= 3, let spread = subsequenceSpread(compact, in: hay) {
            return 100 + max(0, 50 - spread)
        }
        return nil
    }

    /// 最多加 300 分：能在开头相同、包含这类相近档位里调整先后，但不会把乱序匹配顶到包含匹配前面。
    public static func usageBonus(_ usage: LaunchUsage?, now: Date) -> Int {
        guard let usage, usage.count > 0 else { return 0 }
        let days = max(0, now.timeIntervalSince(usage.lastUsed) / 86_400)
        let recency: Double = days < 1 ? 1 : days < 7 ? 0.7 : days < 30 ? 0.4 : 0.2
        return min(300, Int((Double(usage.count) * recency * 30).rounded()))
    }

    public static func recordingLaunch(
        _ usage: [String: LaunchUsage],
        bundleID: String,
        at date: Date
    ) -> [String: LaunchUsage] {
        var next = usage
        let count = min(1000, (usage[bundleID]?.count ?? 0) + 1)
        next[bundleID] = LaunchUsage(count: count, lastUsed: date)
        return next
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// 按空格、符号、小写转大写、字母和数字交界切词，例如 "Visual Studio Code"、"OBSStudio"、"iTerm2"。
    static func words(in name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        let chars = Array(name)
        for (index, char) in chars.enumerated() {
            guard char.isLetter || char.isNumber else {
                if !current.isEmpty { words.append(current) }
                current = ""
                previous = nil
                continue
            }
            if let prev = previous {
                let camel = prev.isLowercase && char.isUppercase
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                let acronymEnd = prev.isUppercase && char.isUppercase && next?.isLowercase == true
                let digitEdge = prev.isNumber != char.isNumber
                if camel || acronymEnd || digitEdge {
                    words.append(current)
                    current = ""
                }
            }
            current.append(char)
            previous = char
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// 查询里的字按顺序都能在名字里找到时，返回中间夹了多少个别的字。
    private static func subsequenceSpread(_ needle: String, in hay: String) -> Int? {
        let target = Array(needle)
        var matched = 0
        var first: Int?
        var last = 0
        for (index, char) in hay.enumerated() where matched < target.count && char == target[matched] {
            if first == nil { first = index }
            last = index
            matched += 1
        }
        guard matched == target.count, let first else { return nil }
        return (last - first + 1) - target.count
    }
}
