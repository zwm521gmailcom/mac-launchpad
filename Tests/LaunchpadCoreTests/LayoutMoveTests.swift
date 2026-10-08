import Foundation
import Testing
@testable import LaunchpadCore

struct LayoutMoveTests {
    @Test func samePageUsesIndexAfterRemoval() {
        let layout = Layout(pages: [[.app("a"), .app("b"), .app("c")]])
        let next = LayoutEdit.move(layout: layout, fromPage: 0, fromIndex: 0, toPage: 0, indexAfterRemoval: 1)
        #expect(next.pages == [[.app("b"), .app("a"), .app("c")]])
    }

    @Test func crossPageCompactsSource() {
        let layout = Layout(pages: [[.app("a"), .app("b")], [.app("c")]])
        let next = LayoutEdit.move(layout: layout, fromPage: 0, fromIndex: 0, toPage: 1, indexAfterRemoval: 0)
        #expect(next.pages == [[.app("b")], [.app("a"), .app("c")]])
    }

    @Test func fullPagePushesLastItemToNextPageStart() {
        let first = (0..<35).map { PageItem.app("a.\($0)") }
        let layout = Layout(pages: [first, [.app("b")]])
        let next = LayoutEdit.move(layout: layout, fromPage: 1, fromIndex: 0, toPage: 0, indexAfterRemoval: 0)
        #expect(next.pages[0].count == 35)
        #expect(next.pages[0][0] == .app("b"))
        #expect(next.pages[1] == [.app("a.34")])
    }

    @Test func movingOntoANewPageDropsTheEmptiedSource() {
        let layout = Layout(pages: [[.app("stay"), .app("move")]])
        let next = LayoutEdit.move(layout: layout, fromPage: 0, fromIndex: 1, toPage: 1, indexAfterRemoval: 0)
        #expect(next.pages == [[.app("stay")], [.app("move")]])
    }
}
