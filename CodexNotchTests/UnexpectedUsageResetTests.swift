@testable import CodexNotch
import XCTest

final class UnexpectedUsageResetTests: XCTestCase {
    private let scheduledReset = Date(timeIntervalSince1970: 10_000)

    func testDetectsUsageDropBeforeScheduledWeeklyReset() {
        let reset = UnexpectedUsageResetDetector.detect(
            previous: observation(used: 42, fetchedAt: 1_000),
            current: observation(used: 2, fetchedAt: 1_300)
        )

        XCTAssertEqual(reset?.droppedPercentagePoints, 40)
    }

    func testDoesNotReportNormalScheduledReset() {
        let reset = UnexpectedUsageResetDetector.detect(
            previous: observation(used: 42, fetchedAt: 9_500),
            current: observation(used: 0, fetchedAt: 10_100)
        )

        XCTAssertNil(reset)
    }

    func testDoesNotReportOrdinaryUsageIncreaseOrTinyDataJitter() {
        XCTAssertNil(UnexpectedUsageResetDetector.detect(
            previous: observation(used: 20, fetchedAt: 1_000),
            current: observation(used: 21, fetchedAt: 1_300)
        ))
        XCTAssertNil(UnexpectedUsageResetDetector.detect(
            previous: observation(used: 17, fetchedAt: 1_000),
            current: observation(used: 16, fetchedAt: 1_300)
        ))
    }

    func testDoesNotReportLargeDropThatDoesNotEndNearZero() {
        XCTAssertNil(UnexpectedUsageResetDetector.detect(
            previous: observation(used: 80, fetchedAt: 1_000),
            current: observation(used: 20, fetchedAt: 1_300)
        ))
    }

    func testDoesNotReportSmallAbsoluteDropEvenWhenItEndsAtZero() {
        XCTAssertNil(UnexpectedUsageResetDetector.detect(
            previous: observation(used: 4, fetchedAt: 1_000),
            current: observation(used: 0, fetchedAt: 1_300)
        ))
    }

    func testRequiresKnownScheduledResetTime() {
        let previous = WeeklyUsageObservation(
            usedPercent: 42,
            resetsAt: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
        let reset = UnexpectedUsageResetDetector.detect(
            previous: previous,
            current: observation(used: 0, fetchedAt: 1_300)
        )

        XCTAssertNil(reset)
    }

    private func observation(used: Double, fetchedAt: TimeInterval) -> WeeklyUsageObservation {
        WeeklyUsageObservation(
            usedPercent: used,
            resetsAt: scheduledReset,
            fetchedAt: Date(timeIntervalSince1970: fetchedAt)
        )
    }
}
