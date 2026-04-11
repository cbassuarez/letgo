import SwiftUI

/// Seven-segment style T-minus countdown tuned for low-latency updates.
struct SegmentedCountdown: View {
    let seconds: Double?
    let expiresAt: Date?
    let isArmed: Bool
    let summary: String

    var body: some View {
        if isArmed {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                countdownContent(seconds: secondsAt(context.date))
            }
        } else {
            countdownContent(seconds: nil)
        }
    }

    private func countdownContent(seconds: Double?) -> some View {
        let displayColor = activeColor(for: seconds)
        let displayValue = displayString(for: seconds)
        let summaryTone = summaryColor(for: seconds)

        return VStack(alignment: .center, spacing: 6) {
            Text("T-MINUS")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(2.4)
                .foregroundStyle(Color.white.opacity(0.45))

            ZStack {
                Text("88.8")
                    .font(ConsoleTheme.segmentFont(size: 64))
                    .foregroundStyle(ConsoleTheme.segmentOff)
                    .tracking(2)

                Text(displayValue)
                    .font(ConsoleTheme.segmentFont(size: 64))
                    .foregroundStyle(displayColor)
                    .tracking(2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
            )

            Text(summary.uppercased())
                .font(ConsoleTheme.smallTagFont(size: 10))
                .tracking(1.6)
                .foregroundStyle(summaryTone)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Display logic

    private func secondsAt(_ now: Date) -> Double? {
        guard isArmed else { return nil }
        if let expiresAt {
            return max(0, expiresAt.timeIntervalSince(now))
        }
        return seconds
    }

    private func displayString(for seconds: Double?) -> String {
        guard let seconds, isArmed else {
            return "--.-"
        }
        let clamped = max(0, seconds)
        let totalTenths = Int((clamped * 10).rounded(.toNearestOrEven))
        let whole = max(0, totalTenths / 10)
        let fractional = abs(totalTenths % 10)
        return String(format: "%02d.%01d", whole, fractional)
    }

    private func activeColor(for seconds: Double?) -> Color {
        guard let seconds, isArmed else {
            return ConsoleTheme.segmentOff.opacity(2.5) // ~ medium-grey
        }
        if seconds < 1.0 {
            return ConsoleTheme.segmentOnRed
        }
        if seconds < 3.0 {
            return ConsoleTheme.segmentOnAmber
        }
        return ConsoleTheme.segmentOn
    }

    private func summaryColor(for seconds: Double?) -> Color {
        guard isArmed else { return Color.white.opacity(0.35) }
        guard let seconds else { return ConsoleTheme.lampAmber }
        if seconds < 1.0 { return ConsoleTheme.lampRed }
        if seconds < 3.0 { return ConsoleTheme.lampAmber }
        return ConsoleTheme.lampGreen
    }

}
