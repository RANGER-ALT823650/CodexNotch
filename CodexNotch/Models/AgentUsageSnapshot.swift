import Foundation

struct AgentUsageDay: Identifiable, Equatable, Sendable {
    let day: Date
    let dayKey: String
    let totalTokens: Int64
    let level: Int

    var id: String { dayKey }

    var totalTokensInMillions: String {
        String(
            format: "%.1fM",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(totalTokens) / 1_000_000
        )
    }
}

struct AgentUsageSnapshot: Equatable, Sendable {
    let days: [AgentUsageDay]
    let totalTokens: Int64
    let activeDays: Int
    let sources: [String]
    let fetchedAt: Date
}
