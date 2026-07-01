import SwiftUI

struct UsageCardView: View {
    typealias Provider = UsageProvider

    static let contentSize = CGSize(width: 440, height: 108)

    let codexStore: UsageStore
    let antigravityStore: AntigravityUsageStore
    let agentUsageStore: AgentUsageStore
    let safeAreaTop: CGFloat
    let onAgentDaySelected: (AgentUsageDay, NSPoint) -> Void
    let onAgentDetailDismiss: () -> Void
    let onCollapse: () -> Void
    private var provider: Provider { AppRuntime.shared.activeProvider }
    @State private var swipeDirection: HorizontalSwipeDirection = .left

    var body: some View {
        let headerHeight = max(safeAreaTop, 24.0)

        ZStack(alignment: .top) {
            // Content and footer occupying the main 150pt height
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Group {
                        switch provider {
                        case .codex:
                            codexContent
                        case .antigravity:
                            AntigravityUsageView(store: antigravityStore)
                        case .allAgents:
                            AgentUsageHeatmapView(
                                store: agentUsageStore,
                                onDaySelected: onAgentDaySelected
                            )
                        }
                    }
                    .id(provider)
                    .transition(providerTransition)
                }
                .frame(maxHeight: .infinity)

                if currentError != nil {
                    Spacer().frame(height: 2)
                    footer
                }
            }
            //.padding(.horizontal, 12)
            //.padding(.top, 6)
            //.padding(.bottom, 12)

            // Header elements shifted UP into the notch area (left and right of the notch)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: providerIcon)
                        .foregroundStyle(providerColor)
                    Text(providerTitle)
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                HStack(spacing: 12) {
                    Text(updateText)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 4)

                    Button {
                        refresh(provider)
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
            .padding(.horizontal, 8)
            .frame(height: headerHeight)
            .offset(y: -headerHeight)
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
        .accessibilityAction(named: "显示所有智能体 Token 用量") {
            select(.allAgents, direction: .left)
        }
        .onAppear {
            loadIfNeeded(provider)
        }
        .onChange(of: provider) { _, next in
            if next != .allAgents {
                onAgentDetailDismiss()
            }
        }
    }

    private var footer: some View {
        HStack {
            if currentError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(currentError ?? "")
            }
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
        switch provider {
        case .codex: codexStore.isRefreshing
        case .antigravity: antigravityStore.isRefreshing
        case .allAgents: agentUsageStore.isRefreshing
        }
    }

    private var currentError: String? {
        switch provider {
        case .codex: codexStore.errorMessage
        case .antigravity: antigravityStore.errorMessage
        case .allAgents: agentUsageStore.errorMessage
        }
    }

    private var currentUpdateDate: Date? {
        switch provider {
        case .codex: codexStore.snapshot?.fetchedAt
        case .antigravity: antigravityStore.snapshot?.fetchedAt
        case .allAgents: agentUsageStore.snapshot?.fetchedAt
        }
    }

    private var providerIcon: String {
        switch provider {
        case .codex: "terminal.fill"
        case .antigravity: "sparkles"
        case .allAgents: "square.grid.3x3.square.fill"
        }
    }

    private var providerColor: Color {
        switch provider {
        case .codex: .green
        case .antigravity: .mint
        case .allAgents: Color(red: 0.34, green: 0.82, blue: 0.43)
        }
    }

    private var providerTitle: String {
        switch provider {
        case .codex: "Codex 用量"
        case .antigravity: "Antigravity 用量"
        case .allAgents: "所有智能体 Token"
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
        let next = Self.provider(after: provider, direction: direction)
        select(next, direction: direction)
    }

    nonisolated static func provider(
        after current: Provider,
        direction: HorizontalSwipeDirection
    ) -> Provider {
        let providers = Provider.allCases
        guard let index = providers.firstIndex(of: current) else { return .codex }
        let delta = direction == .left ? 1 : -1
        let nextIndex = (index + delta + providers.count) % providers.count
        return providers[nextIndex]
    }

    private func select(_ next: Provider, direction: HorizontalSwipeDirection) {
        guard next != provider else { return }
        swipeDirection = direction
        withAnimation(.snappy(duration: 0.28)) {
            AppRuntime.shared.activeProvider = next
        }
        loadIfNeeded(next)
    }

    private func loadIfNeeded(_ target: Provider) {
        // The all-agent collector starts an external process and parses a year of
        // usage data. Reusing its snapshot keeps that work out of notch animations;
        // the refresh button remains the explicit way to force a fresh collection.
        if target == .allAgents, agentUsageStore.snapshot != nil {
            return
        }
        refresh(target)
    }

    private func refresh(_ target: Provider) {
        Task {
            switch target {
            case .codex: await codexStore.refresh()
            case .antigravity: await antigravityStore.refresh()
            case .allAgents: await agentUsageStore.refresh()
            }
        }
    }
}
