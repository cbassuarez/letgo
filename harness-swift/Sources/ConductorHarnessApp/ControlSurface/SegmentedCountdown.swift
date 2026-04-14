import SwiftUI

/// Seven-segment style T-minus countdown tuned for low-latency updates.
/// Displays a single digit (whole seconds only).
struct SegmentedCountdown: View {
    let seconds: Double?
    let expiresAt: Date?
    let isArmed: Bool
    let summary: String

    var body: some View {
        Group {
            if isArmed, expiresAt != nil {
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    countdownContent(seconds: secondsAt(timeline.date))
                }
            } else {
                countdownContent(seconds: secondsAt(Date()))
            }
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
                Text("8")
                    .font(ConsoleTheme.segmentFont(size: 64))
                    .foregroundStyle(ConsoleTheme.segmentOff)

                Text(displayValue)
                    .font(ConsoleTheme.segmentFont(size: 64))
                    .foregroundStyle(displayColor)
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
            return "-"
        }
        let clamped = max(0, seconds)
        let wholeSeconds = Int(ceil(clamped))
        let digit = max(0, min(9, wholeSeconds))
        return String(digit)
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
