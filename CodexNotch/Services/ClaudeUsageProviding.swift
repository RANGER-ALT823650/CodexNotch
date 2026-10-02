import Foundation

protocol ClaudeUsageProviding: Sendable {
    func fetchUsage() async throws -> ClaudeUsageSnapshot
}

enum ClaudeUsageError: LocalizedError, Equatable {
    case tokenNotFound
    case unauthenticated(String)
    case requestFailed(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .tokenNotFound:
            "未检测到 Claude 登录凭证，请启动 Claude Desktop 或在终端运行 claude"
        case let .unauthenticated(message):
            "Claude 认证已失效，请重新登录：\(message)"
        case let .requestFailed(message):
            "Claude 接口请求失败：\(message)"
        case let .parseFailed(message):
            "无法解析 Claude 配额：\(message)"
        }
    }
}
