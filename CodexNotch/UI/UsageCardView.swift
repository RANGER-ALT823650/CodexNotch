import SwiftUI

struct UsageCardView: View {
    typealias Provider = UsageProvider

    static let referenceSize = CGSize(width: 440, height: 108)
    static var contentSize: CGSize { referenceSize }

    static func contentSize(for screen: NSScreen?) -> CGSize {
        guard let screen else { return referenceSize }
        let w = round(screen.frame.width * 0.28)
        let h = round(screen.frame.height * 0.11)
        return CGSize(width: w, height: h)
    }

    let codexStore: UsageStore
    let claudeStore: ClaudeUsageStore
    let cursorStore: CursorUsageStore
    let antigravityStore: AntigravityUsageStore
    let agentUsageStore: AgentUsageStore
    let safeAreaTop: CGFloat
    let cardSize: CGSize
    let onAgentDaySelected: (AgentUsageDay, NSPoint) -> Void
    let onAgentDetailDismiss: () -> Void
    let onCollapse: () -> Void
    private var provider: Provider { AppRuntime.shared.activeProvider }
    @State private var swipeDirection: HorizontalSwipeDirection = .left

    private var scale: CGFloat {
        cardSize.width / Self.referenceSize.width
    }

    init(
        codexStore: UsageStore,
        claudeStore: ClaudeUsageStore,
        cursorStore: CursorUsageStore,
        antigravityStore: AntigravityUsageStore,
        agentUsageStore: AgentUsageStore,
        safeAreaTop: CGFloat,
        cardSize: CGSize = Self.referenceSize,
        onAgentDaySelected: @escaping (AgentUsageDay, NSPoint) -> Void,
        onAgentDetailDismiss: @escaping () -> Void,
        onCollapse: @escaping () -> Void
    ) {
        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.cursorStore = cursorStore
        self.antigravityStore = antigravityStore
        self.agentUsageStore = agentUsageStore
        self.safeAreaTop = safeAreaTop
        self.cardSize = cardSize
        self.onAgentDaySelected = onAgentDaySelected
        self.onAgentDetailDismiss = onAgentDetailDismiss
        self.onCollapse = onCollapse
    }

    var body: some View {
        let headerHeight = max(safeAreaTop, 24.0 * scale)

        ZStack(alignment: .top) {
            // Content and footer occupying the main 150pt height
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Group {
                        switch provider {
                        case .codex:
                            codexContent
                        case .claude:
                            ClaudeUsageView(store: claudeStore, scale: scale)
                        case .cursor:
                            CursorUsageView(store: cursorStore, scale: scale)
                        case .antigravity:
                            AntigravityUsageView(store: antigravityStore, scale: scale)
                        case .allAgents:
                            AgentUsageHeatmapView(
                                store: agentUsageStore,
                                scale: scale,
                                onDaySelected: onAgentDaySelected
                            )
                        }
                    }
                    .id(provider)
                    .transition(providerTransition)
                }
                .frame(maxHeight: .infinity)

                if currentError != nil {
                    Spacer().frame(height: 2 * scale)
                    footer
                }
            }
            //.padding(.horizontal, 12)
            //.padding(.top, 6)
            //.padding(.bottom, 12)

            // Header elements shifted UP into the notch area (left and right of the notch)
            HStack(spacing: 8 * scale) {
                HStack(spacing: 6 * scale) {
                    Image(systemName: providerIcon)
                        .foregroundStyle(providerColor)
                    Text(providerTitle)
                        .font(.system(size: 13 * scale, weight: .semibold))
                }

                Spacer()

                HStack(spacing: 12 * scale) {
                    Text(updateText)
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 4 * scale)

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
            .padding(.horizontal, 8 * scale)
            .frame(height: headerHeight)
            .offset(y: -headerHeight)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .foregroundStyle(.white)
        .background {
            HorizontalSwipeDetector(onSwipe: switchProvider)
        }
        .accessibilityAction(named: "显示 Codex 用量") {
            select(.codex, direction: .right)
        }
        .accessibilityAction(named: "显示 Claude Code 用量") {
            select(.claude, direction: .left)
        }
        .accessibilityAction(named: "显示 Cursor 用量") {
            select(.cursor, direction: .left)
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
        .font(.system(size: 10 * scale))
        .foregroundStyle(.tertiary)
    }

    private var updateText: String {
        guard let date = currentUpdateDate else { return currentError ?? "未更新" }
        return "更新于 \(date.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private var codexContent: some View {
        if let snapshot = codexStore.snapshot {
            GeometryReader { proxy in
                let horizontalPadding: CGFloat = 16 * scale
                let spacing: CGFloat = 12 * scale
                let totalWidth = max(proxy.size.width - (horizontalPadding * 2), 0)
                let hasCredits = snapshot.credits != nil
                let availableWidth = max(totalWidth - (hasCredits ? spacing : 0), 0)
                let rightWidth = availableWidth * (hasCredits ? 0.28 : 0.0)

                HStack(spacing: spacing) {
                    if let primary = snapshot.primary {
                        UsageProgressView(window: primary, scale: scale)
                            .frame(maxWidth: .infinity)

                        Divider()
                            .overlay(.white.opacity(0.12))
                    }

                    UsageProgressView(window: snapshot.secondary, scale: scale)
                        .frame(maxWidth: .infinity)

                    if let credits = snapshot.credits {
                        Divider()
                            .overlay(.white.opacity(0.12))

                        UsageCreditsView(credits: credits, scale: scale)
                            .frame(width: rightWidth)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        } else if codexStore.isRefreshing {
            VStack(spacing: 10 * scale) {
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
        case .claude: claudeStore.isRefreshing
        case .cursor: cursorStore.isRefreshing
        case .antigravity: antigravityStore.isRefreshing
        case .allAgents: agentUsageStore.isRefreshing
        }
    }

    private var currentError: String? {
        switch provider {
        case .codex: codexStore.errorMessage
        case .claude: claudeStore.errorMessage
        case .cursor: cursorStore.errorMessage
        case .antigravity: antigravityStore.errorMessage
        case .allAgents: agentUsageStore.errorMessage
        }
    }

    private var currentUpdateDate: Date? {
        switch provider {
        case .codex: codexStore.snapshot?.fetchedAt
        case .claude: claudeStore.snapshot?.fetchedAt
        case .cursor: cursorStore.snapshot?.fetchedAt
        case .antigravity: antigravityStore.snapshot?.fetchedAt
        case .allAgents: agentUsageStore.snapshot?.fetchedAt
        }
    }

    private var providerIcon: String {
        switch provider {
        case .codex: "terminal.fill"
        case .claude: "asterisk"
        case .cursor: "cursorarrow.rays"
        case .antigravity: "sparkles"
        case .allAgents: "square.grid.3x3.square.fill"
        }
    }

    private var providerColor: Color {
        switch provider {
        case .codex: .green
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .cursor: Color(red: 0.45, green: 0.67, blue: 1)
        case .antigravity: .mint
        case .allAgents: Color(red: 0.34, green: 0.82, blue: 0.43)
        }
    }

    private var providerTitle: String {
        switch provider {
        case .codex: "Codex 用量"
        case .claude: "Claude Code 用量"
        case .cursor: "Cursor 用量"
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
            case .claude: await claudeStore.refresh()
            case .cursor: await cursorStore.refresh()
            case .antigravity: await antigravityStore.refresh()
            case .allAgents: await agentUsageStore.refresh()
            }
        }
    }
}
