import Foundation

protocol CursorUsageProviding: Sendable {
    func fetchUsage() async throws -> CursorUsageSnapshot
}

struct CursorCredentials: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var email: String?
    var membershipType: String?
}

enum CursorUsageError: LocalizedError, Equatable {
    case tokenNotFound
    case unauthenticated(String)
    case requestFailed(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .tokenNotFound:
            "未检测到 Cursor 登录凭证，请先打开 Cursor 并登录"
        case let .unauthenticated(message):
            "Cursor 登录已失效，请在 Cursor 中重新登录：\(message)"
        case let .requestFailed(message):
            "Cursor 用量请求失败：\(message)"
        case let .parseFailed(message):
            "无法解析 Cursor 用量：\(message)"
        }
    }
}
