import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private let provider: any CodexUsageProviding
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?

    private(set) var snapshot: UsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    init(provider: any CodexUsageProviding) {
        self.provider = provider
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            snapshot = try await provider.fetchUsage()
            errorMessage = nil
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
}
