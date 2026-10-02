import Foundation

struct ClaudeBreakdownItem: Identifiable, Equatable, Sendable {
    var id: String { key }
    let key: String
    let displayName: String
    let percent: Int
}

struct ClaudeUsageSnapshot: Equatable, Sendable {
    let primary: UsageWindow?
    let secondary: UsageWindow
    let breakdown: [ClaudeBreakdownItem]
    let accountEmail: String?
    let billingType: String?
    let fetchedAt: Date

    init(
        primary: UsageWindow?,
        secondary: UsageWindow,
        breakdown: [ClaudeBreakdownItem] = [],
        accountEmail: String? = nil,
        billingType: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.primary = primary
        self.secondary = secondary
        self.breakdown = breakdown
        self.accountEmail = accountEmail
        self.billingType = billingType
        self.fetchedAt = fetchedAt
    }
}
