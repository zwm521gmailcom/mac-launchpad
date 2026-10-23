import Foundation
import Testing
@testable import LaunchpadCore

struct AppSearchTests {
    @Test func filtersInLayoutOrderWithoutChangingLayoutOrTruncating() {
        let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let folderMembers = ["com.mail", "com.maps"]
        let layout = Layout(pages: [[
            .app("com.notes"),
            .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: folderMembers)),
            .app("com.music")
        ]])
        let records = [
            record("com.music", "Music"),
            record("com.mail", "Mail"),
            record("com.notes", "Notes"),
            record("com.maps", "Maps")
        ]
        let matches = AppSearch.filter(layout: layout, records: records, query: "ma")
        #expect(matches.map(\.bundleID) == ["com.mail", "com.maps"])
        #expect(layout.pages[0].count == 3)
        let manyIDs = (1...36).map { "com.item.\($0)" }
        let manyLayout = Layout(pages: [manyIDs.map { .app($0) }])
        let manyRecords = manyIDs.map { record($0, "Gamma \($0)") }
        #expect(AppSearch.filter(layout: manyLayout, records: manyRecords, query: "gamma").count == 36)
    }

    @Test func matchTiersRankPrefixAboveWordAboveContainsAboveFuzzy() {
        #expect(AppSearch.matchScore(name: "Calculator", query: "calculator") == 1000)
        #expect(AppSearch.matchScore(name: "Calculator", query: "calc") == 800)
        #expect(AppSearch.matchScore(name: "Visual Studio Code", query: "stu") == 650)
        #expect(AppSearch.matchScore(name: "Calculator", query: "lat") == 500)
        #expect(AppSearch.matchScore(name: "Visual Studio Code", query: "vsc") == 400)
        #expect(AppSearch.matchScore(name: "OBSStudio", query: "studio") == 650)
        #expect((AppSearch.matchScore(name: "Calculator", query: "clcr") ?? 0) > 100)
        #expect(AppSearch.matchScore(name: "Calculator", query: "cl") == nil)
        #expect(AppSearch.matchScore(name: "Calculator", query: "xyz") == nil)
        #expect(AppSearch.matchScore(name: "Café", query: "cafe") == 1000)
    }

    @Test func bundleFileNameAlsoMatches() {
        let wechat = AppRecord(
            bundleID: "com.tencent.xinWeChat",
            displayName: "微信",
            url: URL(fileURLWithPath: "/Applications/WeChat.app")
        )
        let layout = Layout(pages: [[.app(wechat.bundleID)]])
        #expect(AppSearch.filter(layout: layout, records: [wechat], query: "wechat").count == 1)
        #expect(AppSearch.filter(layout: layout, records: [wechat], query: "微").count == 1)
    }

    @Test func betterMatchesComeFirstRegardlessOfLayoutOrder() {
        let layout = Layout(pages: [[.app("com.fuzzy"), .app("com.contains"), .app("com.prefix")]])
        let records = [
            record("com.fuzzy", "Mega Essay Saver"),
            record("com.contains", "Gamessage"),
            record("com.prefix", "Messages")
        ]
        let ids = AppSearch.filter(layout: layout, records: records, query: "messa").map(\.bundleID)
        #expect(ids == ["com.prefix", "com.contains", "com.fuzzy"])
    }

    @Test func frequentlyUsedAppsRiseWithinTheSameTier() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let layout = Layout(pages: [[.app("com.calendar"), .app("com.calculator")]])
        let records = [record("com.calendar", "Calendar"), record("com.calculator", "Calculator")]
        var usage: [String: LaunchUsage] = [:]
        #expect(AppSearch.filter(layout: layout, records: records, query: "cal", usage: usage, now: now)
            .map(\.bundleID) == ["com.calendar", "com.calculator"])
        usage = AppSearch.recordingLaunch(usage, bundleID: "com.calculator", at: now)
        usage = AppSearch.recordingLaunch(usage, bundleID: "com.calculator", at: now)
        #expect(usage["com.calculator"]?.count == 2)
        #expect(AppSearch.filter(layout: layout, records: records, query: "cal", usage: usage, now: now)
            .map(\.bundleID) == ["com.calculator", "com.calendar"])
    }

    @Test func usageBonusIsCappedAndFadesWithTime() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let heavy = LaunchUsage(count: 500, lastUsed: now)
        #expect(AppSearch.usageBonus(heavy, now: now) == 300)
        #expect(AppSearch.usageBonus(nil, now: now) == 0)
        let fresh = LaunchUsage(count: 3, lastUsed: now)
        let old = LaunchUsage(count: 3, lastUsed: now.addingTimeInterval(-60 * 86_400))
        #expect(AppSearch.usageBonus(fresh, now: now) > AppSearch.usageBonus(old, now: now))
        let fuzzyMax = (AppSearch.matchScore(name: "Calculator", query: "clcr") ?? 0) + 300
        #expect(fuzzyMax < AppSearch.matchScore(name: "Calculator", query: "lat")!)
    }

    private func record(_ bundleID: String, _ name: String) -> AppRecord {
        AppRecord(bundleID: bundleID, displayName: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }
}
