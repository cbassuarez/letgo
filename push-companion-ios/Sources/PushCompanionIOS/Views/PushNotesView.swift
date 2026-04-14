import SwiftUI

struct PushNotesView: View {
    @ObservedObject var model: PushDeckViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var notesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Performance Notes")
                        .font(DeckThemeTokens.monoFont(size: 20, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.96))
                    Text("Authoritative local cue log with live state snapshot.")
                        .font(DeckThemeTokens.monoFont(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .blendMode(.overlay)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .font(DeckThemeTokens.monoFont(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Rectangle().fill(Color.white.opacity(0.08)))
                .buttonStyle(.plain)
            }

            stateSnapshotStrip

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CueTemplate.allCases, id: \.self) { template in
                        Button(template.label) {
                            appendTemplate(template)
                        }
                        .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Rectangle().fill(template.tint.opacity(0.22))
                        )
                        .overlay(
                            Rectangle().stroke(template.tint.opacity(0.8), lineWidth: 1)
                        )
                        .buttonStyle(.plain)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.notesText)
                    .font(DeckThemeTokens.monoFont(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($notesFocused)
                    .padding(8)

                if model.notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Type operator notes, callouts, safety cues, and fallback paths...")
                        .font(DeckThemeTokens.monoFont(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                }
            }
            .frame(minHeight: 260)
            .background(Color.black.opacity(0.5))
            .overlay(
                Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            HStack(spacing: 10) {
                Text("WORDS \(wordCount)")
                    .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
                Text("LINES \(lineCount)")
                    .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                Spacer()
                Text("LOCAL AUTO-SAVE")
                    .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                    .foregroundStyle(DeckThemeTokens.accentApply)
                    .blendMode(.overlay)
            }
            .padding(.horizontal, 2)
        }
        .padding(18)
        .background(
            DeckThemeTokens.stageGradient
                .overlay(Color.black.opacity(model.settingsState.prefersHighContrast ? 0.06 : 0.2))
        )
        .onAppear {
            notesFocused = true
        }
    }

    private var stateSnapshotStrip: some View {
        HStack(spacing: 6) {
            snapshotChip(
                title: "LINK",
                value: model.socketClient.linkState.rawValue.uppercased(),
                tint: model.socketClient.linkState == .online ? DeckThemeTokens.accentApply : DeckThemeTokens.accentWarn
            )
            snapshotChip(title: "ENGINE", value: model.engineReadout, tint: engineTint)
            snapshotChip(title: "TIMING", value: model.timingMode.rawValue.uppercased(), tint: DeckThemeTokens.accentMain)
            snapshotChip(title: "BANKS", value: "M\(model.mainBank)/C\(model.choirBank)", tint: DeckThemeTokens.accentMain)
        }
    }

    private func snapshotChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(DeckThemeTokens.monoFont(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.64))
            Text(value)
                .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .blendMode(.overlay)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Rectangle().fill(tint.opacity(0.16)))
        .overlay(Rectangle().stroke(tint.opacity(0.72), lineWidth: 1))
    }

    private var engineTint: Color {
        if model.engineReadout.hasPrefix("DYNAMIC") {
            return DeckThemeTokens.accentApply
        }
        if model.engineReadout.hasPrefix("OFF") {
            return DeckThemeTokens.accentWarn
        }
        return DeckThemeTokens.accentMain
    }

    private func appendTemplate(_ template: CueTemplate) {
        let prefix = Self.timeFormatter.string(from: .now)
        let block = "\n[\(prefix)] \(template.label)\n- intent:\n- cues:\n- fallback:\n"
        if model.notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.notesText = "[\(prefix)] \(template.label)\n- intent:\n- cues:\n- fallback:\n"
        } else {
            model.notesText += block
        }
    }

    private var wordCount: Int {
        model.notesText.split(whereSeparator: \.isWhitespace).count
    }

    private var lineCount: Int {
        model.notesText.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private enum CueTemplate: CaseIterable {
        case preshow
        case intro
        case dynamic
        case ending
        case safety

        var label: String {
            switch self {
            case .preshow:
                return "PRESHOW"
            case .intro:
                return "INTRO"
            case .dynamic:
                return "DYNAMIC"
            case .ending:
                return "ENDING"
            case .safety:
                return "SAFETY"
            }
        }

        var tint: Color {
            switch self {
            case .preshow, .intro:
                return DeckThemeTokens.accentMain
            case .dynamic:
                return DeckThemeTokens.accentApply
            case .ending:
                return DeckThemeTokens.accentWarn
            case .safety:
                return DeckThemeTokens.accentError
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
