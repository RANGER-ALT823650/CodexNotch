import SwiftUI

struct CursorUsageView: View {
    let store: CursorUsageStore
    var scale: CGFloat = 1.0

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HStack(spacing: 12 * scale) {
                    UsageProgressView(window: snapshot.grokWindow, scale: scale)
                        .frame(maxWidth: .infinity)

                    Divider()
                        .overlay(.white.opacity(0.12))

                    UsageProgressView(window: snapshot.otherWindow, scale: scale)
                        .frame(maxWidth: .infinity)

                    Divider()
                        .overlay(.white.opacity(0.12))

                    grokBotColumn(snapshot)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    @ViewBuilder
    private func grokBotColumn(_ snapshot: CursorUsageSnapshot) -> some View {
        if let window = snapshot.grokBotWindow {
            UsageProgressView(window: window, scale: scale)
        } else {
            VStack(spacing: 6 * scale) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Grok Bot")
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text("--")
                        .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                }
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: 8 * scale)
                HStack {
                    Text("剩余用量")
                    Spacer()
                    Text("每周重置")
                }
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Grok Bot 用量暂不可用")
        }
    }
}
