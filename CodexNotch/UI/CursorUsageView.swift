import SwiftUI

struct CursorUsageView: View {
    let store: CursorUsageStore
    var scale: CGFloat = 1.0

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                GeometryReader { proxy in
                    let horizontalPadding: CGFloat = 16 * scale
                    let spacing: CGFloat = 12 * scale
                    let totalWidth = max(proxy.size.width - (horizontalPadding * 2), 0)
                    let availableWidth = max(totalWidth - spacing, 0)
                    let rightWidth = availableWidth * 0.30

                    HStack(spacing: spacing) {
                        UsageProgressView(window: snapshot.grokWindow, scale: scale)
                            .frame(maxWidth: .infinity)

                        Divider()
                            .overlay(.white.opacity(0.12))

                        UsageProgressView(window: snapshot.otherWindow, scale: scale)
                            .frame(maxWidth: .infinity)

                        Divider()
                            .overlay(.white.opacity(0.12))

                        sideView(snapshot)
                            .frame(width: rightWidth)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            } else if store.isRefreshing {
                VStack(spacing: 10 * scale) {
                    ProgressView().controlSize(.small)
                    Text("正在读取 Cursor 用量…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "暂无 Cursor 数据",
                    systemImage: "cursorarrow.rays",
                    description: Text(store.errorMessage ?? "请打开 Cursor 并登录后手动刷新")
                )
            }
        }
    }

    private func sideView(_ snapshot: CursorUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.planName)
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.67, blue: 1))
                    .lineLimit(1)
                Spacer(minLength: 4 * scale)
                if let price = snapshot.priceLabel {
                    Text(price)
                        .font(.system(size: 9 * scale, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            amountRow("已含", value: includedText(snapshot))
            amountRow("按需", value: onDemandText(snapshot))
            if snapshot.bonusSpendCents > 0 {
                amountRow("奖励", value: CursorUsageSnapshot.dollars(snapshot.bonusSpendCents))
            }
        }
        .padding(.vertical, 2 * scale)
    }

    private func amountRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9 * scale))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4 * scale)
            Text(value)
                .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func includedText(_ snapshot: CursorUsageSnapshot) -> String {
        let used = CursorUsageSnapshot.dollars(snapshot.includedSpendCents)
        guard snapshot.includedLimitCents > 0 else { return used }
        return "\(used)/\(CursorUsageSnapshot.dollars(snapshot.includedLimitCents))"
    }

    private func onDemandText(_ snapshot: CursorUsageSnapshot) -> String {
        let used = CursorUsageSnapshot.dollars(snapshot.onDemandSpendCents)
        guard let limit = snapshot.onDemandLimitCents, limit > 0 else { return used }
        return "\(used)/\(CursorUsageSnapshot.dollars(limit))"
    }
}
