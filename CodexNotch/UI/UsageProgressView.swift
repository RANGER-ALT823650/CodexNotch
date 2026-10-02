import SwiftUI

struct UsageProgressView: View {
    let window: UsageWindow
    var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 6 * scale) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * window.remainingFraction)
                }
            }
            .frame(height: 8 * scale)

            HStack {
                Text("剩余用量")
                Spacer()
                Text(resetDescription)
            }
            .font(.system(size: 10 * scale, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.title)剩余 \(Int(window.remainingPercent.rounded())) 百分比")
    }

    private var tint: Color {
        switch window.remainingPercent {
        case 50...:
            .green
        case 20..<50:
            .orange
        default:
            .red
        }
    }

    private var resetDescription: String {
        if let resetsAt = window.resetsAt {
            return "\(resetsAt.formatted(.relative(presentation: .named)))重置"
        }
        if window.durationMinutes == 10_080 {
            return "每周重置"
        }
        return "重置时间未知"
    }
}
