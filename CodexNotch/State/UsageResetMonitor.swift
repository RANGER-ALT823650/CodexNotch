import Foundation

@MainActor
final class UsageResetMonitor {
    private enum Key {
        static let previousObservation = "codexResetMonitor.previousObservation"
        static let resetCandidate = "codexResetMonitor.resetCandidate"
        static let pendingReset = "codexResetMonitor.pendingReset"
        static let manualResetSuppressionUntil = "codexResetMonitor.manualResetSuppressionUntil"
    }

    private let notifier: any UsageResetNotifying
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        notifier: any UsageResetNotifying = OpenClawTelegramResetNotifier(),
        defaults: UserDefaults = .standard
    ) {
        self.notifier = notifier
        self.defaults = defaults
    }

    var manualResetSuppressionUntil: Date? {
        defaults.object(forKey: Key.manualResetSuppressionUntil) as? Date
    }

    var isManualResetSuppressionActive: Bool {
        guard let until = manualResetSuppressionUntil else { return false }
        return until > Date()
    }

    func markNextResetAsUserInitiated(now: Date = Date()) {
        defaults.set(now.addingTimeInterval(10 * 60), forKey: Key.manualResetSuppressionUntil)
    }

    func observe(_ snapshot: UsageSnapshot) async throws {
        let current = WeeklyUsageObservation(snapshot: snapshot)
        let previous: WeeklyUsageObservation? = decode(forKey: Key.previousObservation)

        if decode(UnexpectedUsageReset.self, forKey: Key.pendingReset) == nil {
            if let candidate = decode(UnexpectedUsageReset.self, forKey: Key.resetCandidate) {
                evaluateCandidate(candidate, against: current)
            } else if let previous,
                      let reset = UnexpectedUsageResetDetector.detect(
                          previous: previous,
                          current: current
                      )
            {
                if isManualResetSuppressionActive {
                    defaults.removeObject(forKey: Key.manualResetSuppressionUntil)
                } else {
                    // A single anomalous response is not enough. Keep it as a
                    // candidate until a later poll confirms usage remains near zero.
                    encode(reset, forKey: Key.resetCandidate)
                }
            }
        }

        encode(current, forKey: Key.previousObservation)

        guard let pending = decode(UnexpectedUsageReset.self, forKey: Key.pendingReset) else {
            return
        }
        try await notifier.notifyUnexpectedReset(pending)
        defaults.removeObject(forKey: Key.pendingReset)
    }

    private func evaluateCandidate(
        _ candidate: UnexpectedUsageReset,
        against current: WeeklyUsageObservation
    ) {
        guard current.fetchedAt > candidate.current.fetchedAt else { return }

        // Automatic polling runs every five minutes. Requiring at least eight
        // minutes means a reset-like value must survive two later polls (about
        // ten minutes total), not merely one transient app-server response.
        let confirmationDelay: TimeInterval = 8 * 60
        let usageStillNearZero = current.usedPercent <= 5
        let stillBeforeScheduledReset = candidate.previous.resetsAt.map {
            current.fetchedAt < $0.addingTimeInterval(-5 * 60)
        } ?? false

        guard usageStillNearZero, stillBeforeScheduledReset else {
            defaults.removeObject(forKey: Key.resetCandidate)
            return
        }
        guard current.fetchedAt.timeIntervalSince(candidate.current.fetchedAt) >= confirmationDelay else {
            return
        }

        defaults.removeObject(forKey: Key.resetCandidate)
        if isManualResetSuppressionActive {
            defaults.removeObject(forKey: Key.manualResetSuppressionUntil)
            return
        }
        encode(
            UnexpectedUsageReset(previous: candidate.previous, current: current),
            forKey: Key.pendingReset
        )
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type = T.self, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
