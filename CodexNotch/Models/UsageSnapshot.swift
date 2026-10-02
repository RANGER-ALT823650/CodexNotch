import Foundation

struct UsageWindow: Equatable, Sendable {
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?
    let label: String?

    init(usedPercent: Double, durationMinutes: Int?, resetsAt: Date?, label: String? = nil) {
        self.usedPercent = usedPercent
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
        self.label = label
    }

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }

    var remainingFraction: Double {
        remainingPercent / 100
    }

    var title: String {
        if let label { return label }
        return switch durationMinutes {
        case 300:
            "5 小时"
        case 10_080:
            "一周"
        case let minutes?:
            "\(minutes) 分钟"
        case nil:
            "用量"
        }
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let primary: UsageWindow?
    let secondary: UsageWindow
    let credits: Double?
    let fetchedAt: Date

    init(
        primary: UsageWindow?,
        secondary: UsageWindow,
        credits: Double? = nil,
        fetchedAt: Date
    ) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.fetchedAt = fetchedAt
    }
}


