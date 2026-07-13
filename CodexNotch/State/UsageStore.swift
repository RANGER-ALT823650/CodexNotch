import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private let provider: any CodexUsageProviding
    private let resetMonitor: UsageResetMonitor
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?

    private(set) var snapshot: UsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var resetNotificationError: String?
    private(set) var manualResetSuppressionUntil: Date?

    init(
        provider: any CodexUsageProviding,
        resetMonitor: UsageResetMonitor = UsageResetMonitor()
    ) {
        self.provider = provider
        self.resetMonitor = resetMonitor
        manualResetSuppressionUntil = resetMonitor.manualResetSuppressionUntil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let nextSnapshot = try await provider.fetchUsage()
            snapshot = nextSnapshot
            errorMessage = nil
            do {
                try await resetMonitor.observe(nextSnapshot)
                resetNotificationError = nil
            } catch {
                // Usage remains valid even when Telegram delivery fails. The
                // monitor keeps the event pending and retries on the next poll.
                resetNotificationError = error.localizedDescription
            }
            manualResetSuppressionUntil = resetMonitor.manualResetSuppressionUntil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAutomaticRefresh() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func stopAutomaticRefresh() {
        refreshLoop?.cancel()
        refreshLoop = nil
    }

    var isManualResetSuppressionActive: Bool {
        guard let manualResetSuppressionUntil else { return false }
        return manualResetSuppressionUntil > Date()
    }

    func markNextResetAsUserInitiated() {
        resetMonitor.markNextResetAsUserInitiated()
        manualResetSuppressionUntil = resetMonitor.manualResetSuppressionUntil
    }
}
