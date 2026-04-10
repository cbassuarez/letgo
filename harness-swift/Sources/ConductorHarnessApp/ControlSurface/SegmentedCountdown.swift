import SwiftUI

/// Seven-segment style T-minus countdown.
///
/// - When `seconds` is nil, displays `T - - - . -` in the disarmed color.
/// - White > 3.0s, amber 1.0–3.0s, red < 1.0s.
/// - Pulse rate doubles below 3s and doubles again below 1s, driven by the
///   shared blink timer (no extra timers introduced).
struct SegmentedCountdown: View {
    let seconds: Double?
    let isArmed: Bool
    let blinkOn: Bool
    let summary: String

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("T-MINUS")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(2.4)
                .foregroundStyle(Color.white.opacity(0.45))

            ZStack {
                // Faint ghost segments
                Text("8 8 . 8")
                    .font(ConsoleTheme.segmentFont(size: 72))
                    .foregroundStyle(ConsoleTheme.segmentOff)
                    .tracking(4)

                Text(displayString)
                    .font(ConsoleTheme.segmentFont(size: 72))
                    .foregroundStyle(activeColor)
                    .tracking(4)
                    .shadow(color: activeColor.opacity(0.7), radius: shouldGlow ? 8 : 0)
                    .opacity(displayOpacity)
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
                .foregroundStyle(summaryColor)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Display logic

    private var displayString: String {
        guard let seconds, isArmed else {
            return "- - . -"
        }
        let clamped = max(0, seconds)
        return String(format: "%04.1f", clamped)
            .map { String($0) }
            .joined(separator: " ")
    }

    private var activeColor: Color {
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

    private var summaryColor: Color {
        guard isArmed else { return Color.white.opacity(0.35) }
        guard let seconds else { return ConsoleTheme.lampAmber }
        if seconds < 1.0 { return ConsoleTheme.lampRed }
        if seconds < 3.0 { return ConsoleTheme.lampAmber }
        return ConsoleTheme.lampGreen
    }

    private var shouldGlow: Bool {
        isArmed && seconds != nil
    }

    /// Pulse rate escalates as the countdown approaches zero. The blinkOn
    /// parameter ticks at 0.45s; we sample it at faster effective rates by
    /// gating on the fractional part of `seconds` for the inner thresholds.
    private var displayOpacity: Double {
        guard isArmed, let seconds else { return 1.0 }
        if seconds < 1.0 {
            // Fast pulse — twice per second.
            let phase = (seconds * 2).truncatingRemainder(dividingBy: 1.0)
            return phase > 0.5 ? 1.0 : 0.35
        }
        if seconds < 3.0 {
            return blinkOn ? 1.0 : 0.55
        }
        return 1.0
    }
}
