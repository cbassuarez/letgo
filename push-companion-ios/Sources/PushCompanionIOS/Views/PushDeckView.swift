import SwiftUI

private enum DeckSheet: String, Identifiable {
    case settings
    case notes
    case quant

    var id: String { rawValue }
}

struct PushDeckView: View {
    @ObservedObject var model: PushDeckViewModel

    @State private var activeSheet: DeckSheet?
    @State private var hasConnectedOnce = false
    @State private var settingsSheetDetent: PresentationDetent = .large
    @State private var notesSheetDetent: PresentationDetent = .large
    @State private var quantSheetDetent: PresentationDetent = .large

    private let padColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    var body: some View {
        GeometryReader { proxy in
            let profile = DeckLayoutProfile.profile(for: proxy.size)
            ZStack {
                DeckThemeTokens.stageGradient
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(model.settingsState.prefersHighContrast ? 0.0 : 0.08))

                VStack(spacing: profile.verticalSpacing) {
                    topCommandRail(profile: profile)
                    HStack(spacing: profile.verticalSpacing) {
                        if model.handedness == .left {
                            sideRail(profile: profile)
                                .frame(width: actionRailWidth(for: profile))
                        }

                        padStage(profile: profile)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if model.handedness == .right {
                            sideRail(profile: profile)
                                .frame(width: actionRailWidth(for: profile))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(profile.outerPadding)

                if let flash = model.actionFlashEvent {
                    actionFlash(flash)
                        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                        .padding(.top, profile.outerPadding + 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                if let proposal = model.proposalCardState {
                    proposalCard(proposal)
                        .padding(profile.outerPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.86), value: model.actionFlashEvent?.id)
            .animation(.easeInOut(duration: 0.28), value: model.proposalCardState?.id)
            .onAppear {
                model.settingsState.hostDraft = model.sessionStore.backendHost
                guard !hasConnectedOnce else { return }
                hasConnectedOnce = true
                model.connect()
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            if model.notesPresentationState.isPresented {
                model.dismissNotes()
            }
        }) { sheet in
            switch sheet {
            case .settings:
                PushSettingsSheetView(model: model)
                    .presentationDetents([.medium, .large], selection: $settingsSheetDetent)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(0)
                    .onAppear {
                        settingsSheetDetent = .large
                    }
            case .notes:
                PushNotesView(model: model)
                    .presentationDetents([.medium, .large], selection: $notesSheetDetent)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(0)
                    .onAppear {
                        notesSheetDetent = .large
                    }
            case .quant:
                PushQuantizeModal(
                    currentMs: model.quantIntervalMs,
                    onChangeMs: { model.setQuantIntervalMs($0) },
                    onClose: { activeSheet = nil }
                )
                .presentationDetents([.medium, .large], selection: $quantSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(0)
                .onAppear {
                    quantSheetDetent = .large
                }
            }
        }
    }

    private func topCommandRail(profile: DeckLayoutProfile) -> some View {
        HStack(spacing: 8) {
            highlightToggleButton

            iconButton(
                systemName: model.handedness == .right ? "hand.point.right.fill" : "hand.point.left.fill",
                isProminent: false
            ) {
                model.toggleHandedness()
            }

            iconButton(systemName: "note.text", isProminent: false) {
                model.presentNotes()
                activeSheet = .notes
            }

            iconButton(systemName: "gearshape.fill", isProminent: true) {
                activeSheet = .settings
            }

            linkChip
            engineStatusChip
            timingControls(profile: profile)
            bankStrip(icon: "waveform", shortLabel: "M", current: model.mainBank, onSelect: model.setMainBank)
            bankStrip(icon: "person.3.fill", shortLabel: "C", current: model.choirBank, onSelect: model.setChoirBank)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DeckThemeTokens.panelFill.opacity(panelFillOpacity))
        .clipShape(Rectangle())
        .overlay(
            Rectangle().stroke(DeckThemeTokens.panelStroke, lineWidth: 1)
        )
    }

    private var highlightToggleButton: some View {
        Button {
            model.toggleHighlightSelection()
        } label: {
            Image(systemName: "highlighter")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 34)
                .foregroundStyle(model.highlightSelectionEnabled ? Color.black : textPrimaryColor)
                .background(
                    Rectangle().fill(model.highlightSelectionEnabled ? DeckThemeTokens.accentWarn : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.highlightSelectionEnabled ? "Disable Pad Highlight Select" : "Enable Pad Highlight Select")
    }

    private func iconButton(
        systemName: String,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 34)
                .foregroundStyle(isProminent ? Color.black : textPrimaryColor)
                .background(
                    Rectangle().fill(isProminent ? DeckThemeTokens.accentMain : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private var linkChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.socketClient.linkState == .online ? DeckThemeTokens.accentApply : DeckThemeTokens.accentWarn)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("LINK")
                    .font(DeckThemeTokens.monoFont(size: 9, weight: .bold))
                    .foregroundStyle(textMutedColor)
                Text(model.socketClient.linkState.rawValue.uppercased())
                    .font(DeckThemeTokens.monoFont(size: 11, weight: .semibold))
                    .foregroundStyle(textPrimaryColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.25))
        .clipShape(Rectangle())
    }

    private var engineStatusChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "engine.combustion")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(engineReadoutColor)
            Text(model.engineReadout)
                .font(DeckThemeTokens.monoFont(size: 11, weight: .semibold))
                .foregroundStyle(textPrimaryColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.25))
        .clipShape(Rectangle())
    }

    private func timingControls(profile: DeckLayoutProfile) -> some View {
        HStack(spacing: 6) {
            Button {
                model.setTimingMode(.immediate)
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(model.timingMode == .immediate ? Color.black : textPrimaryColor)
                    .background(
                        Rectangle().fill(model.timingMode == .immediate ? DeckThemeTokens.accentApply : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Immediate Timing")

            Button {
                model.setTimingMode(.quantized)
            } label: {
                Image(systemName: "metronome.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(model.timingMode == .quantized ? Color.black : textPrimaryColor)
                    .background(
                        Rectangle().fill(model.timingMode == .quantized ? DeckThemeTokens.accentApply : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quantized Timing")

            Button {
                activeSheet = .quant
            }
            label: {
                Text("\(model.quantIntervalMs)ms")
                    .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                    .foregroundStyle(textPrimaryColor)
                    .frame(minWidth: 58, minHeight: 30)
                    .background(
                        Rectangle().fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .controlSize(profile.commandRailControlSize)
            .disabled(model.timingMode != .quantized)
        }
        .padding(4)
        .background(Color.black.opacity(0.24))
        .clipShape(Rectangle())
    }

    private func bankStrip(
        icon: String,
        shortLabel: String,
        current: Int,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(textMutedColor)
            Text(shortLabel)
                .font(DeckThemeTokens.monoFont(size: 9, weight: .bold))
                .foregroundStyle(textMutedColor)

            ForEach(1...3, id: \.self) { bank in
                Button("B\(bank)") {
                    onSelect(bank)
                }
                .buttonStyle(.plain)
                .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                .foregroundStyle(current == bank ? Color.black : textPrimaryColor)
                .frame(minWidth: 34, minHeight: 30)
                .background(
                    Rectangle().fill(current == bank ? DeckThemeTokens.accentApply : Color.white.opacity(0.12))
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.24))
        .clipShape(Rectangle())
    }

    private func macroRack(profile: DeckLayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MACRO RACK")
                    .font(DeckThemeTokens.monoFont(size: 11, weight: .bold))
                    .foregroundStyle(textMutedColor)
                Spacer()
                Text(model.engineReadout)
                    .font(DeckThemeTokens.monoFont(size: 10, weight: .semibold))
                    .foregroundStyle(engineReadoutColor)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(1...8, id: \.self) { lane in
                    let labelColor = Color.white.opacity(model.settingsState.prefersHighContrast ? 0.98 : 0.94)
                    let subtitleColor = Color.white.opacity(model.settingsState.prefersHighContrast ? 0.88 : 0.82)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.macroTitle(for: lane))
                            .font(DeckThemeTokens.monoFont(size: profile == .compact ? 10 : 11, weight: .semibold))
                            .foregroundStyle(labelColor)
                            .blendMode(.overlay)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(model.macroSubtitle(for: lane))
                            .font(DeckThemeTokens.monoFont(size: 9, weight: .medium))
                            .foregroundStyle(subtitleColor)
                            .blendMode(.overlay)
                            .lineLimit(1)

                        Slider(
                            value: Binding(
                                get: { model.macroValues[lane - 1] },
                                set: { model.setMacroValue(lane: lane, value: $0) }
                            ),
                            in: 0...1
                        )
                        .tint(model.macroAccent(for: lane))
                        .frame(minHeight: 44)

                        Text(String(format: "%.2f", model.macroValues[lane - 1]))
                            .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                            .foregroundStyle(labelColor)
                            .blendMode(.overlay)
                    }
                    .padding(10)
                    .frame(minHeight: profile.macroCellMinHeight)
                    .background(Color.black.opacity(0.28))
                    .clipShape(Rectangle())
                    .overlay(
                        Rectangle().stroke(model.macroAccent(for: lane).opacity(lane >= 7 ? 0.45 : 0.25), lineWidth: 1)
                    )
                }
            }
        }
        .padding(12)
        .background(DeckThemeTokens.panelFill.opacity(panelFillOpacity))
        .clipShape(Rectangle())
        .overlay(
            Rectangle().stroke(DeckThemeTokens.panelStroke, lineWidth: 1)
        )
    }

    private func padStage(profile: DeckLayoutProfile) -> some View {
        GeometryReader { proxy in
            let padSide = max(360, min(proxy.size.width - 8, proxy.size.height - 8))

            padGrid(side: padSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(minHeight: profile == .expanded ? 560 : (profile == .standard ? 500 : 400))
        .padding(10)
        .background(DeckThemeTokens.panelFill.opacity(panelFillOpacity))
        .clipShape(Rectangle())
        .overlay(
            Rectangle().stroke(DeckThemeTokens.panelStroke, lineWidth: 1)
        )
    }

    private func padGrid(side: CGFloat) -> some View {
        let cellSide = (side - (7 * 6)) / 8

        return ZStack(alignment: .topLeading) {
            LazyVGrid(columns: padColumns, spacing: 6) {
                ForEach(0..<64, id: \.self) { slot in
                    padCell(slot: slot, cellSide: cellSide)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)

            PushMultiTouchCaptureView(
                onTouchesChanged: { touches in
                    model.handleTouches(touches, in: CGSize(width: side, height: side))
                },
                onTouchesEnded: {
                    model.endTouches()
                }
            )
            .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
    }

    private func padCell(slot: Int, cellSide: CGFloat) -> some View {
        let active = model.activePadSlots.contains(slot)
        let highlight = model.padHighlightColor(for: slot)
        let activeColor = highlight ?? DeckThemeTokens.accentApply
        let baseFill = active ? activeColor.opacity(0.6) : Color.white.opacity(0.07)
        let frameBorder = active ? activeColor.opacity(0.96) : Color.white.opacity(0.18)
        let labelColor: Color = active ? Color.white.opacity(0.94) : (highlight?.opacity(0.95) ?? textPrimaryColor.opacity(0.9))
        let slotColor: Color = active ? Color.white.opacity(0.9) : Color.white.opacity(0.52)

        return Rectangle()
            .fill(baseFill)
            .overlay(Rectangle().stroke(frameBorder, lineWidth: 0.9))
            .overlay(highlightBorder(highlight: highlight, active: active))
            .overlay(phosphorAura(active: active, color: activeColor))
            .overlay(alignment: .topLeading) {
                Text("\(slot + 1)")
                    .font(DeckThemeTokens.monoFont(size: 8, weight: .bold))
                    .foregroundStyle(slotColor)
                    .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(model.padFileName(for: slot))
                    .font(DeckThemeTokens.monoFont(size: 8, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.56)
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.trailing)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: cellSide, height: cellSide)
            .shadow(color: active ? activeColor.opacity(0.95) : .clear, radius: 6)
            .shadow(color: active ? activeColor.opacity(0.6) : .clear, radius: 16)
            .shadow(color: active ? activeColor.opacity(0.28) : .clear, radius: 26)
    }

    @ViewBuilder
    private func highlightBorder(highlight: Color?, active: Bool) -> some View {
        if let highlight {
            Rectangle().stroke(highlight.opacity(active ? 1.0 : 0.9), lineWidth: 2.2)
        }
    }

    @ViewBuilder
    private func phosphorAura(active: Bool, color: Color) -> some View {
        if active {
            Rectangle()
                .stroke(color.opacity(0.9), lineWidth: 2)
                .blur(radius: 1.4)
        }
    }

    private func sideRail(profile: DeckLayoutProfile) -> some View {
        VStack(spacing: profile.verticalSpacing) {
            actionRail(profile: profile)
                .frame(height: actionRailHeight(for: profile))
            compactMacroRack(profile: profile)
                .frame(maxHeight: .infinity)
        }
    }

    private func compactMacroRack(profile: DeckLayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MACRO RACK")
                    .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                    .foregroundStyle(textMutedColor)
                Spacer()
                Text(model.engineReadout)
                    .font(DeckThemeTokens.monoFont(size: 9, weight: .semibold))
                    .foregroundStyle(engineReadoutColor)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                ForEach(1...8, id: \.self) { lane in
                    let accent = model.macroAccent(for: lane)
                    let value = model.macroValues[lane - 1]
                    let labelColor = Color.white.opacity(model.settingsState.prefersHighContrast ? 0.98 : 0.94)
                    let subtitleColor = Color.white.opacity(model.settingsState.prefersHighContrast ? 0.86 : 0.8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.macroTitle(for: lane))
                            .font(DeckThemeTokens.monoFont(size: 9, weight: .semibold))
                            .foregroundStyle(labelColor)
                            .blendMode(.overlay)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(model.macroSubtitle(for: lane).uppercased())
                            .font(DeckThemeTokens.monoFont(size: 7, weight: .medium))
                            .foregroundStyle(subtitleColor)
                            .blendMode(.overlay)
                            .lineLimit(1)

                        Slider(
                            value: Binding(
                                get: { model.macroValues[lane - 1] },
                                set: { model.setMacroValue(lane: lane, value: $0) }
                            ),
                            in: 0...1
                        )
                        .tint(accent)
                        .frame(minHeight: 28)

                        Text(String(format: "%.2f", model.macroValues[lane - 1]))
                            .font(DeckThemeTokens.monoFont(size: 8, weight: .bold))
                            .foregroundStyle(labelColor)
                            .blendMode(.overlay)
                    }
                    .padding(6)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.44),
                                accent.opacity(0.10 + (value * 0.08))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Rectangle())
                    .overlay(
                        Rectangle().stroke(accent.opacity(lane >= 7 ? 0.62 : 0.34), lineWidth: 1)
                    )
                    .shadow(color: accent.opacity(0.18 + (value * 0.2)), radius: 8)
                }
            }
        }
        .padding(10)
        .background(DeckThemeTokens.panelFill.opacity(panelFillOpacity))
        .clipShape(Rectangle())
        .overlay(
            Rectangle().stroke(DeckThemeTokens.panelStroke, lineWidth: 1)
        )
    }

    private func actionRail(profile: DeckLayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ACTION RAIL")
                .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                .foregroundStyle(textMutedColor)

            ForEach(Array(model.actionRail.prefix(profile.actionRailLimit))) { entry in
                HStack(spacing: 8) {
                    Circle()
                        .fill(entry.severity.color)
                        .frame(width: 6, height: 6)
                    Text(Self.railTimeFormatter.string(from: entry.timestamp))
                        .font(DeckThemeTokens.monoFont(size: 9, weight: .semibold))
                        .foregroundStyle(textMutedColor)
                    Text(entry.displayMessage)
                        .font(DeckThemeTokens.monoFont(size: 10, weight: .medium))
                        .foregroundStyle(entry.severity.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 16)
            }

            if model.actionRail.isEmpty {
                Text("Awaiting control activity")
                    .font(DeckThemeTokens.monoFont(size: 10, weight: .medium))
                    .foregroundStyle(textMutedColor)
            }
        }
        .padding(12)
        .background(DeckThemeTokens.panelFill.opacity(panelFillOpacity))
        .clipShape(Rectangle())
        .overlay(
            Rectangle().stroke(DeckThemeTokens.panelStroke, lineWidth: 1)
        )
    }

    private func actionFlash(_ flash: DeckActionFlashEvent) -> some View {
        Text(flash.message)
            .font(DeckThemeTokens.monoFont(size: 12, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Rectangle()
                    .fill(flash.severity.color)
                    .shadow(color: flash.severity.color.opacity(0.45), radius: 16)
            )
    }

    private func proposalCard(_ proposal: ProposalCardState) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(proposal.lane.displayName)
                    .font(DeckThemeTokens.monoFont(size: 10, weight: .bold))
                    .foregroundStyle(accentWarnColor)
                Spacer()
                Button {
                    model.dismissProposal()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(textMutedColor)
            }

            Text(proposal.rationale)
                .font(DeckThemeTokens.monoFont(size: 10, weight: .medium))
                .foregroundStyle(textPrimaryColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("CONF \(Int(proposal.confidence * 100))%")
                Text("ACCEPT \(proposal.acceptHint)")
                Text("\(proposal.countdownSeconds)s")
            }
            .font(DeckThemeTokens.monoFont(size: 9, weight: .semibold))
            .foregroundStyle(textMutedColor)
        }
        .padding(12)
        .frame(width: 260)
        .background(Color.black.opacity(0.6))
        .clipShape(Rectangle())
        .overlay(
            Rectangle().stroke(accentWarnColor.opacity(0.5), lineWidth: 1)
        )
    }

    private var panelFillOpacity: Double {
        model.settingsState.prefersHighContrast ? 1.0 : 0.74
    }

    private var textMutedColor: Color {
        DeckThemeTokens.textMuted.opacity(model.settingsState.prefersHighContrast ? 1.0 : 0.82)
    }

    private var textPrimaryColor: Color {
        DeckThemeTokens.textPrimary.opacity(model.settingsState.prefersHighContrast ? 1.0 : 0.9)
    }

    private var accentMainColor: Color {
        model.settingsState.prefersHighContrast ? DeckThemeTokens.accentMain : DeckThemeTokens.accentMain.opacity(0.86)
    }

    private var accentWarnColor: Color {
        model.settingsState.prefersHighContrast ? DeckThemeTokens.accentWarn : DeckThemeTokens.accentWarn.opacity(0.8)
    }

    private var engineReadoutColor: Color {
        if model.engineReadout.hasPrefix("DYNAMIC") {
            return DeckThemeTokens.accentApply
        }
        if model.engineReadout.hasPrefix("OFF") {
            return DeckThemeTokens.accentWarn
        }
        return accentMainColor
    }

    private func actionRailWidth(for profile: DeckLayoutProfile) -> CGFloat {
        switch profile {
        case .expanded:
            return 332
        case .standard:
            return 304
        case .compact:
            return 268
        }
    }

    private func actionRailHeight(for profile: DeckLayoutProfile) -> CGFloat {
        switch profile {
        case .expanded:
            return 250
        case .standard:
            return 232
        case .compact:
            return 210
        }
    }

    private static let railTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
