import Foundation
import Observation

@MainActor
@Observable
final class AgentUsageStore {
    private let provider: any AgentUsageProviding

    private(set) var snapshot: AgentUsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    init(provider: any AgentUsageProviding) {
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
}
