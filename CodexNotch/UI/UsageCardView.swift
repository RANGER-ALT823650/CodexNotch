import SwiftUI

struct UsageCardView: View {
    typealias Provider = UsageProvider

    static let contentSize = CGSize(width: 440, height: 150)

    let codexStore: UsageStore
    let antigravityStore: AntigravityUsageStore
    let onCollapse: () -> Void
    private var provider: Provider { AppRuntime.shared.activeProvider }
    @State private var swipeDirection: HorizontalSwipeDirection = .left

    var body: some View {
        VStack(spacing: 7) {
            header

            ZStack {
                Group {
                    switch provider {
                    case .codex:
                        codexContent
                    case .antigravity:
                        AntigravityUsageView(store: antigravityStore)
                    }
                }
                .id(provider)
                .transition(providerTransition)
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .foregroundStyle(.white)
        .background {
            HorizontalSwipeDetector(onSwipe: switchProvider)
        }
        .accessibilityAction(named: "显示 Codex 用量") {
            select(.codex, direction: .right)
        }
        .accessibilityAction(named: "显示 Antigravity 用量") {
            select(.antigravity, direction: .left)
        }
        .onAppear {
            Task {
                await codexStore.refresh()
            }
            Task {
                await antigravityStore.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: provider == .codex ? "terminal.fill" : "sparkles")
                .foregroundStyle(provider == .codex ? .green : .mint)
            Text(provider == .codex ? "Codex 用量" : "Antigravity 用量")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            providerIndicator
            Spacer()
            Button {
                Task {
                    switch provider {
                    case .codex: await codexStore.refresh()
                    case .antigravity: await antigravityStore.refresh()
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(isRefreshing ? .degrees(360) : .zero)
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .help("刷新")

            Button(action: onCollapse) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .help("收起")
        }
    }

    private var footer: some View {
        HStack {
            if currentError != nil, currentUpdateDate != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(currentError ?? "")
            }
            Text(updateText)
            Spacer()
            if provider == .antigravity, let source = antigravityStore.snapshot?.source.rawValue {
                Text("来源：\(source)")
            }
            Text("双指左右滑切换 · 点击外部收起")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }

    private var updateText: String {
        guard let date = currentUpdateDate else { return currentError ?? "未更新" }
        return "更新于 \(date.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private var codexContent: some View {
        if let snapshot = codexStore.snapshot {
            HStack(spacing: 20) {
                UsageProgressView(window: snapshot.primary)
                Divider().overlay(.white.opacity(0.12))
                UsageProgressView(window: snapshot.secondary)
            }
        } else if codexStore.isRefreshing {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在读取 Codex 用量…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "暂无用量数据",
                systemImage: "gauge.with.dots.needle.0percent",
                description: Text(codexStore.errorMessage ?? "请手动刷新")
            )
        }
    }

    private var isRefreshing: Bool {
        provider == .codex ? codexStore.isRefreshing : antigravityStore.isRefreshing
    }

    private var currentError: String? {
        provider == .codex ? codexStore.errorMessage : antigravityStore.errorMessage
    }

    private var currentUpdateDate: Date? {
        switch provider {
        case .codex: codexStore.snapshot?.fetchedAt
        case .antigravity: antigravityStore.snapshot?.fetchedAt
        }
    }

    private var providerIndicator: some View {
        HStack(spacing: 5) {
            ForEach(Provider.allCases) { item in
                Capsule()
                    .fill(item == provider ? .white : .white.opacity(0.22))
                    .frame(width: item == provider ? 14 : 5, height: 5)
            }
        }
        .animation(.snappy(duration: 0.25), value: provider)
        .accessibilityHidden(true)
    }

    private var providerTransition: AnyTransition {
        let insertion: Edge = swipeDirection == .left ? .trailing : .leading
        let removal: Edge = swipeDirection == .left ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    private func switchProvider(_ direction: HorizontalSwipeDirection) {
        let next: Provider = direction == .left ? .antigravity : .codex
        select(next, direction: direction)
    }

    private func select(_ next: Provider, direction: HorizontalSwipeDirection) {
        guard next != provider else { return }
        swipeDirection = direction
        withAnimation(.snappy(duration: 0.28)) {
            AppRuntime.shared.activeProvider = next
        }
    }
}
