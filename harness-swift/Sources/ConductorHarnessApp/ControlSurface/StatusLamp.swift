import SwiftUI

enum LampState {
    case off
    case standby
    case nominal
    case caution
    case fault
}

/// Circular indicator LED with an optional label below or beside it.
struct StatusLamp: View {
    let label: String
    let state: LampState
    var pulse: Bool = false
    var blinkOn: Bool = false
    var diameter: CGFloat = ConsoleTheme.lampDiameter
    var labelPlacement: Placement = .below

    enum Placement {
        case below
        case trailing
        case none
    }

    var body: some View {
        let layout: AnyLayout = labelPlacement == .trailing
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 5))

        layout {
            lens
            if labelPlacement != .none {
                Text(label.uppercased())
                    .font(ConsoleTheme.smallTagFont(size: 9))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var color: Color {
        switch state {
        case .off: return ConsoleTheme.lampOff
        case .standby: return ConsoleTheme.lampStandby
        case .nominal: return ConsoleTheme.lampGreen
        case .caution: return ConsoleTheme.lampAmber
        case .fault: return ConsoleTheme.lampRed
        }
    }

    private var isLit: Bool {
        state != .off && state != .standby
    }

    private var litOpacity: Double {
        guard pulse, isLit else { return 1.0 }
        return blinkOn ? 1.0 : 0.45
    }

    private var lens: some View {
        ZStack {
            // Bezel ring
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: diameter + 4, height: diameter + 4)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.7)
                )
            // Lens body
            Circle()
                .fill(color.opacity(isLit ? 1.0 : 0.65))
                .frame(width: diameter, height: diameter)
                .opacity(litOpacity)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.5), lineWidth: 0.6)
                )
            // Glow halo
            if isLit {
                Circle()
                    .fill(color)
                    .frame(width: diameter + 6, height: diameter + 6)
                    .blur(radius: 4)
                    .opacity(0.45 * litOpacity)
            }
            // Specular highlight
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: diameter * 0.35, height: diameter * 0.18)
                .offset(y: -diameter * 0.22)
                .blur(radius: 0.6)
        }
    }
}
