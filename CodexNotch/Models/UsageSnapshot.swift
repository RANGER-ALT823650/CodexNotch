import Foundation

struct UsageWindow: Equatable, Sendable {
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }

    var remainingFraction: Double {
        remainingPercent / 100
    }

    var title: String {
        switch durationMinutes {
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
    let primary: UsageWindow
    let secondary: UsageWindow
    let fetchedAt: Date
}

