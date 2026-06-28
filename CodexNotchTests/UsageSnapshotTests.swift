@testable import CodexNotch
import XCTest

final class UsageSnapshotTests: XCTestCase {
    func testRemainingPercentageIsClamped() {
        XCTAssertEqual(UsageWindow(usedPercent: 24, durationMinutes: 300, resetsAt: nil).remainingPercent, 76)
        XCTAssertEqual(UsageWindow(usedPercent: 120, durationMinutes: 300, resetsAt: nil).remainingPercent, 0)
        XCTAssertEqual(UsageWindow(usedPercent: -5, durationMinutes: 300, resetsAt: nil).remainingPercent, 100)
    }

    func testKnownWindowTitles() {
        XCTAssertEqual(UsageWindow(usedPercent: 0, durationMinutes: 300, resetsAt: nil).title, "5 小时")
        XCTAssertEqual(UsageWindow(usedPercent: 0, durationMinutes: 10_080, resetsAt: nil).title, "一周")
    }
}

