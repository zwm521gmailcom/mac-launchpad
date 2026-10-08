import CoreGraphics
import Foundation
import Testing
@testable import LaunchpadCore

struct GridMetricsTests {
    @Test func largeScreenHoldsMoreThanSevenByFive() {
        let metrics = GridMetrics.fitting(width: 2488, height: 1000, icon: 120)
        #expect(metrics.columns >= 8)
        #expect(metrics.rows >= 4)
        #expect(metrics.capacity > Layout.pageCapacity)
        #expect(metrics.icon == 120)
    }

    @Test func biggerIconsLeaveFewerSlots() {
        let small = GridMetrics.fitting(width: 2488, height: 1000, icon: 72)
        let big = GridMetrics.fitting(width: 2488, height: 1000, icon: 160)
        #expect(big.capacity < small.capacity)
    }

    @Test func reflowFillsEveryPageExceptTheLast() {
        let items = (0..<10).map { PageItem.app("id.\($0)") }
        let layout = Layout(pages: [Array(items.prefix(3)), Array(items.dropFirst(3))])
        let next = LayoutEdit.reflow(layout: layout, capacity: 4)
        #expect(next.pages.map(\.count) == [4, 4, 2])
        #expect(next.pages.flatMap { $0 } == items)
    }
}
