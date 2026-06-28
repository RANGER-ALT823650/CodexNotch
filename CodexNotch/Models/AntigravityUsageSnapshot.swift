import Foundation

struct AntigravityQuotaBucket: Identifiable, Equatable, Sendable {
    let id: String
    let groupTitle: String
    let title: String
    let remainingFraction: Double?
    let resetsAt: Date?
    let resetDescription: String?
    let disabled: Bool

    var remainingPercent: Double? {
        remainingFraction.map { min(max($0 * 100, 0), 100) }
    }

    var usedPercent: Double? {
        remainingPercent.map { 100 - $0 }
    }

    var usageKnown: Bool {
        !disabled && remainingFraction != nil
    }
}

struct AntigravityQuotaGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let buckets: [AntigravityQuotaBucket]
}

struct AntigravityUsageSnapshot: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case app = "Antigravity"
        case cli = "agy"
    }

    let groups: [AntigravityQuotaGroup]
    let fetchedAt: Date
    let source: Source

    var buckets: [AntigravityQuotaBucket] {
        groups.flatMap(\.buckets)
    }

    var mostRecentlyUsedGroup: AntigravityQuotaGroup? {
        groups.max(by: { a, b in
            let a5h = a.buckets.first(where: { $0.title == "5 小时" })
            let b5h = b.buckets.first(where: { $0.title == "5 小时" })
            
            let a5hActive = a5h.map { $0.usageKnown && ($0.remainingFraction ?? 1.0) < 1.0 } ?? false
            let b5hActive = b5h.map { $0.usageKnown && ($0.remainingFraction ?? 1.0) < 1.0 } ?? false
            
            switch (a5hActive, b5hActive) {
            case (true, false):
                return false
            case (false, true):
                return true
            case (true, true):
                if let aReset = a5h?.resetsAt, let bReset = b5h?.resetsAt {
                    return aReset < bReset
                }
                return false
            case (false, false):
                let aWeekly = a.buckets.first(where: { $0.title == "一周" })
                let bWeekly = b.buckets.first(where: { $0.title == "一周" })
                
                let aWeeklyActive = aWeekly.map { $0.usageKnown && ($0.remainingFraction ?? 1.0) < 1.0 } ?? false
                let bWeeklyActive = bWeekly.map { $0.usageKnown && ($0.remainingFraction ?? 1.0) < 1.0 } ?? false
                
                switch (aWeeklyActive, bWeeklyActive) {
                case (true, false):
                    return false
                case (false, true):
                    return true
                case (true, true):
                    if let aReset = aWeekly?.resetsAt, let bReset = bWeekly?.resetsAt {
                        return aReset < bReset
                    }
                    return false
                case (false, false):
                    let aMinFraction = a.buckets.compactMap(\.remainingFraction).min() ?? 1.0
                    let bMinFraction = b.buckets.compactMap(\.remainingFraction).min() ?? 1.0
                    return aMinFraction > bMinFraction
                }
            }
        }) ?? groups.first
    }
}

