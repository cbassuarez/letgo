import SwiftUI

struct PushQuantizeModal: View {
    let currentMs: Int
    let onChangeMs: (Int) -> Void
    let onClose: () -> Void

    @State private var localMs: Int = 140
    private let range = 20...500

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quant Timing Control")
                        .font(DeckThemeTokens.monoFont(size: 20, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.97))
                    Text("Authoritative timing interval for quantized trigger dispatch.")
                        .font(DeckThemeTokens.monoFont(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .blendMode(.overlay)
                }
                Spacer()
                Button("Close") {
                    onClose()
                }
                .font(DeckThemeTokens.monoFont(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Rectangle().fill(Color.white.opacity(0.08)))
                .buttonStyle(.plain)
            }

            sectionCard(title: "ACTIVE INTERVAL") {
                HStack(spacing: 8) {
                    Text("\(localMs)")
                        .font(DeckThemeTokens.monoFont(size: 34, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.97))
                        .blendMode(.overlay)
                    Text("ms")
                        .font(DeckThemeTokens.monoFont(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity, minHeight: 74)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.44), DeckThemeTokens.accentApply.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Rectangle().stroke(DeckThemeTokens.accentApply.opacity(0.72), lineWidth: 1)
                )
            }

            sectionCard(title: "FINE / COARSE NUDGE") {
                HStack(spacing: 8) {
                    stepButton("-10", delta: -10, tint: DeckThemeTokens.accentWarn)
                    stepButton("-1", delta: -1, tint: DeckThemeTokens.accentWarn)
                    Spacer(minLength: 0)
                    stepButton("+1", delta: 1, tint: DeckThemeTokens.accentApply)
                    stepButton("+10", delta: 10, tint: DeckThemeTokens.accentApply)
                }
            }

            sectionCard(title: "QUICK PRESETS") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach([50, 100, 140, 200, 300], id: \.self) { preset in
                        Button("\(preset)ms") {
                            apply(preset)
                        }
                        .font(DeckThemeTokens.monoFont(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            Rectangle().fill(
                                localMs == preset
                                ? DeckThemeTokens.accentApply.opacity(0.28)
                                : Color.white.opacity(0.08)
                            )
                        )
                        .overlay(
                            Rectangle().stroke(
                                (localMs == preset ? DeckThemeTokens.accentApply : Color.white.opacity(0.22)),
                                lineWidth: 1
                            )
                        )
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                metadataChip("RANGE", value: "\(range.lowerBound)-\(range.upperBound)ms")
                metadataChip("CURRENT", value: "\(localMs)ms")
                metadataChip("MODE", value: "QUANTIZED")
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            DeckThemeTokens.stageGradient
                .overlay(Color.black.opacity(0.16))
        )
        .onAppear {
            localMs = currentMs
        }
    }

    private func stepButton(_ title: String, delta: Int, tint: Color) -> some View {
        Button(title) {
            apply(localMs + delta)
        }
        .font(DeckThemeTokens.monoFont(size: 16, weight: .bold))
        .foregroundStyle(Color.white.opacity(0.95))
        .frame(minWidth: 84, minHeight: 48)
        .background(Rectangle().fill(tint.opacity(0.22)))
        .overlay(Rectangle().stroke(tint.opacity(0.8), lineWidth: 1))
        .buttonStyle(.plain)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.7))
            content()
        }
        .padding(12)
        .background(Color.black.opacity(0.34))
        .overlay(Rectangle().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func metadataChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DeckThemeTokens.monoFont(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.62))
            Text(value)
                .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .blendMode(.overlay)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Rectangle().fill(DeckThemeTokens.accentMain.opacity(0.14)))
        .overlay(Rectangle().stroke(DeckThemeTokens.accentMain.opacity(0.64), lineWidth: 1))
    }

    private func apply(_ value: Int) {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        localMs = clamped
        onChangeMs(clamped)
    }
}
