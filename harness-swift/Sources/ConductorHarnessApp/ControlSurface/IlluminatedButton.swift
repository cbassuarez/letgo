import SwiftUI

/// Recessed rectangular button with a colored lens, bezel, and engraved labels.
/// The lens "lights up" when `isLit` is true.
struct IlluminatedButton: View {
    enum Style {
        case normal
        case critical
    }

    let label: String
    var subtitle: String? = nil
    let color: Color
    var isLit: Bool = false
    var isEnabled: Bool = true
    var style: Style = .normal
    var blinkOn: Bool = false
    var pulseWhenLit: Bool = false
    var minWidth: CGFloat = 110
    var minHeight: CGFloat = 56
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: triggerIfEnabled) {
            ZStack {
                // Bezel
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                    )

                // Lens
                RoundedRectangle(cornerRadius: 6)
                    .fill(lensFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(lensStroke, lineWidth: 1)
                    )
                    .padding(4)
                    .shadow(
                        color: isLit ? color.opacity(0.6) : .clear,
                        radius: isLit ? 6 : 0
                    )

                // Engraved label
                VStack(spacing: 2) {
                    Text(label.uppercased())
                        .font(ConsoleTheme.panelTitleFont(size: 14))
                        .tracking(2.0)
                        .foregroundStyle(textColor)
                    if let subtitle {
                        Text(subtitle.uppercased())
                            .font(ConsoleTheme.smallTagFont(size: 8))
                            .tracking(1.4)
                            .foregroundStyle(textColor.opacity(0.7))
                    }
                }
                .padding(6)
            }
            .frame(minWidth: minWidth, minHeight: minHeight)
            .scaleEffect(isPressed && isEnabled ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .opacity(litOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private func triggerIfEnabled() {
        guard isEnabled else { return }
        action()
    }

    private var lensFill: Color {
        if !isEnabled {
            return ConsoleTheme.lampOff
        }
        if isLit {
            return color.opacity(0.92)
        }
        // Dim "ready but not lit" — show the color faintly so the button
        // still reads as e.g. green/red even when not actively armed.
        return color.opacity(0.18)
    }

    private var lensStroke: Color {
        if !isEnabled {
            return Color.white.opacity(0.05)
        }
        return isLit ? Color.white.opacity(0.45) : Color.white.opacity(0.12)
    }

    private var textColor: Color {
        if !isEnabled {
            return Color.white.opacity(0.25)
        }
        if isLit {
            // Black text on a bright lens reads like an engraved cap.
            return style == .critical ? Color.white : Color.black
        }
        return Color.white.opacity(0.65)
    }

    private var litOpacity: Double {
        guard isLit, pulseWhenLit else { return 1.0 }
        return blinkOn ? 1.0 : 0.7
    }
}
