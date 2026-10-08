import Foundation
import Testing
@testable import LaunchpadCore

struct CatalogRootTests {
    @Test func standardRootsMatchSpecPriority() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let roots = AppCatalog.standardRoots(home: home)
        let described = roots.map { "\($0.priority) \($0.kind) \($0.url.path)" }
        #expect(described == [
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
