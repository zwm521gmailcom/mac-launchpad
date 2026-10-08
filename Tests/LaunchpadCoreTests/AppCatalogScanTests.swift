import Foundation
import Testing
@testable import LaunchpadCore

struct AppCatalogScanTests {
    @Test func skipsMissingRootsUnreadableBundlesAndNestedApps() throws {
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

        #expect(records.map(\.bundleID) == ["com.good"])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func caskroomReadsOnlyNameVersionApp() throws {
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
        #expect(records.map(\.bundleID) == ["id.Firefox"])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func emptyDisplayNameFallsBackToFileName() {
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
        #expect(records.map(\.displayName) == ["Notes"])
    }

    @Test func scanKeepsHigherPriorityRoot() {
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
        #expect(records.map(\.url.path) == [user.path])
    }

    @Test func blankBundleIDIsSkipped() {
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
        #expect(records.isEmpty)
    }
}

struct BundleDisplayNameReaderTests {
    @Test func skipsBlankDisplayNameThenBundleNameThenFileName() {
        #expect(
            BundleDisplayNameReader.resolve(displayName: "  ", bundleName: "From Bundle", fileName: "File")
            == "From Bundle"
        )
        #expect(
            BundleDisplayNameReader.resolve(displayName: nil, bundleName: " ", fileName: "File")
            == "File"
        )
        #expect(
            BundleDisplayNameReader.resolve(displayName: nil, bundleName: nil, fileName: " ")
            == ""
        )
    }

    @Test func realBundleUsesInfoPlistKeysInOrder() throws {
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
        #expect(facts?.bundleID == "com.demo")
        #expect(facts?.displayName == "Plist Name")
        try? FileManager.default.removeItem(at: root)
    }
}
