import Foundation

struct WeeklyUsageObservation: Codable, Equatable, Sendable {
    let usedPercent: Double
    let resetsAt: Date?
    let fetchedAt: Date

    init(usedPercent: Double, resetsAt: Date?, fetchedAt: Date) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.fetchedAt = fetchedAt
    }

    init(snapshot: UsageSnapshot) {
        usedPercent = snapshot.secondary.usedPercent
        resetsAt = snapshot.secondary.resetsAt
        fetchedAt = snapshot.fetchedAt
    }
}

struct UnexpectedUsageReset: Codable, Equatable, Sendable {
    let previous: WeeklyUsageObservation
    let current: WeeklyUsageObservation

    var droppedPercentagePoints: Double {
        previous.usedPercent - current.usedPercent
    }
}

enum UnexpectedUsageResetDetector {
    /// Codex does not expose a reset-source field. A falling weekly usage value is
    /// therefore considered unexpected only while the previously advertised reset
    /// time is still safely in the future. The tolerance prevents a poll close to
    /// the normal seven-day boundary from being reported as an early reset.
    static func detect(
        previous: WeeklyUsageObservation,
        current: WeeklyUsageObservation,
        minimumDrop: Double = 5,
        minimumRelativeDrop: Double = 0.8,
        maximumPostResetUsage: Double = 5,
        scheduledResetTolerance: TimeInterval = 10 * 60
    ) -> UnexpectedUsageReset? {
        let drop = previous.usedPercent - current.usedPercent
        guard current.fetchedAt > previous.fetchedAt,
              previous.usedPercent > 0,
              drop >= minimumDrop,
              drop / previous.usedPercent >= minimumRelativeDrop,
              current.usedPercent <= maximumPostResetUsage,
              let scheduledReset = previous.resetsAt,
              current.fetchedAt < scheduledReset.addingTimeInterval(-scheduledResetTolerance)
        else {
            return nil
        }

        return UnexpectedUsageReset(previous: previous, current: current)
    }
}
