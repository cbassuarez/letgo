import SwiftUI

/// A bordered "module" of the launch console: a recessed inner well surrounded
/// by a chamfered bezel, screw decorations at each corner, and a label-tape
/// header that names the module.
struct ConsolePanel<Content: View>: View {
    let title: String
    let accent: Color
    let content: () -> Content

    init(
        _ title: String,
        accent: Color = ConsoleTheme.lampAmber,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Outer bezel
            RoundedRectangle(cornerRadius: ConsoleTheme.panelCornerRadius)
                .fill(ConsoleTheme.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: ConsoleTheme.panelCornerRadius)
                        .stroke(ConsoleTheme.panelStroke, lineWidth: ConsoleTheme.panelStrokeWidth)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ConsoleTheme.panelCornerRadius - 1)
                        .stroke(ConsoleTheme.panelHighlight, lineWidth: 0.5)
                        .padding(1)
                )

            // Inner well
            RoundedRectangle(cornerRadius: ConsoleTheme.panelCornerRadius - 2)
                .fill(ConsoleTheme.panelInnerFill)
                .padding(ConsoleTheme.bezelInset)
                .overlay(
                    RoundedRectangle(cornerRadius: ConsoleTheme.panelCornerRadius - 2)
                        .stroke(Color.black.opacity(0.6), lineWidth: 1)
                        .padding(ConsoleTheme.bezelInset)
                )

            // Content sits inside the well, padded so it doesn't kiss the bezel.
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.top, 26)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            // Label tape header
            HStack(spacing: 6) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(title.uppercased())
                    .font(ConsoleTheme.labelTapeFont(size: 9))
                    .tracking(1.4)
                    .foregroundStyle(ConsoleTheme.labelTapeInk)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ConsoleTheme.labelTape)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .padding(.leading, 14)
            .padding(.top, 8)

            // Screw decorations at each corner
            ScrewMark().offset(x: 8, y: 8)
            ScrewMark().offset(x: 8, y: 0).frame(maxWidth: .infinity, alignment: .topTrailing).padding(.top, 8).padding(.trailing, 8)
            ScrewMark().offset(x: 0, y: 0).frame(maxHeight: .infinity, alignment: .bottomLeading).padding(.bottom, 8).padding(.leading, 8)
            ScrewMark().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(8)
        }
    }
}

private struct ScrewMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 4, height: 0.7)
                .rotationEffect(.degrees(35))
        }
        .frame(width: 6, height: 6)
    }
}
