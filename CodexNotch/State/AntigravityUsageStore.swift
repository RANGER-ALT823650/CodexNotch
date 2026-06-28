import Foundation
import Observation

@MainActor
@Observable
final class AntigravityUsageStore {
    private let provider: any AntigravityUsageProviding
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?

    private(set) var snapshot: AntigravityUsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    init(provider: any AntigravityUsageProviding) {
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

    func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
        Task { await provider.shutdown() }
    }
}

