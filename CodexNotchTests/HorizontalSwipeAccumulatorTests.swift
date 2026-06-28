@testable import CodexNotch
import XCTest

final class HorizontalSwipeAccumulatorTests: XCTestCase {
    func testTriggersLeftAfterHorizontalThreshold() {
        var accumulator = HorizontalSwipeAccumulator(threshold: 30)
        accumulator.begin()

        XCTAssertNil(accumulator.add(deltaX: -18, deltaY: 2))
        XCTAssertEqual(accumulator.add(deltaX: -14, deltaY: 1), .left)
    }

    func testIgnoresMostlyVerticalScrolling() {
        var accumulator = HorizontalSwipeAccumulator(threshold: 20)
        accumulator.begin()

        XCTAssertNil(accumulator.add(deltaX: 12, deltaY: 30))
        XCTAssertNil(accumulator.add(deltaX: 12, deltaY: 30))
    }

    func testTriggersOnlyOnceUntilGestureEnds() {
        var accumulator = HorizontalSwipeAccumulator(threshold: 20)
        accumulator.begin()

        XCTAssertEqual(accumulator.add(deltaX: 24, deltaY: 0), .right)
        XCTAssertNil(accumulator.add(deltaX: 30, deltaY: 0))

        accumulator.end()
        accumulator.begin()
        XCTAssertEqual(accumulator.add(deltaX: -24, deltaY: 0), .left)
    }
}

