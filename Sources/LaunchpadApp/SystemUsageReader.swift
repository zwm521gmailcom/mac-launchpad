import CoreServices
import Foundation
import LaunchpadCore

/// 读聚焦（Spotlight）记下的应用使用次数和最近使用时间，从程序坞、访达打开的也算在内。
/// 聚焦索引关掉时读不到，返回的字典里就没有这个应用。
enum SystemUsageReader {
    static func usage(for records: [AppRecord]) -> [String: LaunchUsage] {
        var result: [String: LaunchUsage] = [:]
        for record in records {
            guard let item = MDItemCreateWithURL(nil, record.url as CFURL) else { continue }
            // SDK 里没有导出 kMDItemUseCount 常量，只能写属性名。
            let count = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue ?? 0
            guard count > 0 else { continue }
            let last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date ?? .distantPast
            result[record.bundleID] = LaunchUsage(count: count, lastUsed: last)
        }
        return result
    }
}
