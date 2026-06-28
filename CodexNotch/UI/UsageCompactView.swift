import SwiftUI

struct UsageCompactView: View {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind
    let onTap: () -> Void

    private var activeProvider: UsageProvider {
        AppRuntime.shared.activeProvider
    }

    private var codexStore: UsageStore {
        AppRuntime.shared.usageStore
    }

    private var antigravityStore: AntigravityUsageStore {
        AppRuntime.shared.antigravityStore
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if isRefreshing, remainingPercent == nil {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }

                Text(title)
                    .font(.system(size: 10, weight: .medium))

                Text(percentText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)剩余\(percentText)，点击展开")
    }

    private var isRefreshing: Bool {
        switch activeProvider {
        case .codex: codexStore.isRefreshing
        case .antigravity: antigravityStore.isRefreshing
        }
    }

    private var percentText: String {
        remainingPercent.map { "\(Int($0.rounded()))%" } ?? "--"
    }

    private var title: String {
        kind == .primary ? "5h" : "7d"
    }

    private var remainingPercent: Double? {
        switch activeProvider {
        case .codex:
            switch kind {
            case .primary:
                return codexStore.snapshot?.primary.remainingPercent
            case .secondary:
                return codexStore.snapshot?.secondary.remainingPercent
            }
        case .antigravity:
            guard let group = antigravityStore.snapshot?.mostRecentlyUsedGroup else { return nil }
            switch kind {
            case .primary:
                return group.buckets.first(where: { $0.title == "5 小时" })?.remainingPercent
            case .secondary:
                return group.buckets.first(where: { $0.title == "一周" })?.remainingPercent
            }
        }
    }

    private var tint: Color {
        guard let remainingPercent else { return .gray }
        return switch remainingPercent {
        case 50...:
            .green
        case 20..<50:
            .orange
        default:
            .red
        }
    }
}
