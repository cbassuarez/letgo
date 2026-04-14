import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PushSettingsSheetView: View {
    @ObservedObject var model: PushDeckViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copiedControllerID = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deck Settings")
                            .font(DeckThemeTokens.monoFont(size: 20, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.97))
                        Text("Connectivity, diagnostics, and performance controls")
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

                sectionCard(title: "CONNECTION") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backend Host")
                            .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.75))

                        TextField("Backend Host", text: $model.settingsState.hostDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(DeckThemeTokens.monoFont(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.36))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))

                        HStack(spacing: 8) {
                            settingsAction("Apply", tint: DeckThemeTokens.accentMain) {
                                model.applyHostDraft()
                            }
                            settingsAction("Reconnect", tint: DeckThemeTokens.accentApply) {
                                model.reconnect()
                            }
                            settingsAction("Disconnect", tint: DeckThemeTokens.accentWarn) {
                                model.disconnect()
                            }
                            settingsAction("Default Host", tint: DeckThemeTokens.textMuted) {
                                model.settingsState.hostDraft = PushSessionStore.defaultBackendHost
                            }
                        }
                    }
                }

                sectionCard(title: "SYSTEM STATUS") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            statusChip("LINK", value: model.socketClient.linkState.rawValue.uppercased(), tint: linkTint)
                            statusChip("ENGINE", value: model.engineReadout, tint: engineTint)
                            statusChip("TIMING", value: model.timingMode.rawValue.uppercased(), tint: DeckThemeTokens.accentMain)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("WS ENDPOINT")
                                .font(DeckThemeTokens.monoFont(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.62))
                            Text(model.sessionStore.websocketURL?.absoluteString ?? "Unavailable")
                                .font(DeckThemeTokens.monoFont(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.9))
                                .textSelection(.enabled)
                        }

                        Text("STATUS: \(model.socketClient.statusLine)")
                            .font(DeckThemeTokens.monoFont(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                }

                sectionCard(title: "CONTROLLER IDENTITY") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.sessionStore.controllerID)
                            .font(DeckThemeTokens.monoFont(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.34))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))

                        HStack(spacing: 8) {
                            settingsAction(copiedControllerID ? "Copied" : "Copy ID", tint: DeckThemeTokens.accentMain) {
                                copyControllerID()
                            }
                            settingsAction("Reconnect", tint: DeckThemeTokens.accentApply) {
                                model.reconnect()
                            }
                        }
                    }
                }

                sectionCard(title: "PERFORMANCE PREFERENCES") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Handedness")
                            .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.75))

                        Picker("Handedness", selection: Binding(
                            get: { model.settingsState.mirrorHandedness },
                            set: { model.setHandedness($0) }
                        )) {
                            ForEach(DeckHandedness.allCases) { hand in
                                Text(hand.rawValue.uppercased()).tag(hand)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle(isOn: Binding(
                            get: { model.settingsState.prefersHighContrast },
                            set: { _ in model.toggleHighContrast() }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Adaptive High Contrast")
                                    .font(DeckThemeTokens.monoFont(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.95))
                                Text("Boosts legibility while keeping stage bloom controlled")
                                    .font(DeckThemeTokens.monoFont(size: 10, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.76))
                                    .blendMode(.overlay)
                            }
                        }
                        .tint(DeckThemeTokens.accentApply)
                    }
                }

                sectionCard(title: "ML ASSIST") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phone Pad Echo Probability")
                            .font(DeckThemeTokens.monoFont(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.94))
                        Text("Chance that a regular iPad pad hit is mirrored to one phone output. Does not affect HOTAS or phone choir.")
                            .font(DeckThemeTokens.monoFont(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.76))
                            .blendMode(.overlay)

                        HStack(spacing: 10) {
                            Slider(
                                value: Binding(
                                    get: { model.phonePadEchoProbability },
                                    set: { model.setPhonePadEchoProbability($0) }
                                ),
                                in: 0...0.2
                            )
                            .tint(DeckThemeTokens.accentApply)

                            Text("\(Int((model.phonePadEchoProbability / 0.2) * 20))%")
                                .font(DeckThemeTokens.monoFont(size: 12, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.96))
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(
            DeckThemeTokens.stageGradient
                .overlay(Color.black.opacity(model.settingsState.prefersHighContrast ? 0.06 : 0.2))
        )
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.68))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.34))
        .overlay(Rectangle().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func settingsAction(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.94))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Rectangle().fill(tint.opacity(0.22)))
            .overlay(Rectangle().stroke(tint.opacity(0.8), lineWidth: 1))
            .buttonStyle(.plain)
    }

    private func statusChip(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DeckThemeTokens.monoFont(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.65))
            Text(value)
                .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .blendMode(.overlay)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Rectangle().fill(tint.opacity(0.16)))
        .overlay(Rectangle().stroke(tint.opacity(0.74), lineWidth: 1))
    }

    private var linkTint: Color {
        model.socketClient.linkState == .online ? DeckThemeTokens.accentApply : DeckThemeTokens.accentWarn
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

    private func copyControllerID() {
        #if canImport(UIKit)
        UIPasteboard.general.string = model.sessionStore.controllerID
        #endif
        copiedControllerID = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copiedControllerID = false
        }
    }
}
