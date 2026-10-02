import Foundation

struct CursorUsageSnapshot: Equatable, Sendable {
    let planName: String
    let priceLabel: String?
    let email: String?
    let includedSpendCents: Int
    let includedLimitCents: Int
    let bonusSpendCents: Int
    let totalPercentUsed: Double
    let autoPercentUsed: Double
    let apiPercentUsed: Double
    let onDemandSpendCents: Int
    let onDemandLimitCents: Int?
    let billingCycleEnd: Date?
    let fetchedAt: Date

    /// Cursor 设置里的 Cursor Models 池：Grok 与 Composer。
    var grokWindow: UsageWindow {
        UsageWindow(
            usedPercent: min(max(autoPercentUsed, 0), 100),
            durationMinutes: nil,
            resetsAt: billingCycleEnd,
            label: "Grok"
        )
    }

    /// Cursor 设置里的 Other Models 池：第三方模型。
    var otherWindow: UsageWindow {
        UsageWindow(
            usedPercent: min(max(apiPercentUsed, 0), 100),
            durationMinutes: nil,
            resetsAt: billingCycleEnd,
            label: "其他"
        )
    }

    var planUsedPercent: Double {
        if includedLimitCents > 0 {
            let ratio = Double(includedSpendCents) / Double(includedLimitCents) * 100
            return min(max(ratio, 0), 100)
        }
        return min(max(totalPercentUsed, 0), 100)
    }

    static func dollars(_ cents: Int) -> String {
        if cents % 100 == 0 {
            return "$\(cents / 100)"
        }
        return String(format: "$%.2f", Double(cents) / 100)
    }
}
