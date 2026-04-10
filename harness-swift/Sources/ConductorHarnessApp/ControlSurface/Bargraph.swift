import SwiftUI

/// Vertical LED-segment bar showing a 0…1 value with a label, used for the
/// dynamic vector readouts. Tap-and-drag in the bar to set a new value.
struct Bargraph: View {
    let label: String
    let value: Double
    let onChange: (Double) -> Void

    private let segmentCount = 14
    private let barHeight: CGFloat = 110
    private let barWidth: CGFloat = 18

    var body: some View {
        VStack(spacing: 6) {
            // Numeric readout
            Text(String(format: "%.2f", value))
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.65))

            // Bar
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: barWidth, height: barHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                    )

                VStack(spacing: 1) {
                    ForEach((0..<segmentCount).reversed(), id: \.self) { idx in
                        let threshold = Double(idx + 1) / Double(segmentCount)
                        let lit = value >= threshold - (1.0 / Double(segmentCount * 2))
                        Rectangle()
                            .fill(lit ? segmentColor(for: idx) : Color.white.opacity(0.04))
                            .frame(width: barWidth - 6, height: (barHeight - 16) / CGFloat(segmentCount) - 1)
                            .shadow(
                                color: lit ? segmentColor(for: idx).opacity(0.7) : .clear,
                                radius: lit ? 1.5 : 0
                            )
                    }
                }
                .padding(.vertical, 7)
            }
            .frame(width: barWidth, height: barHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let normalized = 1.0 - Double(gesture.location.y / barHeight)
                        let clamped = max(0, min(1, normalized))
                        onChange(clamped)
                    }
            )

            // Label
            Text(label.uppercased())
                .font(ConsoleTheme.smallTagFont(size: 8))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
                .frame(width: 44)
        }
        .accessibilityLabel("\(label) \(Int(value * 100)) percent")
    }

    private func segmentColor(for idx: Int) -> Color {
        // Top-of-bar segments transition green → amber → red.
        let topThird = segmentCount * 2 / 3
        let upperThird = segmentCount * 5 / 6
        if idx >= upperThird { return ConsoleTheme.lampRed }
        if idx >= topThird { return ConsoleTheme.lampAmber }
        return ConsoleTheme.lampGreen
    }
}
