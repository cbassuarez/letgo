import AVKit
import ConductorCore
import SwiftUI

struct ConductorSurfaceView: View {
    @ObservedObject var model: ConductorHarnessViewModel

    @State private var wsURL: String = "ws://localhost:8787/ws/harness"
    @State private var blinkOn = false
    @State private var inspectorOpen = false

    private let blinkTimer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()
    private let sceneImportOrder: [ShowState] = [.preshow, .introduction, .main, .ending]

    var body: some View {
        VStack(spacing: 12) {
            topStatusBar

            HStack(alignment: .top, spacing: 12) {
                leftColumn
                    .frame(width: 230)
                centerColumn
                    .frame(maxWidth: .infinity)
                rightColumn
                    .frame(width: 280)
            }

            flightLogPanel
                .frame(height: 150)

            if inspectorOpen {
                inspectorDrawer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(14)
        .frame(minWidth: 1280, minHeight: 860)
        .background(ConsoleTheme.consoleBackground)
        .preferredColorScheme(.dark)
        .onReceive(blinkTimer) { _ in
            blinkOn.toggle()
        }
    }

    // MARK: - Top status bar

    private var topStatusBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CONDUCTOR I")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .tracking(3.0)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("LAUNCH CONTROL · MK II")
                    .font(ConsoleTheme.smallTagFont(size: 8))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            Divider().frame(height: 28).overlay(Color.white.opacity(0.1))

            // System lamp cluster
            HStack(spacing: 14) {
                StatusLamp(
                    label: "ENG",
                    state: model.engineRunning ? .nominal : .standby,
                    blinkOn: blinkOn
                )
                StatusLamp(
                    label: "LINK",
                    state: linkLampState,
                    pulse: model.connectionStatus.contains("Connecting"),
                    blinkOn: blinkOn
                )
                StatusLamp(
                    label: "ML",
                    state: mlLampState,
                    blinkOn: blinkOn
                )
                StatusLamp(
                    label: "LATCH",
                    state: model.isLatchArmed ? .caution : .standby,
                    pulse: model.isLatchArmed,
                    blinkOn: blinkOn
                )
                StatusLamp(
                    label: "ARM KEY",
                    state: model.masterArmKey == .armed ? .fault : .standby,
                    pulse: model.masterArmKey == .armed,
                    blinkOn: blinkOn
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(ConsoleTheme.panelInnerFill)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
            )

            Spacer()

            // Show-state lamp strip
            HStack(spacing: 6) {
                ForEach(ShowState.allCases, id: \.self) { state in
                    showStateLamp(state)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    inspectorOpen.toggle()
                }
            } label: {
                Text(inspectorOpen ? "HIDE INSPECTOR" : "INSPECTOR")
                    .font(ConsoleTheme.smallTagFont(size: 9))
                    .tracking(1.4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .background(ConsoleTheme.panelInnerFill)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ConsoleTheme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
        )
    }

    private func showStateLamp(_ state: ShowState) -> some View {
        let isActive = model.state == state
        let lampState: LampState = isActive
            ? (state == .aborted ? .fault : (state == .hold ? .caution : .nominal))
            : .off
        return VStack(spacing: 3) {
            StatusLamp(
                label: state.rawValue,
                state: lampState,
                pulse: isActive && (state == .hold || state == .aborted),
                blinkOn: blinkOn,
                diameter: 10,
                labelPlacement: .none
            )
            Text(state.rawValue.uppercased())
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.3))
        }
        .frame(width: 52)
    }

    // MARK: - Left column: GO/NO-GO + master arm

    private var leftColumn: some View {
        VStack(spacing: 12) {
            ConsolePanel("GO / NO-GO", accent: ConsoleTheme.lampGreen) {
                VStack(alignment: .leading, spacing: 7) {
                    checklistRow("ENG RUN", lit: model.engineRunning)
                    checklistRow("WS LINK", lit: linkLampState == .nominal)
                    checklistRow("ML HEALTHY", lit: model.modelHealthLevel == .healthy)
                    checklistRow("MEDIA LOADED", lit: !model.sceneMediaURLs.isEmpty || !model.showFixedLanes.isEmpty)
                    checklistRow("LATCH ARMED", lit: model.isLatchArmed, caution: true)
                    checklistRow("MASTER ARM", lit: model.masterArmKey == .armed, fault: true)
                    checklistRow("CAN FIRE GO", lit: model.canFireWithMasterArm, caution: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ConsolePanel("ARM KEY", accent: ConsoleTheme.lampRed) {
                VStack(spacing: 8) {
                    KeySwitch(
                        isArmed: model.masterArmKey == .armed,
                        onToggle: model.toggleMasterArmKey
                    )
                    Text(model.masterArmKey == .armed
                         ? "FIRE CIRCUIT LIVE"
                         : "FIRE CIRCUIT INHIBITED")
                        .font(ConsoleTheme.smallTagFont(size: 8))
                        .tracking(1.0)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(model.masterArmKey == .armed ? ConsoleTheme.lampRed : Color.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func checklistRow(_ label: String, lit: Bool, caution: Bool = false, fault: Bool = false) -> some View {
        let state: LampState = {
            if !lit { return .off }
            if fault { return .fault }
            if caution { return .caution }
            return .nominal
        }()
        return HStack(spacing: 10) {
            StatusLamp(
                label: label,
                state: state,
                blinkOn: blinkOn,
                diameter: 10,
                labelPlacement: .none
            )
            Text(label)
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.1)
                .foregroundStyle(lit ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
            Spacer()
            Text(lit ? "GO" : "NOGO")
                .font(ConsoleTheme.smallTagFont(size: 8))
                .foregroundStyle(lit ? ConsoleTheme.lampGreen : Color.white.opacity(0.3))
        }
    }

    // MARK: - Center column: launch panel

    private var centerColumn: some View {
        VStack(spacing: 12) {
            ConsolePanel("T-MINUS · LAUNCH", accent: ConsoleTheme.lampAmber) {
                VStack(spacing: 14) {
                    SegmentedCountdown(
                        seconds: model.latchCountdownSeconds,
                        isArmed: model.isLatchArmed,
                        blinkOn: blinkOn,
                        summary: model.latchSummary
                    )

                    HStack(alignment: .top, spacing: 18) {
                        ProgramPreviewBus(
                            title: "Output Mode",
                            rows: outputModeRows,
                            programId: model.committedOutputMode.rawValue,
                            previewId: model.pendingOutputMode?.rawValue,
                            canTake: model.canFireWithMasterArm && model.engineRunning,
                            blinkOn: blinkOn,
                            onPreviewSelect: { id in
                                if let mode = FlightOutputMode(rawValue: id) {
                                    model.armOutputMode(mode)
                                }
                            },
                            onTake: model.fireOutputGO
                        )

                        ProgramPreviewBus(
                            title: "Static Lane",
                            rows: laneRows,
                            programId: model.activeStaticLaneId,
                            previewId: model.pendingLaneId,
                            canTake: model.canFireWithMasterArm && model.engineRunning,
                            blinkOn: blinkOn,
                            onPreviewSelect: model.armTransportLane,
                            onTake: model.fireOutputGO
                        )
                    }
                }
            }

            ConsolePanel("FLIGHT CONTROLS", accent: ConsoleTheme.lampBlue) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IlluminatedButton(
                            label: "START",
                            subtitle: "ENGINE",
                            color: ConsoleTheme.lampGreen,
                            isLit: !model.engineRunning,
                            isEnabled: !model.engineRunning,
                            minWidth: 110,
                            minHeight: 56,
                            action: model.startEngine
                        )
                        IlluminatedButton(
                            label: "STOP",
                            subtitle: "ENGINE",
                            color: ConsoleTheme.lampRed,
                            isLit: model.engineRunning,
                            isEnabled: model.engineRunning,
                            style: .critical,
                            minWidth: 110,
                            minHeight: 56,
                            action: model.stopEngine
                        )
                        IlluminatedButton(
                            label: "RESET",
                            subtitle: "SHOW",
                            color: ConsoleTheme.lampAmber,
                            isLit: false,
                            isEnabled: true,
                            minWidth: 110,
                            minHeight: 56,
                            action: model.resetShowRun
                        )

                        Spacer()

                        IlluminatedButton(
                            label: "HOLD",
                            color: ConsoleTheme.lampAmber,
                            isLit: model.state == .hold,
                            isEnabled: model.canApply(action: .hold),
                            blinkOn: blinkOn,
                            pulseWhenLit: true,
                            minWidth: 110,
                            minHeight: 56,
                            action: { model.apply(action: .hold) }
                        )
                        IlluminatedButton(
                            label: "RECOVER",
                            color: ConsoleTheme.lampGreen,
                            isLit: model.state == .recovery,
                            isEnabled: model.canApply(action: .recover),
                            minWidth: 110,
                            minHeight: 56,
                            action: { model.apply(action: .recover) }
                        )
                        SafetyCoverButton(
                            label: "ABORT",
                            armedSubtitle: "PRESS TO FIRE",
                            liftedSubtitle: "PRESS TO FIRE",
                            isCoverOpen: model.abortCoverOpen,
                            canCommit: model.canApply(action: .abort),
                            blinkOn: blinkOn,
                            onLift: model.openAbortCover,
                            onCancel: model.cancelAbortCover,
                            onCommit: model.commitAbort
                        )
                    }

                    Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 2)

                    Text("TIMELINE STEPS")
                        .font(ConsoleTheme.smallTagFont(size: 9))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.45))

                    HStack(spacing: 10) {
                        timelineButton("PRESHOW", isActive: model.state == .preshow, action: model.runPreshowTimelineStep)
                        timelineButton("INTRO", isActive: model.state == .introduction, action: model.runIntroductionTimelineStep)
                        timelineButton("ENDING", isActive: model.state == .ending, action: model.runEndingTimelineStep)
                        Spacer()
                        if let cue = model.latestCue {
                            Text("LAST CUE  \(cue.cueId)")
                                .font(ConsoleTheme.telemetryFont(size: 10))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                    }
                    .disabled(!model.engineRunning)
                }
            }
        }
    }

    private func timelineButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        IlluminatedButton(
            label: label,
            color: isActive ? ConsoleTheme.lampBlue : ConsoleTheme.lampStandby,
            isLit: isActive,
            isEnabled: model.engineRunning,
            minWidth: 90,
            minHeight: 36,
            action: action
        )
    }

    // MARK: - Right column: vectors + telemetry

    private var rightColumn: some View {
        VStack(spacing: 12) {
            ConsolePanel("DYNAMIC VECTORS", accent: ConsoleTheme.lampGreen) {
                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Bargraph(label: "TXT", value: model.vector.textAmount) {
                            model.patchVector(ParamVectorPatch(textAmount: $0))
                        }
                        Bargraph(label: "BIAS", value: model.vector.compositeBias) {
                            model.patchVector(ParamVectorPatch(compositeBias: $0))
                        }
                        Bargraph(label: "GAIN", value: model.vector.audioGain) {
                            model.patchVector(ParamVectorPatch(audioGain: $0))
                        }
                    }
                    HStack(alignment: .bottom, spacing: 4) {
                        Bargraph(label: "SPL X", value: model.vector.spatialX) {
                            model.patchVector(ParamVectorPatch(spatialX: $0))
                        }
                        Bargraph(label: "SPL Y", value: model.vector.spatialY) {
                            model.patchVector(ParamVectorPatch(spatialY: $0))
                        }
                        Bargraph(label: "SPL Z", value: model.vector.spatialZ) {
                            model.patchVector(ParamVectorPatch(spatialZ: $0))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            ConsolePanel("AUDIENCE TELEMETRY", accent: ConsoleTheme.lampBlue) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(model.devices.count) DEVICES")
                            .font(ConsoleTheme.smallTagFont(size: 9))
                            .tracking(1.2)
                            .foregroundStyle(Color.white.opacity(0.55))
                        Spacer()
                        Button {
                            model.refreshTelemetry()
                        } label: {
                            Text("PING")
                                .font(ConsoleTheme.smallTagFont(size: 8))
                                .tracking(1.0)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundStyle(Color.white.opacity(0.7))
                                .background(ConsoleTheme.panelInnerFill)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if model.devices.isEmpty {
                        Text("// no devices acquired")
                            .font(ConsoleTheme.telemetryFont(size: 10))
                            .foregroundStyle(Color.white.opacity(0.3))
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(model.devices) { device in
                                    deviceRow(device)
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func deviceRow(_ device: DeviceTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(device.id)
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.75))
            Text("ZONE \(device.zoneName ?? "—") · A:\(device.permissions.audio ? "Y" : "N") G:\(device.permissions.geolocation ? "Y" : "N") M:\(device.permissions.motion ? "Y" : "N")")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    // MARK: - Flight log

    private var flightLogPanel: some View {
        ConsolePanel("FLIGHT LOG · TELEMETRY TAPE", accent: ConsoleTheme.lampGreen) {
            FlightLogTape(entries: model.statusLineHistory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Inspector drawer (preview / media / coreml / connection)

    private var inspectorDrawer: some View {
        HStack(alignment: .top, spacing: 12) {
            ConsolePanel("LINK · MEDIA", accent: ConsoleTheme.lampStandby) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WEBSOCKET")
                        .font(ConsoleTheme.smallTagFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))
                    HStack {
                        TextField("ws://...", text: $wsURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Button("LINK") { model.connect(to: wsURL) }
                            .buttonStyle(.bordered)
                        Button("DROP") { model.disconnect() }
                            .buttonStyle(.bordered)
                    }
                    Text(model.connectionStatus.uppercased())
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))

                    Divider().overlay(Color.white.opacity(0.08))

                    Text("MEDIA BANK")
                        .font(ConsoleTheme.smallTagFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))

                    ForEach(sceneImportOrder, id: \.self) { scene in
                        HStack {
                            Text(scene.rawValue.uppercased())
                                .font(ConsoleTheme.telemetryFont(size: 10))
                                .frame(width: 80, alignment: .leading)
                                .foregroundStyle(Color.white.opacity(0.65))
                            Button("LOAD") { model.importSceneMedia(for: scene) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Text(model.mediaFilename(for: scene))
                                .font(ConsoleTheme.telemetryFont(size: 9))
                                .foregroundStyle(Color.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                    HStack {
                        Text("INTERSTL")
                            .font(ConsoleTheme.telemetryFont(size: 10))
                            .frame(width: 80, alignment: .leading)
                            .foregroundStyle(Color.white.opacity(0.65))
                        Button("LOAD") { model.importInterstitialMedia() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Text(model.interstitialFilename())
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    HStack {
                        Text("LANE +")
                            .font(ConsoleTheme.telemetryFont(size: 10))
                            .frame(width: 80, alignment: .leading)
                            .foregroundStyle(Color.white.opacity(0.65))
                        Button("ADD") { model.importShowFixedLaneMedia() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Text("\(model.showFixedLanes.count) LANES")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
            }
            .frame(maxWidth: .infinity)

            ConsolePanel("PREVIEW MONITOR", accent: ConsoleTheme.lampAmber) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MODE \(model.effectiveOutputMode.rawValue.uppercased())  ·  \(model.previewStatus)")
                        .font(ConsoleTheme.telemetryFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                    VideoPlayer(player: model.previewPlayer)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.6)
                        )
                    HStack {
                        Button("PLAY") { model.playPreview() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("PAUSE") { model.pausePreview() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Spacer()
                    }
                    if !model.generatedLine.isEmpty {
                        Text(model.generatedLine)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .frame(width: 360)

            ConsolePanel("COREML RUNTIME", accent: ConsoleTheme.lampGreen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.modelHealthLevel.rawValue.uppercased())
                            .font(ConsoleTheme.smallTagFont(size: 9))
                            .tracking(1.2)
                            .foregroundStyle(modelHealthColor)
                        Spacer()
                        Text("FAIL \(model.modelRuntimeFailures)")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    HStack(spacing: 6) {
                        Button("IMPORT") { model.importModelBundleFromDisk() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("REFRESH") { model.refreshModelCatalog() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("AUTO RELOAD") { model.reloadPreferredModel() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    if !model.modelCandidates.isEmpty {
                        HStack {
                            Picker("", selection: $model.selectedModelCandidateID) {
                                ForEach(model.modelCandidates) { candidate in
                                    Text(candidate.name).tag(candidate.id)
                                }
                            }
                            .pickerStyle(.menu)
                            Button("LOAD") { model.loadSelectedModelBundle() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    Text(model.modelHealthSummary)
                        .font(ConsoleTheme.telemetryFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(2)
                    if !model.modelChecks.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(model.modelChecks) { check in
                                    HStack(spacing: 6) {
                                        Text(check.passed ? "OK" : "FAIL")
                                            .font(ConsoleTheme.smallTagFont(size: 8))
                                            .foregroundStyle(check.passed ? ConsoleTheme.lampGreen : ConsoleTheme.lampRed)
                                            .frame(width: 28, alignment: .leading)
                                        Text("\(check.name): \(check.details)")
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 80)
                    }
                }
            }
            .frame(width: 320)
        }
        .frame(height: 280)
    }

    // MARK: - Derived rows

    private var outputModeRows: [BusRow] {
        FlightOutputMode.allCases.map { mode in
            BusRow(
                id: mode.rawValue,
                label: mode.rawValue,
                subtitle: mode == .static ? "fixed lane" : (mode == .dynamic ? "live render" : "silent"),
                canSelect: true
            )
        }
    }

    private var laneRows: [BusRow] {
        let descriptors = model.transportLaneDescriptors
        if descriptors.isEmpty {
            return [BusRow(id: "__empty__", label: "no lanes loaded", subtitle: nil, canSelect: false)]
        }
        return descriptors.map { lane in
            BusRow(
                id: lane.id,
                label: lane.label,
                subtitle: lane.isActive ? "on program" : nil,
                canSelect: lane.canArm
            )
        }
    }

    // MARK: - Lamp helpers

    private var linkLampState: LampState {
        let s = model.connectionStatus
        if s.contains("Connected") { return .nominal }
        if s.contains("Connecting") { return .caution }
        if s.contains("error") || s.contains("failed") { return .fault }
        return .standby
    }

    private var mlLampState: LampState {
        switch model.modelHealthLevel {
        case .healthy: return .nominal
        case .degraded: return .caution
        case .unavailable: return .fault
        }
    }

    private var modelHealthColor: Color {
        switch model.modelHealthLevel {
        case .healthy: return ConsoleTheme.lampGreen
        case .degraded: return ConsoleTheme.lampAmber
        case .unavailable: return ConsoleTheme.lampRed
        }
    }
}
