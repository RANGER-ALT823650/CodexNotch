import SwiftUI

struct AntigravityUsageView: View {
    let store: AntigravityUsageStore

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HStack(spacing: 12) {
                    ForEach(snapshot.groups) { group in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(group.buckets) { bucket in
                                    quota(bucket)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.isRefreshing {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取 Antigravity 用量…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "暂无 Antigravity 数据",
                    systemImage: "sparkles",
                    description: Text(store.errorMessage ?? "请启动 Antigravity 或登录 agy 后刷新")
                )
            }
        }
    }

    private func quota(_ bucket: AntigravityQuotaBucket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                Text(remainingText(bucket))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: bucket.remainingPercent ?? 0, total: 100)
                .tint(progressColor(bucket.remainingPercent))
                .opacity(bucket.usageKnown ? 1 : 0.35)
                .controlSize(.small)

            Text(resetText(bucket))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
    }

    private func remainingText(_ bucket: AntigravityQuotaBucket) -> String {
        guard bucket.usageKnown, let remaining = bucket.remainingPercent else { return "—" }
        return "\(Int(remaining.rounded()))%"
    }

    private func resetText(_ bucket: AntigravityQuotaBucket) -> String {
        if bucket.disabled { return "已停用" }
        if let date = bucket.resetsAt {
            return "重置 \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        }
        return bucket.resetDescription ?? "重置时间未知"
    }

    private func progressColor(_ remainingPercent: Double?) -> Color {
        switch remainingPercent ?? 100 {
        case ...15: .red
        case ...35: .orange
        default: .green
        }
    }
}
