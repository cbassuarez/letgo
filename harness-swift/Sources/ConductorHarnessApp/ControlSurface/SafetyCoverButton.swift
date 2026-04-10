import SwiftUI

/// A flip-up safety cover that protects an `IlluminatedButton` underneath.
///
/// Two-step interaction:
/// - When `isCoverOpen == false`, the cover is shown and tapping it calls
///   `onLift()`. The host (view model) is responsible for opening the cover
///   and starting a 3s auto-close timer.
/// - When `isCoverOpen == true`, the cover slides up out of the way and
///   reveals the underlying critical button. Tapping the button calls
///   `onCommit()`. Tapping the lifted cover calls `onCancel()`.
struct SafetyCoverButton: View {
    let label: String
    let armedSubtitle: String
    let liftedSubtitle: String
    let isCoverOpen: Bool
    var canCommit: Bool = true
    var blinkOn: Bool = false
    let onLift: () -> Void
    let onCancel: () -> Void
    let onCommit: () -> Void

    private let buttonSize = CGSize(width: 130, height: 70)

    var body: some View {
        ZStack(alignment: .top) {
            // The button underneath
            IlluminatedButton(
                label: label,
                subtitle: isCoverOpen ? liftedSubtitle : "PROTECTED",
                color: ConsoleTheme.lampRed,
                isLit: isCoverOpen,
                isEnabled: isCoverOpen && canCommit,
                style: .critical,
                blinkOn: blinkOn,
                pulseWhenLit: true,
                minWidth: buttonSize.width,
                minHeight: buttonSize.height,
                action: onCommit
            )

            // The cover, hinged from the top
            cover
                .frame(width: buttonSize.width + 8, height: buttonSize.height + 8)
                .rotation3DEffect(
                    .degrees(isCoverOpen ? -110 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .top,
                    perspective: 0.6
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isCoverOpen)
                .onTapGesture {
                    if isCoverOpen {
                        onCancel()
                    } else {
                        onLift()
                    }
                }
        }
        .frame(width: buttonSize.width + 8, height: buttonSize.height + 12)
    }

    private var cover: some View {
        ZStack {
            // Striped cover plate
            HazardStripes()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.85), lineWidth: 1.4)
                )

            VStack(spacing: 4) {
                Text(label.uppercased())
                    .font(ConsoleTheme.panelTitleFont(size: 14))
                    .tracking(2.0)
                    .foregroundStyle(Color.black)
                Text("LIFT COVER")
                    .font(ConsoleTheme.smallTagFont(size: 8))
                    .tracking(1.4)
                    .foregroundStyle(Color.black.opacity(0.75))
            }
            .padding(6)
            .background(ConsoleTheme.warningStripeYellow.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Hinge highlights at the top edge
            VStack {
                HStack(spacing: 12) {
                    Hinge()
                    Spacer()
                    Hinge()
                }
                .padding(.top, 2)
                .padding(.horizontal, 8)
                Spacer()
            }
        }
    }
}

private struct HazardStripes: View {
    var body: some View {
        GeometryReader { geo in
            let stripeWidth: CGFloat = 14
            let count = Int((geo.size.width + geo.size.height) / stripeWidth) + 4
            ZStack {
                ConsoleTheme.warningStripeYellow
                ForEach(0..<count, id: \.self) { idx in
                    Rectangle()
                        .fill(ConsoleTheme.warningStripeBlack)
                        .frame(width: stripeWidth / 2, height: geo.size.height * 2)
                        .offset(x: CGFloat(idx) * stripeWidth - geo.size.height)
                        .rotationEffect(.degrees(45), anchor: .topLeading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

private struct Hinge: View {
    var body: some View {
        Circle()
            .fill(Color.black.opacity(0.7))
            .frame(width: 5, height: 5)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            )
    }
}
