@testable import CodexNotch
import XCTest

@MainActor
final class UsageResetMonitorTests: XCTestCase {
    func testUserInitiatedMarkerSuppressesUnexpectedReset() async throws {
        let notifier = RecordingResetNotifier()
        let defaults = makeDefaults()
        let monitor = UsageResetMonitor(notifier: notifier, defaults: defaults)

        try await monitor.observe(snapshot(used: 42, fetchedAt: 1_000))
        monitor.markNextResetAsUserInitiated()
        try await monitor.observe(snapshot(used: 0, fetchedAt: 1_300))
        try await monitor.observe(snapshot(used: 1, fetchedAt: 1_600))

        let attemptCount = await notifier.attemptCount
        XCTAssertEqual(attemptCount, 0)
        XCTAssertFalse(monitor.isManualResetSuppressionActive)
    }

    func testFailedDeliveryRemainsPendingAndRetriesOnNextObservation() async throws {
        let notifier = RecordingResetNotifier(failuresBeforeSuccess: 1)
        let monitor = UsageResetMonitor(notifier: notifier, defaults: makeDefaults())

        try await monitor.observe(snapshot(used: 42, fetchedAt: 1_000))
        try await monitor.observe(snapshot(used: 0, fetchedAt: 1_300))
        try await monitor.observe(snapshot(used: 1, fetchedAt: 1_600))
        do {
            try await monitor.observe(snapshot(used: 2, fetchedAt: 1_900))
            XCTFail("Expected the first delivery to fail")
        } catch {
            // The pending event should survive this failure.
        }
        try await monitor.observe(snapshot(used: 3, fetchedAt: 2_200))

        let attemptCount = await notifier.attemptCount
        let deliveredCount = await notifier.deliveredCount
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(deliveredCount, 1)
    }

    func testResetLikeSampleMustSurviveTwoLaterPollsBeforeSending() async throws {
        let notifier = RecordingResetNotifier()
        let monitor = UsageResetMonitor(notifier: notifier, defaults: makeDefaults())

        try await monitor.observe(snapshot(used: 42, fetchedAt: 1_000))
        try await monitor.observe(snapshot(used: 0, fetchedAt: 1_300))
        let attemptsAfterCandidate = await notifier.attemptCount
        XCTAssertEqual(attemptsAfterCandidate, 0)

        try await monitor.observe(snapshot(used: 1, fetchedAt: 1_600))
        let attemptsAfterFirstConfirmation = await notifier.attemptCount
        XCTAssertEqual(attemptsAfterFirstConfirmation, 0)

        try await monitor.observe(snapshot(used: 2, fetchedAt: 1_900))
        let attemptsAfterSecondConfirmation = await notifier.attemptCount
        XCTAssertEqual(attemptsAfterSecondConfirmation, 1)
    }

    private func snapshot(used: Double, fetchedAt: TimeInterval) -> UsageSnapshot {
        UsageSnapshot(
            // NOTE: Codex 已取消 5 小时限额，primary 传 nil。
            primary: nil,
            secondary: UsageWindow(
                usedPercent: used,
                durationMinutes: 10_080,
                resetsAt: Date(timeIntervalSince1970: 10_000)
            ),
            fetchedAt: Date(timeIntervalSince1970: fetchedAt)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageResetMonitorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private actor RecordingResetNotifier: UsageResetNotifying {
    private(set) var attemptCount = 0
    private(set) var deliveredCount = 0
    private var failuresBeforeSuccess: Int

    init(failuresBeforeSuccess: Int = 0) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func notifyUnexpectedReset(_ reset: UnexpectedUsageReset) async throws {
        attemptCount += 1
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw TestNotificationError.failed
        }
        deliveredCount += 1
    }
}

private enum TestNotificationError: Error {
    case failed
}
