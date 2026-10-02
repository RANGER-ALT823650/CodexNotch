import SwiftUI

struct ClaudeUsageView: View {
    let store: ClaudeUsageStore
    var scale: CGFloat = 1.0

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                GeometryReader { proxy in
                    let horizontalPadding: CGFloat = 16 * scale
                    let spacing: CGFloat = 12 * scale
                    let totalWidth = max(proxy.size.width - (horizontalPadding * 2), 0)
                    let showSideInfo = !snapshot.breakdown.isEmpty || snapshot.accountEmail != nil
                    let availableWidth = max(totalWidth - (showSideInfo ? spacing : 0), 0)
                    let rightWidth = availableWidth * (showSideInfo ? 0.28 : 0.0)

                    HStack(spacing: spacing) {
                        if let primary = snapshot.primary {
                            UsageProgressView(window: primary, scale: scale)
                                .frame(maxWidth: .infinity)

                            Divider()
                                .overlay(.white.opacity(0.12))
                        }

                        UsageProgressView(window: snapshot.secondary, scale: scale)
                            .frame(maxWidth: .infinity)

                        if showSideInfo {
                            Divider()
                                .overlay(.white.opacity(0.12))

                            claudeSideView(snapshot: snapshot)
                                .frame(width: rightWidth)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            } else if store.isRefreshing {
                VStack(spacing: 10 * scale) {
                    ProgressView().controlSize(.small)
                    Text("正在读取 Claude 用量…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "暂无 Claude 数据",
                    systemImage: "asterisk",
                    description: Text(store.errorMessage ?? "请启动 Claude 或登录后手动刷新")
                )
            }
        }
    }

    private func claudeSideView(snapshot: ClaudeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(alignment: .firstTextBaseline) {
                Text(subscriptionTitle(snapshot))
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                Spacer()
                Text("$20/月")
                    .font(.system(size: 9 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if !snapshot.breakdown.isEmpty {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    ForEach(snapshot.breakdown.prefix(2)) { item in
                        HStack {
                            Text(item.displayName)
                                .font(.system(size: 9 * scale))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.percent)%")
                                .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .monospacedDigit()
                        }
                    }
                }
            } else if let email = snapshot.accountEmail {
                Text(email)
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2 * scale)
    }

    private func subscriptionTitle(_ snapshot: ClaudeUsageSnapshot) -> String {
        if snapshot.billingType == "apple_subscription" {
            return "Apple 订阅"
        }
        return "Pro 订阅"
    }
}
