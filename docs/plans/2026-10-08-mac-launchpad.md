# MacLaunchpad Implementation Plan

> **For agentic workers:** REQUIRED: Use `subagent-driven-development` (if subagents available) or `executing-plans` to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做一个停在程序坞里的 macOS 全屏启动台，扫描本机 App，点图标打开，并记住分页、文件夹和排序。

**Architecture:** 纯逻辑放在 `LaunchpadCore`，用 XCTest 覆盖扫描、布局和搜索。SwiftUI 可执行文件只负责窗口、手势和调用 `NSWorkspace`。布局进程内以内存为准，`layout.json` 只是成功写入后的副本。

**Tech Stack:** Swift 5.9、Swift Package Manager、SwiftUI、AppKit、XCTest。最低系统 macOS 14。

## Global Constraints

- 显示名是「程序启动台」。布局目录是 `~/Library/Application Support/MacLaunchpad/layout.json`。
- 每页最多 35 个，7 列 × 5 行，页内不留空格。
- 扫描根和优先级按规格：用户应用目录优先于 `/Applications`，再是两个 Caskroom，然后系统应用，最后是 `/Applications/Utilities`。
- 同一 bundle id 在布局文件里出现超过一次，整份布局作废。
- 第一版没有全局快捷键、菜单栏图标、扫描缓存、文件夹嵌套和界面自动化测试。
- 规格：`docs/specs/2026-10-08-mac-launchpad-design.md`

## File Structure

- `Package.swift` — 包定义。库 `LaunchpadCore`，可执行文件 `MacLaunchpad`，测试 `LaunchpadCoreTests`。
- `Sources/LaunchpadCore/AppRecord.swift` — 一个已安装 App 的 bundle id、显示名、路径。
- `Sources/LaunchpadCore/AppCatalog.swift` — 枚举目录、去重、决定标准扫描根。
- `Sources/LaunchpadCore/Layout.swift` — 页、格子、文件夹的数据模型。
- `Sources/LaunchpadCore/LayoutEdit.swift` — 合并扫描结果、换位、文件夹、溢出和删空页。
- `Sources/LaunchpadCore/AppSearch.swift` — 按布局顺序做显示名子串过滤。
- `Sources/LaunchpadCore/LayoutStore.swift` — 读写并校验 `layout.json`。
- `Sources/LaunchpadApp/MacLaunchpadApp.swift` — 进程入口、窗口显示和隐藏。
- `Sources/LaunchpadApp/ScreenWindow.swift` — 铺满当前屏幕的无边框窗口。
- `Sources/LaunchpadApp/LaunchpadModel.swift` — 把扫描、内存布局和保存串起来。
- `Sources/LaunchpadApp/AppOpener.swift` — 按路径打开 App。
- `Sources/LaunchpadApp/LaunchpadRootView.swift` — 搜索、分页、圆点和打开失败提示。
- `Sources/LaunchpadApp/PageGridView.swift` — 7 列网格。
- `Sources/LaunchpadApp/FolderOverlay.swift` — 文件夹内页和改名。
- `Sources/LaunchpadApp/DesktopBackground.swift` — 壁纸模糊，失败时深色底。
- `Scripts/package-app.sh` — 把二进制包成 `.app`，使它出现在程序坞。
- `Tests/LaunchpadCoreTests/` — 与上面核心文件对应的单元测试。

---

## Chunk 1: 扫描和去重

这一段只产生 `LaunchpadCore` 里的目录扫描。跑完 `swift test` 后，还没有窗口。

### Task 1: 包和 App 记录

**Files:**
- Create: `Package.swift`
- Create: `Sources/LaunchpadCore/AppRecord.swift`
- Test: `Tests/LaunchpadCoreTests/AppRecordTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class AppRecordTests: XCTestCase {
    func testIdentityIsBundleID() {
        let record = AppRecord(
            bundleID: "com.example.Safari",
            displayName: "Safari",
            url: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        XCTAssertEqual(record.id, "com.example.Safari")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppRecordTests`
Expected: FAIL，找不到 `LaunchpadCore` 或 `AppRecord`。

- [ ] **Step 3: Write minimal implementation**

`Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacLaunchpad",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LaunchpadCore", targets: ["LaunchpadCore"])
    ],
    targets: [
        .target(name: "LaunchpadCore"),
        .testTarget(name: "LaunchpadCoreTests", dependencies: ["LaunchpadCore"])
    ]
)
```

