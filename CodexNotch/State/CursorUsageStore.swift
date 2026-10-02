import Foundation
import Observation

@MainActor
@Observable
final class CursorUsageStore {
    private let provider: any CursorUsageProviding
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var recentModelLoop: Task<Void, Never>?

    private(set) var snapshot: CursorUsageSnapshot?
    private(set) var recentChatModel: String?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    init(provider: any CursorUsageProviding = CursorUsageProvider()) {
        self.provider = provider
    }

    /// 缩略图左侧显示的额度池，跟随 Cursor 最近一个对话的模型。
    var recentModelWindow: UsageWindow? {
        snapshot?.recentModelWindow(modelName: recentChatModel)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshRecentChatModel()
        do {
            snapshot = try await provider.fetchUsage()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshRecentChatModel() async {
        if let model = await provider.fetchRecentChatModel() {
            recentChatModel = model
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
        // 切换模型只需读本机数据库，比请求用量接口便宜得多，所以单独高频轮询。
        recentModelLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                await self.refreshRecentChatModel()
            }
        }
    }

    func stopAutomaticRefresh() {
        refreshLoop?.cancel()
        refreshLoop = nil
        recentModelLoop?.cancel()
        recentModelLoop = nil
    }
}
