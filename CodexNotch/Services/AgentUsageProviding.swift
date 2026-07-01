import Foundation

protocol AgentUsageProviding: Sendable {
    func fetchUsage() async throws -> AgentUsageSnapshot
}

enum AgentUsageError: LocalizedError, Equatable {
    case collectorNotFound
    case collectorFailed(String)
    case queueNotFound(String)
    case unreadableQueue(String)

    var errorDescription: String? {
        switch self {
        case .collectorNotFound:
            "未找到 TokenTracker 或 npx。请安装 Node.js 20+，或通过 TOKENTRACKER_PATH 指定采集器。"
        case let .collectorFailed(message):
            "TokenTracker 采集失败：\(message)"
        case let .queueNotFound(path):
            "TokenTracker 未生成用量数据：\(path)"
        case let .unreadableQueue(message):
            "无法读取 TokenTracker 数据：\(message)"
        }
    }
}