`Sources/LaunchpadCore/AppRecord.swift`

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppRecordTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/LaunchpadCore/AppRecord.swift Tests/LaunchpadCoreTests/AppRecordTests.swift
git commit -m "Add AppRecord as the scanned app identity."
```

### Task 2: 按优先级去重

**Files:**
- Create: `Sources/LaunchpadCore/AppCatalog.swift`
- Test: `Tests/LaunchpadCoreTests/AppCatalogDedupeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class AppCatalogDedupeTests: XCTestCase {
    func testPrefersLowerPriorityNumber() {
        let kept = AppCatalog.dedupe([
            candidate("com.app", "/System/Applications/App.app", priority: 5),
            candidate("com.app", "/Users/me/Applications/App.app", priority: 1),
            candidate("com.app", "/Applications/App.app", priority: 2),
            candidate("com.app", "/opt/homebrew/Caskroom/app/1/App.app", priority: 3)
        ])
        XCTAssertEqual(kept.map(\.url.path), ["/Users/me/Applications/App.app"])
    }

    func testCaskroomBeatsSystem() {
        let kept = AppCatalog.dedupe([
            candidate("com.app", "/System/Applications/App.app", priority: 5),
            candidate("com.app", "/opt/homebrew/Caskroom/app/1/App.app", priority: 3)
        ])
        XCTAssertEqual(kept.map(\.url.path), ["/opt/homebrew/Caskroom/app/1/App.app"])
    }

    func testSamePriorityKeepsLexicographicallySmallerPath() {
        let kept = AppCatalog.dedupe([
            candidate("com.app", "/opt/homebrew/Caskroom/app/2.0/App.app", priority: 3),
            candidate("com.app", "/opt/homebrew/Caskroom/app/1.0/App.app", priority: 3)
        ])
        XCTAssertEqual(kept.map(\.url.path), ["/opt/homebrew/Caskroom/app/1.0/App.app"])
    }

    private func candidate(_ bundleID: String, _ path: String, priority: Int) -> CatalogCandidate {
        CatalogCandidate(
            record: AppRecord(bundleID: bundleID, displayName: "App", url: URL(fileURLWithPath: path)),
            priority: priority
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppCatalogDedupeTests`
Expected: FAIL，找不到 `AppCatalog`。

- [ ] **Step 3: Write minimal implementation**

在 `Sources/LaunchpadCore/AppCatalog.swift` 写入：

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppCatalogDedupeTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/AppCatalog.swift Tests/LaunchpadCoreTests/AppCatalogDedupeTests.swift
git commit -m "Dedupe scanned apps by bundle id and source priority."
```

### Task 3: 标准扫描根

**Files:**
- Modify: `Sources/LaunchpadCore/AppCatalog.swift`
- Test: `Tests/LaunchpadCoreTests/CatalogRootTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class CatalogRootTests: XCTestCase {
    func testStandardRootsMatchSpecPriority() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let roots = AppCatalog.standardRoots(home: home)
        let described = roots.map { "\($0.priority) \($0.kind) \($0.url.path)" }
        XCTAssertEqual(described, [
            "1 topLevel /Users/me/Applications",
            "2 topLevel /Applications",
            "3 caskroom /opt/homebrew/Caskroom",
            "4 caskroom /usr/local/Caskroom",
            "5 topLevel /System/Applications",
            "5 topLevel /System/Applications/Utilities",
            "6 topLevel /Applications/Utilities"
        ])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CatalogRootTests`
Expected: FAIL，找不到 `standardRoots`。

- [ ] **Step 3: Write minimal implementation**

把下面的类型和函数加进 `AppCatalog.swift`。`Kind` 的 `CustomStringConvertible` 必须输出 `topLevel` 和 `caskroom`，测试比较的是这个文字。

```swift
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

extension AppCatalog {
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CatalogRootTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/AppCatalog.swift Tests/LaunchpadCoreTests/CatalogRootTests.swift
git commit -m "List the spec scan roots in priority order."
```

### Task 4: 枚举 .app 并跳过坏包

**Files:**
- Modify: `Sources/LaunchpadCore/AppCatalog.swift`
- Test: `Tests/LaunchpadCoreTests/AppCatalogScanTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class AppCatalogScanTests: XCTestCase {
    func testSkipsMissingRootsUnreadableBundlesAndNestedApps() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let applications = root.appendingPathComponent("Applications")
        let nested = applications.appendingPathComponent("Host.app/Contents/PlugIns/Helper.app")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications.appendingPathComponent("Good.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications.appendingPathComponent("NoID.app"), withIntermediateDirectories: true)

        let records = AppCatalog.scan(
            roots: [CatalogRoot(url: applications, kind: .topLevel, priority: 2),
                    CatalogRoot(url: root.appendingPathComponent("Missing"), kind: .topLevel, priority: 1)],
            facts: { url in
                if url.lastPathComponent == "Good.app" {
                    return BundleFacts(bundleID: "com.good", displayName: "Good")
                }
                if url.lastPathComponent == "Helper.app" {
                    return BundleFacts(bundleID: "com.helper", displayName: "Helper")
                }
                return BundleFacts(bundleID: nil, displayName: nil)
            }
        )

        XCTAssertEqual(records.map(\.bundleID), ["com.good"])
        try? FileManager.default.removeItem(at: root)
    }

    func testCaskroomReadsOnlyNameVersionApp() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Caskroom/firefox/120/Firefox.app")
        let tooDeep = root.appendingPathComponent("Caskroom/firefox/120/Extra/Hidden.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tooDeep, withIntermediateDirectories: true)

        let records = AppCatalog.scan(
            roots: [CatalogRoot(url: root.appendingPathComponent("Caskroom"), kind: .caskroom, priority: 3)],
            facts: { url in
                BundleFacts(bundleID: "id.\(url.deletingPathExtension().lastPathComponent)", displayName: "Name")
            }
        )
        XCTAssertEqual(records.map(\.bundleID), ["id.Firefox"])
        try? FileManager.default.removeItem(at: root)
    }

    func testEmptyDisplayNameFallsBackToFileName() {
        let url = URL(fileURLWithPath: "/Applications/Notes.app")
        let records = AppCatalog.scan(
            roots: [CatalogRoot(url: url.deletingLastPathComponent(), kind: .topLevel, priority: 2)],
            facts: { _ in BundleFacts(bundleID: "com.notes", displayName: "  ") },
            fileExists: { path, isDirectory in
                isDirectory?.pointee = ObjCBool(path != url.path)
                return true
            },
            contents: { directory in
                directory.lastPathComponent == "Applications" ? [url] : []
            }
        )
        XCTAssertEqual(records.map(\.displayName), ["Notes"])
    }

    func testScanKeepsHigherPriorityRoot() {
        let user = URL(fileURLWithPath: "/Users/me/Applications/App.app")
        let system = URL(fileURLWithPath: "/System/Applications/App.app")
        let records = AppCatalog.scan(
            roots: [
                CatalogRoot(url: user.deletingLastPathComponent(), kind: .topLevel, priority: 1),
                CatalogRoot(url: system.deletingLastPathComponent(), kind: .topLevel, priority: 5)
            ],
            facts: { _ in BundleFacts(bundleID: "com.app", displayName: "App") },
            fileExists: { _, isDirectory in
                isDirectory?.pointee = true
                return true
            },
            contents: { directory in
                if directory.path == "/Users/me/Applications" { return [user] }
                if directory.path == "/System/Applications" { return [system] }
                return []
            }
        )
        XCTAssertEqual(records.map(\.url.path), [user.path])
    }

    func testBlankBundleIDIsSkipped() {
        let url = URL(fileURLWithPath: "/Applications/Blank.app")
        let records = AppCatalog.scan(
            roots: [CatalogRoot(url: url.deletingLastPathComponent(), kind: .topLevel, priority: 2)],
            facts: { _ in BundleFacts(bundleID: "   ", displayName: "Blank") },
            fileExists: { _, isDirectory in
                isDirectory?.pointee = true
                return true
            },
            contents: { $0.lastPathComponent == "Applications" ? [url] : [] }
        )
        XCTAssertTrue(records.isEmpty)
    }
}

final class BundleDisplayNameReaderTests: XCTestCase {
    func testSkipsBlankDisplayNameThenBundleNameThenFileName() {
        XCTAssertEqual(
            BundleDisplayNameReader.resolve(displayName: "  ", bundleName: "From Bundle", fileName: "File"),
            "From Bundle"
        )
        XCTAssertEqual(
            BundleDisplayNameReader.resolve(displayName: nil, bundleName: " ", fileName: "File"),
            "File"
        )
        XCTAssertEqual(
            BundleDisplayNameReader.resolve(displayName: nil, bundleName: nil, fileName: " "),
            ""
        )
    }

    func testRealBundleUsesInfoPlistKeysInOrder() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Demo.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: String] = [
            "CFBundleIdentifier": "com.demo",
            "CFBundleDisplayName": "   ",
            "CFBundleName": "Plist Name"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let facts = BundleDisplayNameReader.facts(at: app)
        XCTAssertEqual(facts?.bundleID, "com.demo")
        XCTAssertEqual(facts?.displayName, "Plist Name")
        try? FileManager.default.removeItem(at: root)
    }
}
```

`testEmptyDisplayNameFallsBackToFileName` 不碰真实的 `/Applications`。扫描函数要接受可替换的 `fileExists` 和 `contents`，默认转发到 `FileManager`。

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppCatalogScanTests`
Expected: FAIL，找不到 `scan`。

- [ ] **Step 3: Write minimal implementation**

在 `AppCatalog.swift` 增加：

```swift
public struct BundleFacts: Equatable, Sendable {
    public var bundleID: String?
    public var displayName: String?

    public init(bundleID: String?, displayName: String?) {
        self.bundleID = bundleID
        self.displayName = displayName
    }
}

extension AppCatalog {
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
```

显示名读取器跟扫描放在同一个文件。`Bundle.object(forInfoDictionaryKey:)` 会按当前首选语言读取本地化字符串。空白字符串不能占住下一个键。两个键都没有可用文字时，把文件名交给扫描函数的既有回退；两个键和文件名都是空白时，解析结果是空字符串，扫描会跳过。

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppCatalogScanTests`
Expected: PASS

Run: `swift test --filter BundleDisplayNameReaderTests`
Expected: PASS

然后再跑 `swift test`。通过的测试类是 `AppRecordTests`、`AppCatalogDedupeTests`、`CatalogRootTests`、`AppCatalogScanTests`、`BundleDisplayNameReaderTests`。

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/AppCatalog.swift Tests/LaunchpadCoreTests/AppCatalogScanTests.swift
git commit -m "Scan application roots without entering nested bundles."
```

---

## Chunk 2: 布局、文件夹和搜索

这一段仍只改 `LaunchpadCore`。界面落在图标中心还是格子前后半段，由后面的 SwiftUI 决定。这里的函数接收已经判断好的操作。

比较显示名用 `localizedCaseInsensitiveCompare`。显示名相同再比 bundle id。新建布局和后来追加的新 App 用同一种比较。

### Task 5: 页和文件夹模型

**Files:**
- Create: `Sources/LaunchpadCore/Layout.swift`
- Test: `Tests/LaunchpadCoreTests/LayoutModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class LayoutModelTests: XCTestCase {
    func testPageItemExposesMemberIDsInOrder() {
        let folder = FolderItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "文件夹",
            bundleIDs: ["com.b", "com.a"]
        )
        XCTAssertEqual(PageItem.app("com.a").bundleIDs, ["com.a"])
        XCTAssertEqual(PageItem.folder(folder).bundleIDs, ["com.b", "com.a"])
        XCTAssertEqual(Layout.pageCapacity, 35)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LayoutModelTests`
Expected: FAIL，找不到 `FolderItem`。

- [ ] **Step 3: Write minimal implementation**

`Sources/LaunchpadCore/Layout.swift`

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LayoutModelTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/Layout.swift Tests/LaunchpadCoreTests/LayoutModelTests.swift
git commit -m "Add ordered page and folder layout values."
```

### Task 6: 新建布局和扫描合并

**Files:**
- Create: `Sources/LaunchpadCore/LayoutEdit.swift`
- Test: `Tests/LaunchpadCoreTests/LayoutReconcileTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class LayoutReconcileTests: XCTestCase {
    func testFreshSortsByLocalizedNameThenBundleIDAndPagesBy35() {
        let records = [
            record("com.b", "beta"),
            record("com.a2", "Alpha"),
            record("com.a1", "alpha")
        ] + (1...35).map { record("com.n\($0)", "n\($0)") }
        let layout = LayoutEdit.fresh(records: records)
        XCTAssertEqual(layout.pages[0].count, 35)
        XCTAssertEqual(layout.pages[1].count, 3)
        XCTAssertEqual(layout.pages[0].first, .app("com.a1"))
        XCTAssertEqual(layout.pages[0][1], .app("com.a2"))
    }

    func testReconcileDropsMissingAppsAndEmptyFoldersThenFillsFirstGap() {
        let folder = FolderItem(id: fixedID, name: "文件夹", bundleIDs: ["gone.folder", "kept.folder"])
        let full = (0..<34).map { PageItem.app("keep.\($0)") } + [.folder(folder)]
        let layout = Layout(pages: [full, [.app("gone.page")], [.app("tail")]])
        let records = (0..<34).map { record("keep.\($0)", "K\($0)") }
            + [record("kept.folder", "Folder App"), record("tail", "Tail"), record("new.app", "New")]
        let next = LayoutEdit.reconcile(layout: layout, records: records)
        XCTAssertEqual(next.pages.count, 2)
        XCTAssertEqual(next.pages[0].count, 35)
        XCTAssertEqual(next.pages[0].last, .folder(FolderItem(id: fixedID, name: "文件夹", bundleIDs: ["kept.folder"])))
        XCTAssertFalse(next.pages[1].contains(.app("gone.page")))
        XCTAssertEqual(next.pages[1].last, .app("new.app"))
    }

    func testNewAppStartsAPageWhenExistingPagesAreFull() {
        let existing = (0..<35).map { record("a.\($0)", "A\($0)") }
        let layout = Layout(pages: [existing.map { .app($0.bundleID) }])
        let next = LayoutEdit.reconcile(layout: layout, records: existing + [record("new.app", "New")])
        XCTAssertEqual(next.pages.count, 2)
        XCTAssertEqual(next.pages[1], [.app("new.app")])
    }

    private let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func record(_ bundleID: String, _ name: String) -> AppRecord {
        AppRecord(bundleID: bundleID, displayName: name, url: URL(fileURLWithPath: "/Applications/\(bundleID).app"))
    }
}
```

`testFreshSorts` 的前三项按显示名应是 `alpha`、`Alpha`、`beta`。大小写不敏感时 `alpha` 与 `Alpha` 相同，bundle id `com.a1` 在 `com.a2` 前。`n1` 这类名字的本地化排序不要写死整页，只断言页大小和前两个 bundle id。35 个 `n*` 加上 3 个字母项一共 38 个，所以第二页是 3 个。第一页的第一个必须是 `com.a1`。如果本地化排序把 `alpha` 排到 `n*` 后面，这个断言会失败；实现必须先按显示名排序再分页，测试数据里的 `alpha` 用拉丁字母，会排在 `n` 前面。

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LayoutReconcileTests`
Expected: FAIL，找不到 `LayoutEdit`。

- [ ] **Step 3: Write minimal implementation**

`Sources/LaunchpadCore/LayoutEdit.swift`

```swift
import Foundation

public enum LayoutEdit {
    public static let defaultFolderName = "文件夹"

    public static func fresh(records: [AppRecord]) -> Layout {
        let items = records.sorted(by: displayNameOrder).map { PageItem.app($0.bundleID) }
        let pages = stride(from: 0, to: items.count, by: Layout.pageCapacity).map { start in
            Array(items[start..<min(start + Layout.pageCapacity, items.count)])
        }
        return Layout(pages: pages)
    }

    public static func reconcile(layout: Layout, records: [AppRecord]) -> Layout {
        let known = Set(records.map(\.bundleID))
        var placed = Set<String>()
        var pages: [[PageItem]] = []
        for page in layout.pages {
            var next: [PageItem] = []
            for item in page {
                switch item {
                case .app(let bundleID):
                    if known.contains(bundleID), placed.insert(bundleID).inserted {
                        next.append(.app(bundleID))
                    }
                case .folder(var folder):
                    folder.bundleIDs = folder.bundleIDs.filter { known.contains($0) && placed.insert($0).inserted }
                    if !folder.bundleIDs.isEmpty {
                        next.append(.folder(folder))
                    }
                }
            }
            if !next.isEmpty {
                pages.append(next)
            }
        }
        let newcomers = records.filter { !placed.contains($0.bundleID) }.sorted(by: displayNameOrder)
        for record in newcomers {
            if let index = pages.firstIndex(where: { $0.count < Layout.pageCapacity }) {
                pages[index].append(.app(record.bundleID))
            } else {
                pages.append([.app(record.bundleID)])
            }
        }
        return Layout(pages: pages)
    }

    static func displayNameOrder(_ lhs: AppRecord, _ rhs: AppRecord) -> Bool {
        let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if order == .orderedSame {
            return lhs.bundleID < rhs.bundleID
        }
        return order == .orderedAscending
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LayoutReconcileTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/LayoutEdit.swift Tests/LaunchpadCoreTests/LayoutReconcileTests.swift
git commit -m "Reconcile saved pages with the latest app scan."
```

### Task 7: 换位、溢出和空页

**Files:**
- Modify: `Sources/LaunchpadCore/LayoutEdit.swift`
- Test: `Tests/LaunchpadCoreTests/LayoutMoveTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class LayoutMoveTests: XCTestCase {
    func testSamePageUsesIndexAfterRemoval() {
        let layout = Layout(pages: [[.app("a"), .app("b"), .app("c")]])
        let next = LayoutEdit.move(layout: layout, fromPage: 0, fromIndex: 0, toPage: 0, indexAfterRemoval: 1)
        XCTAssertEqual(next.pages, [[.app("b"), .app("a"), .app("c")]])
    }

    func testCrossPageCompactsSource() {
        let layout = Layout(pages: [[.app("a"), .app("b")], [.app("c")]])
        let next = LayoutEdit.move(layout: layout, fromPage: 0, fromIndex: 0, toPage: 1, indexAfterRemoval: 0)
        XCTAssertEqual(next.pages, [[.app("b")], [.app("a"), .app("c")]])
    }

    func testFullPagePushesLastItemToNextPageStart() {
        let first = (0..<35).map { PageItem.app("a.\($0)") }
        let layout = Layout(pages: [first, [.app("b")]])
        let next = LayoutEdit.move(layout: layout, fromPage: 1, fromIndex: 0, toPage: 0, indexAfterRemoval: 0)
        XCTAssertEqual(next.pages[0].count, 35)
        XCTAssertEqual(next.pages[0][0], .app("b"))
        XCTAssertEqual(next.pages[1], [.app("a.34")])
    }

    func testMovingOntoANewPageDropsTheEmptiedSource() {
        let layout = Layout(pages: [[.app("stay"), .app("move")]])
        let next = LayoutEdit.move(layout: layout, fromPage: 0, fromIndex: 1, toPage: 1, indexAfterRemoval: 0)
        XCTAssertEqual(next.pages, [[.app("stay")], [.app("move")]])
    }
}
```

`toPage: 1` 在只有一页时表示拖拽中新建的那一页。函数要先允许这个新下标，放下后再删掉仍然为空的页。

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LayoutMoveTests`
Expected: FAIL，找不到 `move`。

- [ ] **Step 3: Write minimal implementation**

把下面的方法加进 `LayoutEdit`：

```swift
public static func move(
    layout: Layout,
    fromPage: Int,
    fromIndex: Int,
    toPage: Int,
    indexAfterRemoval: Int
) -> Layout {
    var pages = layout.pages
    guard pages.indices.contains(fromPage), pages[fromPage].indices.contains(fromIndex) else {
        return layout
    }
    let item = pages[fromPage].remove(at: fromIndex)
    if toPage == pages.count {
        pages.append([])
    }
    guard pages.indices.contains(toPage) else { return layout }
    let bounded = min(max(indexAfterRemoval, 0), pages[toPage].count)
    pages[toPage].insert(item, at: bounded)
    pages = spill(pages)
    pages.removeAll { $0.isEmpty }
    return Layout(pages: pages)
}

private static func spill(_ pages: [[PageItem]]) -> [[PageItem]] {
    var pages = pages
    var index = 0
    while index < pages.count {
        while pages[index].count > Layout.pageCapacity {
            let extra = pages[index].removeLast()
            if index + 1 == pages.count {
                pages.append([])
            }
            pages[index + 1].insert(extra, at: 0)
        }
        index += 1
    }
    return pages
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LayoutMoveTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/LayoutEdit.swift Tests/LaunchpadCoreTests/LayoutMoveTests.swift
git commit -m "Move layout items using indexes after removal."
```

### Task 8: 文件夹操作

**Files:**
- Modify: `Sources/LaunchpadCore/LayoutEdit.swift`
- Test: `Tests/LaunchpadCoreTests/FolderEditTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class FolderEditTests: XCTestCase {
    private let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    func testDropOnAppCreatesFolderAtTarget() {
        let layout = Layout(pages: [[.app("a"), .app("b"), .app("c")]])
        let next = LayoutEdit.makeFolder(layout: layout, draggedBundleID: "a", ontoBundleID: "b", folderID: folderID)
        XCTAssertEqual(next.pages[0], [
            .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["b", "a"])),
            .app("c")
        ])
    }

    func testDropOnFolderAppendsAndRemovingLastMemberDeletesFolder() {
        let layout = Layout(pages: [[.app("a"), .folder(FolderItem(id: folderID, name: "工作", bundleIDs: ["b"]))]])
        let added = LayoutEdit.addToFolder(layout: layout, bundleID: "a", folderID: folderID)
        XCTAssertEqual(added.pages[0], [
            .folder(FolderItem(id: folderID, name: "工作", bundleIDs: ["b", "a"]))
        ])
        let removed = LayoutEdit.moveOutOfFolder(layout: added, bundleID: "b", folderID: folderID)
        XCTAssertEqual(removed.pages, [[
            .folder(FolderItem(id: folderID, name: "工作", bundleIDs: ["a"])),
            .app("b")
        ]])
        let emptied = LayoutEdit.moveOutOfFolder(layout: removed, bundleID: "a", folderID: folderID)
        XCTAssertEqual(emptied.pages, [[.app("b"), .app("a")]])
    }

    func testMoveOutOfFullPageSpillsBeforeDeletingEmptyFolder() {
        var page = (0..<34).map { PageItem.app("a.\($0)") }
        page.append(.folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["inside"])))
        let next = LayoutEdit.moveOutOfFolder(layout: Layout(pages: [page]), bundleID: "inside", folderID: folderID)
        XCTAssertEqual(next.pages[0].count, 34)
        XCTAssertEqual(next.pages[1], [.app("inside")])
    }

    func testBlankRenameRestoresDefaultName() {
        let layout = Layout(pages: [[.folder(FolderItem(id: folderID, name: "工作", bundleIDs: ["a"]))]])
        let next = LayoutEdit.renameFolder(layout: layout, folderID: folderID, name: "  ")
        XCTAssertEqual(next.pages[0][0], .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["a"])))
    }

    func testReorderInsideFolderDoesNotCreateAnotherFolder() {
        let layout = Layout(pages: [[.folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["a", "b", "c"]))]])
        let next = LayoutEdit.reorderFolder(layout: layout, folderID: folderID, fromIndex: 0, indexAfterRemoval: 1)
        XCTAssertEqual(next.pages[0][0], .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["b", "a", "c"])))
    }
}
```

`moveOutOfFolder` 先按文件夹还在时的页尾插入，溢出之后再删除已经空的文件夹。上面第二个测试里，拖出 `b` 时文件夹还在，页尾是文件夹后面，所以结果是文件夹在前、`b` 在后。再拖出最后一个 `a` 时，先得到空文件夹加末尾的 `a`，然后删掉空文件夹，页上只剩原来的 `b` 和刚出来的 `a`。

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FolderEditTests`
Expected: FAIL，找不到 `makeFolder`。

- [ ] **Step 3: Write minimal implementation**

继续加进 `LayoutEdit`：

```swift
public static func makeFolder(
    layout: Layout,
    draggedBundleID: String,
    ontoBundleID: String,
    folderID: UUID
) -> Layout {
    guard draggedBundleID != ontoBundleID,
          let dragged = locateApp(layout, draggedBundleID),
          let target = locateApp(layout, ontoBundleID) else { return layout }
    var pages = layout.pages
    pages[dragged.page].remove(at: dragged.index)
    var targetIndex = target.index
    if dragged.page == target.page, dragged.index < target.index {
        targetIndex -= 1
    }
    guard pages[target.page].indices.contains(targetIndex),
          case .app(let bundleID) = pages[target.page][targetIndex],
          bundleID == ontoBundleID else { return layout }
    pages[target.page][targetIndex] = .folder(FolderItem(
        id: folderID,
        name: defaultFolderName,
        bundleIDs: [ontoBundleID, draggedBundleID]
    ))
    pages.removeAll { $0.isEmpty }
    return Layout(pages: pages)
}

public static func addToFolder(layout: Layout, bundleID: String, folderID: UUID) -> Layout {
    guard let app = locateApp(layout, bundleID), let folder = locateFolder(layout, folderID) else { return layout }
    var pages = layout.pages
    pages[app.page].remove(at: app.index)
    var folderIndex = folder.index
    if app.page == folder.page, app.index < folder.index {
        folderIndex -= 1
    }
    guard pages[folder.page].indices.contains(folderIndex),
          case .folder(var item) = pages[folder.page][folderIndex],
          item.id == folderID else { return layout }
    item.bundleIDs.append(bundleID)
    pages[folder.page][folderIndex] = .folder(item)
    pages.removeAll { $0.isEmpty }
    return Layout(pages: pages)
}

public static func moveOutOfFolder(layout: Layout, bundleID: String, folderID: UUID) -> Layout {
    guard let located = locateFolder(layout, folderID),
          case .folder(var folder) = layout.pages[located.page][located.index],
          folder.bundleIDs.contains(bundleID) else { return layout }
    var pages = layout.pages
    folder.bundleIDs.removeAll { $0 == bundleID }
    pages[located.page][located.index] = .folder(folder)
    pages[located.page].insert(.app(bundleID), at: pages[located.page].count)
    pages = spill(pages)
    if folder.bundleIDs.isEmpty, let again = locateFolder(Layout(pages: pages), folderID) {
        pages[again.page].remove(at: again.index)
    }
    pages.removeAll { $0.isEmpty }
    return Layout(pages: pages)
}

public static func reorderFolder(
    layout: Layout,
    folderID: UUID,
    fromIndex: Int,
    indexAfterRemoval: Int
) -> Layout {
    guard let located = locateFolder(layout, folderID),
          case .folder(var folder) = layout.pages[located.page][located.index],
          folder.bundleIDs.indices.contains(fromIndex) else { return layout }
    let bundleID = folder.bundleIDs.remove(at: fromIndex)
    let index = min(max(indexAfterRemoval, 0), folder.bundleIDs.count)
    folder.bundleIDs.insert(bundleID, at: index)
    var pages = layout.pages
    pages[located.page][located.index] = .folder(folder)
    return Layout(pages: pages)
}

public static func renameFolder(layout: Layout, folderID: UUID, name: String) -> Layout {
    guard let located = locateFolder(layout, folderID),
          case .folder(var folder) = layout.pages[located.page][located.index] else { return layout }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    folder.name = trimmed.isEmpty ? defaultFolderName : trimmed
    var pages = layout.pages
    pages[located.page][located.index] = .folder(folder)
    return Layout(pages: pages)
}

private struct Location { var page: Int; var index: Int }

private static func locateApp(_ layout: Layout, _ bundleID: String) -> Location? {
    for (pageIndex, page) in layout.pages.enumerated() {
        if let index = page.firstIndex(where: { if case .app(let id) = $0 { return id == bundleID }; return false }) {
            return Location(page: pageIndex, index: index)
        }
    }
    return nil
}

private static func locateFolder(_ layout: Layout, _ folderID: UUID) -> Location? {
    for (pageIndex, page) in layout.pages.enumerated() {
        if let index = page.firstIndex(where: { if case .folder(let folder) = $0 { return folder.id == folderID }; return false }) {
            return Location(page: pageIndex, index: index)
        }
    }
    return nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FolderEditTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/LayoutEdit.swift Tests/LaunchpadCoreTests/FolderEditTests.swift
git commit -m "Create, fill, rename, and dissolve layout folders."
```

### Task 9: 搜索过滤

**Files:**
- Create: `Sources/LaunchpadCore/AppSearch.swift`
- Test: `Tests/LaunchpadCoreTests/AppSearchTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class AppSearchTests: XCTestCase {
    func testFiltersInLayoutOrderWithoutChangingLayoutOrTruncating() {
        let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let folderMembers = ["com.mail", "com.maps"]
        var layout = Layout(pages: [[
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
        XCTAssertEqual(matches.map(\.bundleID), ["com.mail", "com.maps"])
        XCTAssertEqual(layout.pages[0].count, 3)
        let manyIDs = (1...36).map { "com.item.\($0)" }
        let manyLayout = Layout(pages: [manyIDs.map { .app($0) }])
        let manyRecords = manyIDs.map { record($0, "Gamma \($0)") }
        XCTAssertEqual(AppSearch.filter(layout: manyLayout, records: manyRecords, query: "gamma").count, 36)
    }

    private func record(_ bundleID: String, _ name: String) -> AppRecord {
        AppRecord(bundleID: bundleID, displayName: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }
}
```

`ma` 匹配 Mail 和 Maps，不匹配 Notes 和 Music。结果顺序跟页上的顺序一致，文件夹成员按成员列表展开，插在文件夹所在的位置，不把文件夹本身当结果。36 个显示名都含 `Gamma` 时，查询 `gamma` 返回 36 条，不截成 35 条。

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppSearchTests`
Expected: FAIL，找不到 `AppSearch`。

- [ ] **Step 3: Write minimal implementation**

`Sources/LaunchpadCore/AppSearch.swift`

```swift
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
```

空查询返回空数组。界面在查询为空时直接回到原来的页或文件夹，不调用这个结果去画网格。

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppSearchTests`
Expected: PASS

Run: `swift test`
Expected: Chunk 1 和 Chunk 2 的测试全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/AppSearch.swift Tests/LaunchpadCoreTests/AppSearchTests.swift
git commit -m "Filter apps by display name in layout order."
```

---

## Chunk 3: 布局文件

这一段把内存里的 `Layout` 写成 JSON。同一个 bundle id 出现超过一次时，读取结果是空布局，调用方再按当次扫描重建。

JSON 形状：

```json
{
  "pages": [
    {
      "items": [
        { "type": "app", "bundleID": "com.apple.Safari" },
        {
          "type": "folder",
          "id": "00000000-0000-0000-0000-000000000010",
          "name": "文件夹",
          "items": ["com.apple.mail", "com.apple.Maps"]
        }
      ]
    }
  ]
}
```

### Task 10: 读写 layout.json

**Files:**
- Create: `Sources/LaunchpadCore/LayoutStore.swift`
- Test: `Tests/LaunchpadCoreTests/LayoutStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class LayoutStoreTests: XCTestCase {
    func testMissingInvalidAndDuplicateFilesReadAsNoLayout() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("layout.json")
        let store = LayoutStore(fileURL: url)
        XCTAssertNil(store.load())

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)
        XCTAssertNil(store.load())

        let duplicate = """
        {"pages":[{"items":[
          {"type":"app","bundleID":"com.app"},
          {"type":"app","bundleID":"com.app"}
        ]}]}
        """
        try Data(duplicate.utf8).write(to: url)
        XCTAssertNil(store.load())
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripPreservesFolderOrder() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("layout.json")
        let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let layout = Layout(pages: [[
            .app("com.safari"),
            .folder(FolderItem(id: folderID, name: "文件夹", bundleIDs: ["com.mail", "com.maps"]))
        ]])
        let store = LayoutStore(fileURL: url)
        try store.save(layout)
        XCTAssertEqual(store.load(), layout)
        try? FileManager.default.removeItem(at: directory)
    }

    func testDefaultURLLivesInApplicationSupport() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        XCTAssertEqual(
            LayoutStore.defaultFileURL(home: home).path,
            "/Users/me/Library/Application Support/MacLaunchpad/layout.json"
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LayoutStoreTests`
Expected: FAIL，找不到 `LayoutStore`。

- [ ] **Step 3: Write minimal implementation**

`Sources/LaunchpadCore/LayoutStore.swift`

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LayoutStoreTests`
Expected: PASS

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/LayoutStore.swift Tests/LaunchpadCoreTests/LayoutStoreTests.swift
git commit -m "Persist launchpad layout as JSON."
```

---

## Chunk 4: 窗口、网格、搜索和打开

这一段做出可以双击打开的 `.app`。它能扫描、分页、搜索、点开 App，也能点进已经存在的文件夹并改名。拖拽排序和拖出文件夹放到 Chunk 5。`load()` 返回 `nil` 时调用 `LayoutEdit.fresh`。进程里已经有内存布局时，不再读磁盘。

### Task 11: 可执行产品和状态对象

**Files:**
- Modify: `Package.swift`
- Create: `Sources/LaunchpadApp/LaunchpadModel.swift`
- Test: `Tests/LaunchpadCoreTests/LaunchpadModelLogicTests.swift`

模型里「要不要读磁盘」和「打开失败的文案」抽成纯函数，测试放在核心测试目标能调用的文件里。`LaunchpadModel` 是界面上的薄包装。

- [ ] **Step 1: Write the failing test**

把纯函数先写进测试期望的模块。在 `Sources/LaunchpadCore/SessionPolicy.swift` 实现之前，测试会失败。

```swift
import XCTest
@testable import LaunchpadCore

final class LaunchpadModelLogicTests: XCTestCase {
    func testNilStoreLayoutBecomesFreshAndMemoryLayoutIsKept() {
        let records = [
            AppRecord(bundleID: "com.app", displayName: "Zzz", url: URL(fileURLWithPath: "/Applications/App.app")),
            AppRecord(bundleID: "com.kept", displayName: "Aaa", url: URL(fileURLWithPath: "/Applications/Kept.app"))
        ]
        let fresh = SessionPolicy.layoutForShow(memory: nil, stored: nil, records: [records[0]])
        XCTAssertEqual(fresh.pages, [[.app("com.app")]])
        let memory = Layout(pages: [[.app("com.app"), .app("com.kept")]])
        let stored = Layout(pages: [[.app("com.stored")]])
        let kept = SessionPolicy.layoutForShow(memory: memory, stored: stored, records: records)
        XCTAssertEqual(kept.pages, [[.app("com.app"), .app("com.kept")]])
        let cold = SessionPolicy.layoutForShow(memory: nil, stored: memory, records: records)
        XCTAssertEqual(cold.pages, [[.app("com.app"), .app("com.kept")]])
    }

    func testLaunchFailureMessageUsesDisplayName() {
        XCTAssertEqual(SessionPolicy.launchFailureMessage(displayName: "Safari"), "无法打开Safari")
    }
}
```

没有内存布局、磁盘也没有布局时，按扫描结果新建。已有内存布局时忽略磁盘。内存顺序是 `com.app` 然后 `com.kept`。如果错误地改走磁盘，这两项会变成按显示名排序的新 App，`Aaa` 会排到前面，断言就会失败。

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LaunchpadModelLogicTests`
Expected: FAIL，找不到 `SessionPolicy`。

- [ ] **Step 3: Write minimal implementation**

`Sources/LaunchpadCore/SessionPolicy.swift`

```swift
import Foundation

public enum SessionPolicy {
    public static func layoutForShow(memory: Layout?, stored: Layout?, records: [AppRecord]) -> Layout {
        let base = memory ?? stored
        if let base {
            return LayoutEdit.reconcile(layout: base, records: records)
        }
        return LayoutEdit.fresh(records: records)
    }

    public static func launchFailureMessage(displayName: String) -> String {
        "无法打开\(displayName)"
    }
}
```

`Package.swift` 换成：

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacLaunchpad",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LaunchpadCore", targets: ["LaunchpadCore"]),
        .executable(name: "MacLaunchpad", targets: ["LaunchpadApp"])
    ],
    targets: [
        .target(name: "LaunchpadCore"),
        .executableTarget(name: "LaunchpadApp", dependencies: ["LaunchpadCore"]),
        .testTarget(name: "LaunchpadCoreTests", dependencies: ["LaunchpadCore"])
    ]
)
```

`Sources/LaunchpadApp/LaunchpadModel.swift`

```swift
import AppKit
import Combine
import LaunchpadCore

final class LaunchpadModel: ObservableObject {
    @Published private(set) var records: [AppRecord] = []
    @Published private(set) var layout = Layout(pages: [])
    @Published var query = ""
    @Published var pageIndex = 0
    @Published var openFolderID: UUID?
    @Published var launchError: String?

    private var memory: Layout?
    private let store: LayoutStore
    private let openURL: (URL) -> Bool
    private var errorGeneration = 0

    init(
        store: LayoutStore = LayoutStore(fileURL: LayoutStore.defaultFileURL()),
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.store = store
        self.openURL = openURL
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var searchResults: [AppRecord] {
        AppSearch.filter(layout: layout, records: records, query: query)
    }

    func record(_ bundleID: String) -> AppRecord? {
        records.first { $0.bundleID == bundleID }
    }

    func folder(_ id: UUID) -> FolderItem? {
        for page in layout.pages {
            for item in page {
                if case .folder(let folder) = item, folder.id == id { return folder }
            }
        }
        return nil
    }

    func windowDidShow() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        records = AppCatalog.scan(
            roots: AppCatalog.standardRoots(home: home),
            facts: BundleDisplayNameReader.facts(at:)
        )
        let stored = memory == nil ? store.load() : nil
        layout = SessionPolicy.layoutForShow(memory: memory, stored: stored, records: records)
        memory = layout
        if layout.pages.isEmpty {
            pageIndex = 0
        } else if pageIndex >= layout.pages.count {
            pageIndex = layout.pages.count - 1
        }
    }

    func showPreviousPage() { shiftPage(-1) }
    func showNextPage() { shiftPage(1) }

    func launch(_ bundleID: String) -> Bool {
        guard let record = record(bundleID) else { return false }
        if openURL(record.url) {
            launchError = nil
            return true
        }
        launchError = SessionPolicy.launchFailureMessage(displayName: record.displayName)
        errorGeneration += 1
        let generation = errorGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.errorGeneration == generation else { return }
            self.launchError = nil
        }
        return false
    }

    func renameFolder(id: UUID, to name: String) {
        commit(LayoutEdit.renameFolder(layout: layout, folderID: id, name: name))
    }

    func commit(_ newLayout: Layout) {
        layout = newLayout
        memory = newLayout
        if pageIndex >= layout.pages.count {
            pageIndex = max(0, layout.pages.count - 1)
        }
        try? store.save(newLayout)
    }

    private func shiftPage(_ delta: Int) {
        guard !layout.pages.isEmpty else { return }
        pageIndex = min(max(0, pageIndex + delta), layout.pages.count - 1)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LaunchpadModelLogicTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/LaunchpadCore/SessionPolicy.swift Sources/LaunchpadApp/LaunchpadModel.swift Tests/LaunchpadCoreTests/LaunchpadModelLogicTests.swift
git commit -m "Keep the in-memory layout across window shows."
```

### Task 12: 全屏窗口和网格界面

**Files:**
- Create: `Sources/LaunchpadApp/AppDelegate.swift`
- Create: `Sources/LaunchpadApp/DesktopBackground.swift`
- Create: `Sources/LaunchpadApp/PageGridView.swift`
- Create: `Sources/LaunchpadApp/LaunchpadRootView.swift`
- Create: `Scripts/package-app.sh`

- [ ] **Step 1: Write the app shell**

`Sources/LaunchpadApp/DesktopBackground.swift`

```swift
import AppKit
import SwiftUI

struct DesktopBackground: View {
    var screen: NSScreen?

    var body: some View {
        ZStack {
            if let image = desktopImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                Color.black.opacity(0.28)
            } else {
                Color.black.opacity(0.72)
            }
        }
        .ignoresSafeArea()
    }

    private var desktopImage: NSImage? {
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }
}
```

`Sources/LaunchpadApp/PageGridView.swift`

```swift
import AppKit
import LaunchpadCore
import SwiftUI

struct PageGridView: View {
    let items: [PageItem]
    let record: (String) -> AppRecord?
    let onLaunch: (String) -> Void
    let onOpenFolder: (UUID) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .app(let bundleID):
                    if let app = record(bundleID) {
                        Button { onLaunch(bundleID) } label: { AppTile(record: app) }
                            .buttonStyle(.plain)
                    }
                case .folder(let folder):
                    Button { onOpenFolder(folder.id) } label: {
                        FolderTile(folder: folder, record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AppTile: View {
    let record: AppRecord

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: record.url.path))
                .resizable()
                .frame(width: 64, height: 64)
            Text(record.displayName)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FolderTile: View {
    let folder: FolderItem
    let record: (String) -> AppRecord?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.18))
                    .frame(width: 64, height: 64)
                VStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(0..<2, id: \.self) { column in
                                miniIcon(at: row * 2 + column)
                            }
                        }
                    }
                }
            }
            Text(folder.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func miniIcon(at index: Int) -> some View {
        if folder.bundleIDs.indices.contains(index), let app = record(folder.bundleIDs[index]) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }
}
```

`Sources/LaunchpadApp/LaunchpadRootView.swift`

```swift
import AppKit
import LaunchpadCore
import SwiftUI

struct LaunchpadRootView: View {
    @ObservedObject var model: LaunchpadModel
    var screen: NSScreen?
    var onHide: () -> Void

    private enum FocusTarget: Hashable { case search, folderName }
    @FocusState private var focus: FocusTarget?
    @State private var editingFolderName = false
    @State private var escapeCancelsRename = false
    @State private var folderDraft = ""

    var body: some View {
        ZStack {
            DesktopBackground(screen: screen)
            VStack(spacing: 24) {
                TextField("搜索", text: $model.query)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .frame(width: 280)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .focused($focus, equals: .search)
                if let launchError = model.launchError {
                    Text(launchError).foregroundStyle(.white)
                }
                if model.isSearching {
                    ScrollView {
                        PageGridView(
                            items: model.searchResults.map { .app($0.bundleID) },
                            record: model.record(_:),
                            onLaunch: launch,
                            onOpenFolder: { _ in }
                        )
                    }
                } else if model.layout.pages.indices.contains(model.pageIndex) {
                    PageGridView(
                        items: model.layout.pages[model.pageIndex],
                        record: model.record(_:),
                        onLaunch: launch,
                        onOpenFolder: { model.openFolderID = $0 }
                    )
                }
                Spacer(minLength: 0)
                pageDots
            }
            .padding(36)
            if let folder = model.openFolderID.flatMap(model.folder(_:)), !model.isSearching {
                folderOverlay(folder)
            }
        }
        .background(ScrollWheelPageTurner(enabled: !model.isSearching && model.openFolderID == nil) { delta in
            if delta < 0 { model.showNextPage() } else { model.showPreviousPage() }
        })
        .onAppear { focus = .search }
        .onExitCommand(perform: handleEscape)
        .onChange(of: focus) { _, newFocus in
            guard editingFolderName, newFocus != .folderName else { return }
            if escapeCancelsRename {
                escapeCancelsRename = false
                editingFolderName = false
            } else {
                finishRename(save: true)
            }
        }
        .onKeyPress(.leftArrow) {
            guard model.openFolderID == nil, !model.isSearching, !editingFolderName else { return .ignored }
            model.showPreviousPage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard model.openFolderID == nil, !model.isSearching, !editingFolderName else { return .ignored }
            model.showNextPage()
            return .handled
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(model.layout.pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == model.pageIndex ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .onTapGesture { model.pageIndex = index }
            }
        }
    }

    private func launch(_ bundleID: String) {
        if model.launch(bundleID) { onHide() }
    }

    private func handleEscape() {
        if editingFolderName {
            escapeCancelsRename = true
            focus = .search
            return
        }
        if model.isSearching {
            model.query = ""
            return
        }
        if model.openFolderID != nil {
            model.openFolderID = nil
            return
        }
        onHide()
    }

    private func folderOverlay(_ folder: FolderItem) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !editingFolderName else { return }
                    model.openFolderID = nil
                }
            VStack(spacing: 20) {
                if editingFolderName {
                    TextField("文件夹", text: $folderDraft)
                        .focused($focus, equals: .folderName)
                        .frame(width: 220)
                        .onSubmit { finishRename(save: true) }
                } else {
                    Text(folder.name)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .onTapGesture {
                            folderDraft = folder.name
                            editingFolderName = true
                            focus = .folderName
                        }
                }
                ScrollView {
                    PageGridView(
                        items: folder.bundleIDs.map { .app($0) },
                        record: model.record(_:),
                        onLaunch: launch,
                        onOpenFolder: { _ in }
                    )
                }
            }
            .padding(32)
        }
    }

    private func finishRename(save: Bool) {
        if save, let id = model.openFolderID {
            model.renameFolder(id: id, to: folderDraft)
        }
        editingFolderName = false
        focus = .search
    }
}

private struct ScrollWheelPageTurner: NSViewRepresentable {
    var enabled: Bool
    var onPage: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard context.coordinator.enabled, event.phase == .began else { return event }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            context.coordinator.onPage(event.scrollingDeltaX > 0 ? -1 : 1)
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.onPage = onPage
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        var enabled = false
        var onPage: (Int) -> Void = { _ in }
    }
}
```

`Sources/LaunchpadApp/AppDelegate.swift`

```swift
import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retained: AppDelegate?
    private var window: NSWindow?
    private let model = LaunchpadModel()

    static func main() {
        let delegate = AppDelegate()
        retained = delegate
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        let screen = screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let root = LaunchpadRootView(model: model, screen: screen, onHide: { [weak self] in
            self?.window?.orderOut(nil)
        })
        if let window {
            window.setFrame(screen.frame, display: true)
            window.contentView = NSHostingView(rootView: root)
        } else {
            let window = KeyableBorderlessWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .popUpMenu
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces]
            window.contentView = NSHostingView(rootView: root)
            self.window = window
        }
        model.windowDidShow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }
}

final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

`Scripts/package-app.sh`

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="MacLaunchpad.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacLaunchpad "$APP/Contents/MacOS/MacLaunchpad"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacLaunchpad</string>
  <key>CFBundleIdentifier</key>
  <string>local.maclaunchpad</string>
  <key>CFBundleName</key>
  <string>MacLaunchpad</string>
  <key>CFBundleDisplayName</key>
  <string>程序启动台</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
echo "built $APP"
```

- [ ] **Step 2: Build and package**

Run: `swift test`
Expected: 全部 PASS。

Run: `chmod +x Scripts/package-app.sh && Scripts/package-app.sh`
Expected: 最后一行是 `built MacLaunchpad.app`，并且 `MacLaunchpad.app/Contents/MacOS/MacLaunchpad` 存在。

- [ ] **Step 3: Manual check**

打开 `MacLaunchpad.app`。确认：

- 窗口铺满鼠标所在的屏幕，没有标题栏，背景是模糊壁纸或深色。
- 能看到本机 App。只有一页时也有一个页点。
- 输入文字后网格只剩匹配项，Esc 清空搜索。
- 点击一个 App，它被打开，启动台窗口隐藏，程序仍在程序坞。再点程序坞图标，窗口回来。
- 主网格按 Esc，窗口隐藏。

- [ ] **Step 4: Commit**

```bash
git add Sources/LaunchpadApp Scripts/package-app.sh
git commit -m "Show a fullscreen grid that launches apps."
```

---

## Chunk 5: 拖拽排序和文件夹

落点规则放在 `LaunchpadCore`，界面只提供坐标。插入序号先按当前画面计算，同一列表里再换成「拿走之后」的序号，然后调用 Chunk 2 的 `LayoutEdit`。

图标中心区域是图标边长向内各留 20% 之后的矩形。只有在主网格、并且拖动的是 App 时，这个区域才建文件夹或放进文件夹。其余情况按格子前半段、后半段计算插入序号。

### Task 13: 落点和边缘

**Files:**
- Create: `Sources/LaunchpadCore/GridHit.swift`
- Test: `Tests/LaunchpadCoreTests/GridHitTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LaunchpadCore

final class GridHitTests: XCTestCase {
    func testIconCenterCreatesFolderAndHalvesReorder() {
        let cells = [
            GridCell(index: 0, bundleID: "com.a", iconFrame: CGRect(x: 0, y: 0, width: 100, height: 100), cellFrame: CGRect(x: 0, y: 0, width: 100, height: 120)),
            GridCell(index: 1, bundleID: "com.b", iconFrame: CGRect(x: 120, y: 0, width: 100, height: 100), cellFrame: CGRect(x: 120, y: 0, width: 100, height: 120))
        ]
        let center = GridHit.drop(at: CGPoint(x: 170, y: 50), cells: cells, draggedIsApp: true, allowsNewFolder: true)
        XCTAssertEqual(center, .makeFolder(bundleID: "com.b"))
        let front = GridHit.drop(at: CGPoint(x: 130, y: 50), cells: cells, draggedIsApp: true, allowsNewFolder: true)
        XCTAssertEqual(front, .insert(displayedIndex: 1))
        let folderDraggedOverCenter = GridHit.drop(at: CGPoint(x: 170, y: 50), cells: cells, draggedIsApp: false, allowsNewFolder: true)
        XCTAssertEqual(folderDraggedOverCenter, .insert(displayedIndex: 2))
    }

    func testSecondRowGapUsesThatRow() {
        let cells = [
            GridCell(index: 0, bundleID: "a", iconFrame: CGRect(x: 0, y: 0, width: 80, height: 80), cellFrame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            GridCell(index: 1, bundleID: "b", iconFrame: CGRect(x: 120, y: 0, width: 80, height: 80), cellFrame: CGRect(x: 120, y: 0, width: 100, height: 100)),
            GridCell(index: 2, bundleID: "c", iconFrame: CGRect(x: 0, y: 140, width: 80, height: 80), cellFrame: CGRect(x: 0, y: 140, width: 100, height: 100)),
            GridCell(index: 3, bundleID: "d", iconFrame: CGRect(x: 120, y: 140, width: 80, height: 80), cellFrame: CGRect(x: 120, y: 140, width: 100, height: 100))
        ]
        let drop = GridHit.drop(at: CGPoint(x: 110, y: 180), cells: cells, draggedIsApp: true, allowsNewFolder: true)
        XCTAssertEqual(drop, .insert(displayedIndex: 3))
    }

    func testFolderIconCenterAddsToFolder() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!
        let cell = GridCell(index: 0, folderID: id, iconFrame: CGRect(x: 0, y: 0, width: 100, height: 100), cellFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let drop = GridHit.drop(at: CGPoint(x: 50, y: 50), cells: [cell], draggedIsApp: true, allowsNewFolder: true)
        XCTAssertEqual(drop, .addToFolder(id))
    }

    func testFolderPageNeverCreatesFolder() {
        let cell = GridCell(index: 0, iconFrame: CGRect(x: 0, y: 0, width: 100, height: 100), cellFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let drop = GridHit.drop(at: CGPoint(x: 50, y: 50), cells: [cell], draggedIsApp: true, allowsNewFolder: false)
        XCTAssertEqual(drop, .insert(displayedIndex: 1))
    }

    func testSameListIndexMovesBackByOneAfterRemoval() {
        XCTAssertEqual(DragIndex.afterRemoval(fromIndex: 0, displayedIndex: 2, sameList: true), 1)
        XCTAssertEqual(DragIndex.afterRemoval(fromIndex: 2, displayedIndex: 0, sameList: true), 0)
    }

    func testScreenEdgeUses24PointInset() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(GridHit.edge(at: CGPoint(x: 10, y: 40), in: bounds), -1)
        XCTAssertEqual(GridHit.edge(at: CGPoint(x: 990, y: 40), in: bounds), 1)
        XCTAssertNil(GridHit.edge(at: CGPoint(x: 100, y: 40), in: bounds))
    }
}
```

第二个格子的 `bundleID` 是 `com.b`，所以图标中心返回 `.makeFolder(bundleID: "com.b")`。

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GridHitTests`
Expected: FAIL，找不到 `GridHit`。

- [ ] **Step 3: Write minimal implementation**

`Sources/LaunchpadCore/GridHit.swift`

```swift
import CoreGraphics
import Foundation

public struct GridCell: Equatable {
    public var index: Int
    public var bundleID: String?
    public var folderID: UUID?
    public var iconFrame: CGRect
    public var cellFrame: CGRect

    public init(index: Int, bundleID: String? = nil, folderID: UUID? = nil, iconFrame: CGRect, cellFrame: CGRect) {
        self.index = index
        self.bundleID = bundleID
        self.folderID = folderID
        self.iconFrame = iconFrame
        self.cellFrame = cellFrame
    }
}

public enum GridDrop: Equatable {
    case insert(displayedIndex: Int)
    case makeFolder(bundleID: String)
    case addToFolder(UUID)
}

public enum DragIndex {
    public static func afterRemoval(fromIndex: Int, displayedIndex: Int, sameList: Bool) -> Int {
        if sameList, fromIndex < displayedIndex { return displayedIndex - 1 }
        return displayedIndex
    }
}

public enum GridHit {
    public static func drop(
        at point: CGPoint,
        cells: [GridCell],
        draggedIsApp: Bool,
        allowsNewFolder: Bool
    ) -> GridDrop {
        if let cell = cells.first(where: { $0.iconFrame.contains(point) }),
           allowsNewFolder,
           draggedIsApp,
           center(of: cell.iconFrame).contains(point) {
            if let folderID = cell.folderID { return .addToFolder(folderID) }
            if let bundleID = cell.bundleID { return .makeFolder(bundleID: bundleID) }
        }
        if let cell = cells.first(where: { $0.cellFrame.contains(point) }) {
            let displayedIndex = point.x < cell.cellFrame.midX ? cell.index : cell.index + 1
            return .insert(displayedIndex: displayedIndex)
        }
        return .insert(displayedIndex: insertionIndex(point, cells))
    }

    private static func insertionIndex(_ point: CGPoint, _ cells: [GridCell]) -> Int {
        guard !cells.isEmpty else { return 0 }
        let nearestY = cells.map(\.cellFrame.midY).min { abs($0 - point.y) < abs($1 - point.y) } ?? point.y
        let row = cells.filter { abs($0.cellFrame.midY - nearestY) < 1 }.sorted { $0.cellFrame.minX < $1.cellFrame.minX }
        if let next = row.first(where: { $0.cellFrame.midX > point.x }) {
            return next.index
        }
        return (row.last?.index ?? -1) + 1
    }

    public static func edge(at point: CGPoint, in bounds: CGRect, inset: CGFloat = 24) -> Int? {
        if point.x <= bounds.minX + inset { return -1 }
        if point.x >= bounds.maxX - inset { return 1 }
        return nil
    }

    private static func center(of frame: CGRect) -> CGRect {
        frame.insetBy(dx: frame.width * 0.2, dy: frame.height * 0.2)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GridHitTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadCore/GridHit.swift Tests/LaunchpadCoreTests/GridHitTests.swift
git commit -m "Decide folder drops and reorder indexes from pointer location."
```

### Task 14: 把拖拽接到网格

**Files:**
- Modify: `Sources/LaunchpadApp/PageGridView.swift`
- Modify: `Sources/LaunchpadApp/LaunchpadRootView.swift`
- Modify: `Sources/LaunchpadApp/LaunchpadModel.swift`

- [ ] **Step 1: 给模型补三个提交方法**

在 `LaunchpadModel` 里增加：

```swift
func makeFolder(dragged: String, onto: String) {
    commit(LayoutEdit.makeFolder(layout: layout, draggedBundleID: dragged, ontoBundleID: onto, folderID: UUID()))
}

func addToFolder(bundleID: String, folderID: UUID) {
    commit(LayoutEdit.addToFolder(layout: layout, bundleID: bundleID, folderID: folderID))
}

func moveOut(bundleID: String, folderID: UUID) {
    commit(LayoutEdit.moveOutOfFolder(layout: layout, bundleID: bundleID, folderID: folderID))
}

func reorder(fromPage: Int, fromIndex: Int, toPage: Int, indexAfterRemoval: Int) {
    commit(LayoutEdit.move(layout: layout, fromPage: fromPage, fromIndex: fromIndex, toPage: toPage, indexAfterRemoval: indexAfterRemoval))
}

func reorderFolderMember(folderID: UUID, fromIndex: Int, indexAfterRemoval: Int) {
    commit(LayoutEdit.reorderFolder(layout: layout, folderID: folderID, fromIndex: fromIndex, indexAfterRemoval: indexAfterRemoval))
}
```

- [ ] **Step 2: 格子报告图标坐标并区分点击和拖拽**

替换 `PageGridView` 这个结构体，并加上偏好键。保留原文件里的 `AppTile` 和 `FolderTile`。坐标空间 `launchpad` 改由根视图提供，网格自己不再声明。`dragEnabled` 为 false 时只保留点击，搜索结果使用这个状态。单击必须走 `minimumDistance: 0` 的 `onEnded`，不能再依赖不会触发的 `onTapGesture`。

```swift
import AppKit
import CoreGraphics
import LaunchpadCore
import SwiftUI

struct PageGridView: View {
    let items: [PageItem]
    let record: (String) -> AppRecord?
    var dragEnabled: Bool
    let onLaunch: (String) -> Void
    let onOpenFolder: (UUID) -> Void
    var reportsFolderFrames: Bool = false
    var onDragChanged: (Int, CGPoint) -> Void
    var onDragEnded: (Int, CGPoint) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                tile(index: index, item: item)
                    .background(frameReader(index: index, item: item))
            }
        }
        .background {
            if reportsFolderFrames {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: FolderGridFrameKey.self,
                        value: proxy.frame(in: .named("launchpad"))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func tile(index: Int, item: PageItem) -> some View {
        PressableTile(dragEnabled: dragEnabled, onActivate: { activate(item) }) { point in
            onDragChanged(index, point)
        } label: {
            tileLabel(item)
        }
    }

    @ViewBuilder
    private func tileLabel(_ item: PageItem) -> some View {
        switch item {
        case .app(let bundleID):
            if let app = record(bundleID) { AppTile(record: app) } else { EmptyView() }
        case .folder(let folder):
            FolderTile(folder: folder, record: record)
        }
    }

    private func activate(_ item: PageItem) {
        switch item {
        case .app(let bundleID): onLaunch(bundleID)
        case .folder(let folder): onOpenFolder(folder.id)
        }
    }

    private func frameReader(index: Int, item: PageItem) -> some View {
        GeometryReader { proxy in
            let cell = proxy.frame(in: .named("launchpad"))
            let icon = CGRect(x: cell.midX - 32, y: cell.minY, width: 64, height: 64)
            let cellValue = [GridCell(
                    index: index,
                    bundleID: { if case .app(let bundleID) = item { return bundleID }; return nil }(),
                    folderID: { if case .folder(let folder) = item { return folder.id }; return nil }(),
                    iconFrame: icon,
                    cellFrame: cell
                )]
            Group {
                if reportsFolderFrames {
                    Color.clear.preference(key: FolderIconFrameKey.self, value: cellValue)
                } else {
                    Color.clear.preference(key: MainIconFrameKey.self, value: cellValue)
                }
            }
        }
    }
}

struct MainIconFrameKey: PreferenceKey {
    static var defaultValue: [GridCell] = []
    static func reduce(value: inout [GridCell], nextValue: () -> [GridCell]) {
        value.append(contentsOf: nextValue())
    }
}

private struct PressableTile<Label: View>: View {
    var dragEnabled: Bool
    var onActivate: () -> Void
    var onDrag: (CGPoint) -> Void
    @ViewBuilder var label: () -> Label
    @State private var passedThreshold = false

    var body: some View {
        if dragEnabled {
            label().gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("launchpad"))
                    .onChanged { value in
                        guard hypot(value.translation.width, value.translation.height) >= 8 else { return }
                        passedThreshold = true
                        onDrag(value.location)
                    }
                    .onEnded { _ in
                        if !passedThreshold { onActivate() }
                        passedThreshold = false
                    }
            )
        } else {
            label().onTapGesture(perform: onActivate)
        }
    }
}

struct FolderIconFrameKey: PreferenceKey {
    static var defaultValue: [GridCell] = []
    static func reduce(value: inout [GridCell], nextValue: () -> [GridCell]) {
        value.append(contentsOf: nextValue())
    }
}
```

App 格子只填 `bundleID`，文件夹格子只填 `folderID`。`GridHit.drop` 先看 `folderID`，所以图标中心会返回 `addToFolder`，不会把文件夹当成普通 App 去新建文件夹。`FolderGridFrameKey` 和 `MainIconFrameKey` 放在同一个文件，不要加 `private`，根视图才能读到内页网格的矩形。位移一旦超过 8 点，`passedThreshold` 保持为真，松手只由鼠标监视器收尾，不再调用 `activate`。

现有 `LaunchpadRootView` 里每一处 `PageGridView(...)` 都补上：

```swift
dragEnabled: !model.isSearching,
reportsFolderFrames: false,
onDragChanged: { index, point in dragChanged(index: index, point: point, inFolder: false) },
onDragEnded: { _, _ in }
```

文件夹内页那一处使用 `dragEnabled: true`、`reportsFolderFrames: true`，`onDragChanged` 传 `inFolder: true`。搜索结果使用 `dragEnabled: false`，拖拽闭包留空。主网格和内页都不要在搜索时翻页。

- [ ] **Step 3: 在根视图里解释拖拽**

给 `LaunchpadRootView` 增加状态：

```swift
@State private var mainCells: [GridCell] = []
@State private var folderCells: [GridCell] = []
@State private var rootBounds: CGRect = .zero
@State private var folderGridFrame: CGRect = .null
@State private var dragFrom: (page: Int, index: Int)?
@State private var folderDragIndex: Int?
@State private var dragMonitor: Any?
@State private var edgeTask: Task<Void, Never>?
@State private var edgeDirection: Int?
@State private var transientPage = false
```

根视图最外层 `ZStack` 加上 `.coordinateSpace(name: "launchpad")`。用背景里的 `GeometryReader` 把根视图矩形记到 `rootBounds`。主网格监听 `MainIconFrameKey`，内页监听 `FolderIconFrameKey` 和 `FolderGridFrameKey`。两套格子不要写进同一个数组。

没有搜索时，主网格始终显示。页码等于 `pages.count` 时表示拖拽中的空页，格子列表用 `[]`，页点多一个。不要因为下标越界把网格从视图树里拿掉。

拖拽一旦超过 8 点，就安装本地鼠标监视器。之后即使格子被翻页拆掉，监视器仍然收得到移动和松手。窗口坐标左下角为原点，根视图铺满窗口，所以转成 `launchpad` 坐标时用内容高度减 y。

```swift
private func dragChanged(index: Int, point: CGPoint, inFolder: Bool) {
    guard dragMonitor == nil else { return }
    if inFolder {
        folderDragIndex = index
    } else if model.layout.pages.indices.contains(model.pageIndex) {
        dragFrom = (model.pageIndex, index)
    }
    dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
        let point = self.pointer(event)
        if event.type == .leftMouseUp { self.finishDrag(at: point) }
        else { self.follow(point) }
        return event
    }
}

private func pointer(_ event: NSEvent) -> CGPoint {
    let location = event.locationInWindow
    let height = event.window?.contentView?.bounds.height ?? rootBounds.height
    return CGPoint(x: location.x, y: height - location.y)
}

private func follow(_ point: CGPoint) {
    guard folderDragIndex == nil else { return }
    let edge = GridHit.edge(at: point, in: rootBounds)
    guard edge != edgeDirection else { return }
    edgeDirection = edge
    edgeTask?.cancel()
    guard let edge else { return }
    edgeTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        self.turn(edge)
    }
}

private func turn(_ edge: Int) {
    if edge < 0 {
        guard model.pageIndex > 0 else { return }
        if transientPage {
            transientPage = false
            model.pageIndex = max(0, model.layout.pages.count - 1)
        } else {
            model.showPreviousPage()
        }
        return
    }
    if model.pageIndex + 1 < model.layout.pages.count {
        model.showNextPage()
    } else if !transientPage {
        transientPage = true
        model.pageIndex = model.layout.pages.count
    }
}

private func finishDrag(at point: CGPoint) {
    guard dragFrom != nil || folderDragIndex != nil else { return }
    if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
    self.dragMonitor = nil
    edgeTask?.cancel()
    if let index = folderDragIndex, let folderID = model.openFolderID {
        if !folderGridFrame.contains(point),
           let folder = model.folder(folderID),
           folder.bundleIDs.indices.contains(index) {
            model.moveOut(bundleID: folder.bundleIDs[index], folderID: folderID)
        } else if case .insert(let displayedIndex) = GridHit.drop(
            at: point, cells: folderCells, draggedIsApp: true, allowsNewFolder: false
        ) {
            let target = DragIndex.afterRemoval(fromIndex: index, displayedIndex: displayedIndex, sameList: true)
            model.reorderFolderMember(folderID: folderID, fromIndex: index, indexAfterRemoval: target)
        }
    } else if let origin = dragFrom, model.layout.pages.indices.contains(origin.page) {
        let item = model.layout.pages[origin.page][origin.index]
        let draggedIsApp = { if case .app = item { return true }; return false }()
        let drop = GridHit.drop(at: point, cells: mainCells, draggedIsApp: draggedIsApp, allowsNewFolder: true)
        switch drop {
        case .makeFolder(let target):
            if case .app(let dragged) = item { model.makeFolder(dragged: dragged, onto: target) }
        case .addToFolder(let folderID):
            if case .app(let dragged) = item { model.addToFolder(bundleID: dragged, folderID: folderID) }
        case .insert(let displayedIndex):
            let toPage = min(model.pageIndex, model.layout.pages.count)
            let target = DragIndex.afterRemoval(
                fromIndex: origin.index,
                displayedIndex: displayedIndex,
                sameList: origin.page == toPage
            )
            model.reorder(fromPage: origin.page, fromIndex: origin.index, toPage: toPage, indexAfterRemoval: target)
        }
    }
    dragFrom = nil
    folderDragIndex = nil
    edgeDirection = nil
    if transientPage, model.pageIndex >= model.layout.pages.count {
        model.pageIndex = max(0, model.layout.pages.count - 1)
    }
    transientPage = false
}
```

```swift
private struct RootBoundsKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct FolderGridFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
```

`folderGridFrame` 来自文件夹网格自身，不是包住它的 `ScrollView`。网格下面的暗色区域不在这个矩形里，松手就算拖出。内页拖拽不调用 `follow`，所以不会翻主网格。

放进临时空页时，`reorder` 会先把那一页建出来，`pageIndex` 就小于新的 `pages.count`，页码保留。没有放进去时，再把页码收回最后一张真实页。

- [ ] **Step 4: 构建并手测**

Run: `swift test`
Expected: 全部 PASS。

Run: `Scripts/package-app.sh`
Expected: `built MacLaunchpad.app`

打开应用后确认：

- 把一个 App 拖到另一个 App 图标中心，出现名为「文件夹」的格子，成员顺序是目标在前。
- 拖到图标中心以外，只换位置，不建文件夹。
- 在文件夹里拖动只改顺序。拖到网格外面的暗色区域，App 回到文件夹所在页的末尾；拖出最后一个后文件夹消失。
- 拖到屏幕右缘约半秒，翻到下一页；最后一页再停住会多出一页。没在新页放下就松手时，空页不保留。

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchpadApp/PageGridView.swift Sources/LaunchpadApp/LaunchpadRootView.swift Sources/LaunchpadApp/LaunchpadModel.swift
git commit -m "Reorder apps and create folders by dragging."
```
