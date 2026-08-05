import AppKit
import SwiftUI

struct AgentUsageHeatmapView: View {
    let store: AgentUsageStore
    var scale: CGFloat = 1.0
    let onDaySelected: (AgentUsageDay, NSPoint) -> Void

    var body: some View {
        Group {
            if let snapshot = store.snapshot, snapshot.totalTokens > 0 {
                AgentUsageHeatmap(snapshot: snapshot, scale: scale, onDaySelected: onDaySelected)
            } else if store.isRefreshing {
                VStack(spacing: 8 * scale) {
                    ProgressView().controlSize(.small)
                    Text("正在汇总本机智能体 Token…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "暂无智能体记录",
                    systemImage: "square.grid.3x3.square",
                    description: Text(store.errorMessage ?? "请点击刷新运行 TokenTracker 采集")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentUsageHeatmap: View {
    private struct Layout {
        let cellSize: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
        let labelWidth: CGFloat
        let labelGap: CGFloat
        let monthHeight: CGFloat
        let monthGap: CGFloat
        let cellOrigin: CGPoint
        let columnStride: CGFloat
        let rowStride: CGFloat

        init(scale: CGFloat) {
            cellSize = 7 * scale
            columnSpacing = 0.8 * scale
            rowSpacing = 2.6 * scale
            labelWidth = 16 * scale
            labelGap = 3 * scale
            monthHeight = 10 * scale
            monthGap = 4 * scale
            cellOrigin = CGPoint(
                x: labelWidth + labelGap,
                y: monthHeight + monthGap
            )
            columnStride = cellSize + columnSpacing
            rowStride = cellSize + rowSpacing
        }
    }

    private let weeks: [HeatmapWeek]
    private let activeDays: Int
    private let scale: CGFloat
    private let layout: Layout
    private let onDaySelected: (AgentUsageDay, NSPoint) -> Void
    @State private var hoveredDay: AgentUsageDay?

    init(
        snapshot: AgentUsageSnapshot,
        scale: CGFloat = 1.0,
        calendar: Calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            return cal
        }(),
        onDaySelected: @escaping (AgentUsageDay, NSPoint) -> Void
    ) {
        weeks = HeatmapWeek.makeWeeks(days: snapshot.days, calendar: calendar)
        activeDays = snapshot.activeDays
        self.scale = scale
        self.layout = Layout(scale: scale)
        self.onDaySelected = onDaySelected
    }

    private var canvasSize: CGSize {
        let columnCount = CGFloat(weeks.count)
        return CGSize(
            width: layout.cellOrigin.x
                + columnCount * layout.cellSize
                + max(0, columnCount - 1) * layout.columnSpacing,
            height: layout.cellOrigin.y
                + 7 * layout.cellSize
                + 6 * layout.rowSpacing
        )
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, _ in
            drawMonthLabels(in: &context)
            drawWeekdayLabels(in: &context)
            drawCells(in: &context)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                hoveredDay = day(at: location)
            case .ended:
                hoveredDay = nil
            }
        }
        .gesture(
            SpatialTapGesture().onEnded { value in
                guard let selectedDay = day(at: value.location) else { return }
                onDaySelected(selectedDay, NSEvent.mouseLocation)
            }
        )
        .help(hoverHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("过去 365 天的智能体 Token 用量热力图")
        .accessibilityValue(accessibilitySummary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drawMonthLabels(in context: inout GraphicsContext) {
        for (column, week) in weeks.enumerated() where week.monthLabel.isEmpty == false {
            let label = Text(week.monthLabel)
                .font(.system(size: 8.5 * scale))
                .foregroundStyle(.secondary)
            context.draw(
                label,
                at: CGPoint(
                    x: layout.cellOrigin.x + CGFloat(column) * layout.columnStride,
                    y: 0
                ),
                anchor: .topLeading
            )
        }
    }

    private func drawWeekdayLabels(in context: inout GraphicsContext) {
        let labels = ["日", "一", "", "三", "", "五", ""]
        for (row, value) in labels.enumerated() where value.isEmpty == false {
            let label = Text(value)
                .font(.system(size: 8.5 * scale))
                .foregroundStyle(.secondary)
            context.draw(
                label,
                at: CGPoint(
                    x: layout.labelWidth,
                    y: layout.cellOrigin.y
                        + CGFloat(row) * layout.rowStride
                        + layout.cellSize / 2
                ),
                anchor: .trailing
            )
        }
    }

    private func drawCells(in context: inout GraphicsContext) {
        for (column, week) in weeks.enumerated() {
            for (row, day) in week.days.enumerated() {
                let origin = CGPoint(
                    x: layout.cellOrigin.x + CGFloat(column) * layout.columnStride,
                    y: layout.cellOrigin.y + CGFloat(row) * layout.rowStride
                )
                let rect = CGRect(origin: origin, size: CGSize(width: layout.cellSize, height: layout.cellSize))
                let path = Path(roundedRect: rect, cornerRadius: 1.5 * scale)
                context.fill(path, with: .color(color(for: day?.level ?? 0)))
            }
        }
    }

    private func day(at location: CGPoint) -> AgentUsageDay? {
        let relativeX = location.x - layout.cellOrigin.x
        let relativeY = location.y - layout.cellOrigin.y
        guard relativeX >= 0, relativeY >= 0 else { return nil }

        let column = Int(relativeX / layout.columnStride)
        let row = Int(relativeY / layout.rowStride)
        guard weeks.indices.contains(column), weeks[column].days.indices.contains(row) else { return nil }

        // Do not treat the spacing between cells as part of a cell's hover target.
        guard relativeX.truncatingRemainder(dividingBy: layout.columnStride) <= layout.cellSize,
              relativeY.truncatingRemainder(dividingBy: layout.rowStride) <= layout.cellSize
        else { return nil }
        return weeks[column].days[row]
    }

    private var hoverHelp: String {
        guard let hoveredDay else { return "将指针移到格子上查看每日 Token 用量" }
        return "\(hoveredDay.day.formatted(date: .abbreviated, time: .omitted)) · \(hoveredDay.totalTokens.formatted()) tokens"
    }

    private var accessibilitySummary: String {
        return "过去一年共有 \(activeDays) 个活跃日"
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 99: Color.red
        case 1: Color(red: 0.04, green: 0.22, blue: 0.10)
        case 2: Color(red: 0.00, green: 0.43, blue: 0.18)
        case 3: Color(red: 0.20, green: 0.72, blue: 0.25)
        case 4: Color(red: 0.70, green: 1.00, blue: 0.38)
        default: Color.white.opacity(0.075)
        }
    }
}

@MainActor
final class AgentUsageDayDetailPanelController {
    static let panelSize = CGSize(width: 176, height: 64)

    private var panel: NSPanel?

    func show(day: AgentUsageDay, topLeft: NSPoint) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: AgentUsageDayDetailView(day: day))
        panel.setFrame(
            NSRect(
                x: topLeft.x,
                y: topLeft.y - Self.panelSize.height,
                width: Self.panelSize.width,
                height: Self.panelSize.height
            ),
            display: true
        )
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return panel
    }
}

private struct AgentUsageDayDetailView: View {
    let day: AgentUsageDay

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.day.formatted(.dateTime.year().month().day()))
                .font(.system(size: 12, weight: .semibold))
            Text("总 Token 用量：\(day.totalTokensInMillions)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
        }
    }
}

private struct HeatmapWeek {
    let days: [AgentUsageDay?]
    let monthLabel: String

    static func makeWeeks(days: [AgentUsageDay], calendar: Calendar) -> [HeatmapWeek] {
        guard let first = days.first else { return [] }
        let leadingEmptyDays = max(0, calendar.component(.weekday, from: first.day) - 1)
        var slots = Array<AgentUsageDay?>(repeating: nil, count: leadingEmptyDays)
        slots.append(contentsOf: days.map(Optional.some))
        while slots.count.isMultiple(of: 7) == false {
            slots.append(nil)
        }

        var previousMonth: Int?
        return stride(from: 0, to: slots.count, by: 7).map { start in
            let weekDays = Array(slots[start..<min(start + 7, slots.count)])
            let firstDate = weekDays.compactMap { $0?.day }.first
            let month = firstDate.map { calendar.component(.month, from: $0) }
            let label: String
            if let month, month != previousMonth {
                label = String(month)
            } else {
                label = ""
            }
            if month != nil { previousMonth = month }
            return HeatmapWeek(days: weekDays, monthLabel: label)
        }
    }
}
