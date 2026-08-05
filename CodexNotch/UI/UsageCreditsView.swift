import SwiftUI

struct UsageCreditsView: View {
    let credits: Double
    var scale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .trailing, spacing: 2 * scale) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("Credits")
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(formattedCredits)
                    .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("剩余 Credits")
                    .font(.system(size: 10 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 6 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余 Credits \(formattedCredits)")
    }

    private var formattedCredits: String {
        String(format: "%.2f", credits)
    }
}
