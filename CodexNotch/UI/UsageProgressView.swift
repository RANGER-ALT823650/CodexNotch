import SwiftUI

struct UsageProgressView: View {
    let window: UsageWindow

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
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
            .frame(height: 8)

            HStack {
                Text("剩余用量")
                Spacer()
                Text(resetDescription)
            }
            .font(.system(size: 10, weight: .medium))
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
        guard let resetsAt = window.resetsAt else { return "重置时间未知" }
        return "\(resetsAt.formatted(.relative(presentation: .named)))重置"
    }
}
