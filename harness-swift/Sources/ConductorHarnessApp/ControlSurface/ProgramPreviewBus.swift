import SwiftUI

/// A row in a PROGRAM/PREVIEW bus. The id is the underlying primitive
/// (e.g. an output mode raw value or a lane id).
struct BusRow: Identifiable, Equatable {
    let id: String
    let label: String
    let subtitle: String?
    let canSelect: Bool

    init(id: String, label: String, subtitle: String? = nil, canSelect: Bool = true) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.canSelect = canSelect
    }
}

/// Broadcast-switcher style PROGRAM/PREVIEW dual-bank with a TAKE button
/// between them. Reused for both the output mode bus and the lane bus.
///
/// - PROGRAM (left) is read-only and shows the currently committed selection.
/// - PREVIEW (right) is interactive: tapping a row calls `onPreviewSelect`
///   (which arms the latch).
/// - TAKE commits PREVIEW → PROGRAM via `onTake`.
struct ProgramPreviewBus: View {
    let title: String
    let rows: [BusRow]
    let programId: String?
    let previewId: String?
    let canTake: Bool
    let blinkOn: Bool
    let onPreviewSelect: (String) -> Void
    let onTake: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(ConsoleTheme.smallTagFont(size: 9))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Text("BUS")
                    .font(ConsoleTheme.smallTagFont(size: 8))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            HStack(alignment: .top, spacing: 12) {
                bank(
                    header: "PROGRAM",
                    selectedId: programId,
                    selectionColor: ConsoleTheme.lampRed,
                    interactive: false
                )

                takeColumn

                bank(
                    header: "PREVIEW",
                    selectedId: previewId,
                    selectionColor: ConsoleTheme.lampAmber,
                    interactive: true
                )
            }
        }
    }

    // MARK: Banks

    private func bank(
        header: String,
        selectedId: String?,
        selectionColor: Color,
        interactive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.6)
                .foregroundStyle(selectionColor)

            VStack(spacing: 4) {
                ForEach(rows) { row in
                    busRowView(
                        row: row,
                        isSelected: row.id == selectedId,
                        selectionColor: selectionColor,
                        interactive: interactive
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func busRowView(
        row: BusRow,
        isSelected: Bool,
        selectionColor: Color,
        interactive: Bool
    ) -> some View {
        let pulse = interactive && isSelected
        return Button {
            guard interactive, row.canSelect else { return }
            onPreviewSelect(row.id)
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isSelected ? selectionColor : Color.white.opacity(0.08))
                    .frame(width: 4)
                    .opacity(pulse ? (blinkOn ? 1.0 : 0.55) : 1.0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.label.uppercased())
                        .font(ConsoleTheme.panelTitleFont(size: 11))
                        .tracking(1.0)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                    if let subtitle = row.subtitle {
                        Text(subtitle.uppercased())
                            .font(ConsoleTheme.smallTagFont(size: 8))
                            .tracking(0.8)
                            .foregroundStyle(Color.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Circle()
                        .fill(selectionColor)
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? (blinkOn ? 1.0 : 0.4) : 1.0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? selectionColor.opacity(0.18) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? selectionColor.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .disabled(!interactive || !row.canSelect)
        .opacity(row.canSelect || isSelected ? 1.0 : 0.4)
    }

    // MARK: Take column

    private var takeColumn: some View {
        VStack(spacing: 6) {
            Text("TAKE")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.55))

            IlluminatedButton(
                label: "TAKE",
                color: ConsoleTheme.lampGreen,
                isLit: canTake,
                isEnabled: canTake,
                blinkOn: blinkOn,
                pulseWhenLit: true,
                minWidth: 70,
                minHeight: 90,
                action: onTake
            )
        }
        .frame(width: 90)
    }
}
