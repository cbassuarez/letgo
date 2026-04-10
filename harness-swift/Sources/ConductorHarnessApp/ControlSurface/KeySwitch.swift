import SwiftUI

/// A two-position key switch (SAFE / ARM). Tapping the key rotates it 90°
/// and toggles the bound state.
struct KeySwitch: View {
    let isArmed: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("MASTER ARM")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.55))

            Button(action: onToggle) {
                ZStack {
                    // Bezel ring
                    Circle()
                        .fill(Color.black.opacity(0.85))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                        )

                    // Recessed dial
                    Circle()
                        .fill(ConsoleTheme.panelInnerFill)
                        .frame(width: 54, height: 54)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.6), lineWidth: 1)
                        )

                    // SAFE / ARM tick labels
                    Text("SAFE")
                        .font(ConsoleTheme.smallTagFont(size: 8))
                        .foregroundStyle(isArmed ? Color.white.opacity(0.35) : ConsoleTheme.lampGreen)
                        .offset(x: -22, y: 0)
                    Text("ARM")
                        .font(ConsoleTheme.smallTagFont(size: 8))
                        .foregroundStyle(isArmed ? ConsoleTheme.lampRed : Color.white.opacity(0.35))
                        .offset(x: 22, y: 0)

                    // The key body — rotates 90° between positions
                    keyShape
                        .frame(width: 36, height: 12)
                        .rotationEffect(.degrees(isArmed ? 90 : 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isArmed)
                }
                .frame(width: 70, height: 70)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Master arm key, currently \(isArmed ? "armed" : "safe")")

            Text(isArmed ? "ARMED" : "SAFE")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(isArmed ? ConsoleTheme.lampRed : ConsoleTheme.lampGreen)
        }
    }

    private var keyShape: some View {
        ZStack(alignment: .leading) {
            // Bow (the round head of the key)
            Circle()
                .fill(LinearGradient(
                    colors: [Color(white: 0.85), Color(white: 0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
                )
                .overlay(
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 3, height: 3)
                )
            // Shaft + bitting
            HStack(spacing: 0) {
                Spacer().frame(width: 10)
                RoundedRectangle(cornerRadius: 1)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.78), Color(white: 0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 24, height: 5)
                    .overlay(
                        HStack(spacing: 1.5) {
                            Rectangle().fill(Color.black.opacity(0.6)).frame(width: 1.2, height: 2)
                            Rectangle().fill(Color.black.opacity(0.6)).frame(width: 1.2, height: 3)
                            Rectangle().fill(Color.black.opacity(0.6)).frame(width: 1.2, height: 2)
                        }
                        .offset(y: 2.5),
                        alignment: .bottomTrailing
                    )
            }
        }
    }
}
