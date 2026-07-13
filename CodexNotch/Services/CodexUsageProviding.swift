import Foundation

protocol CodexUsageProviding: Sendable {
    func fetchUsage() async throws -> UsageSnapshot
}

enum CodexUsageError: LocalizedError, Equatable {
    case codexNotInstalled
    case processStartFailed(String)
    case requestFailed(String)
    case malformedResponse(String)
    case missingRateLimits
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .codexNotInstalled:
            "未找到 Codex CLI，请先安装并登录 Codex。"
        case let .processStartFailed(message):
            "Codex 进程启动失败：\(message)"
        case let .requestFailed(message):
            "Codex 用量请求失败：\(message)"
        case let .malformedResponse(message):
            "Codex 返回了无效数据：\(message)"
        case .missingRateLimits:
            "Codex 没有返回每周限额数据。"
        case let .timeout(method):
            "Codex 请求超时：\(method)"
        }
    }
}

