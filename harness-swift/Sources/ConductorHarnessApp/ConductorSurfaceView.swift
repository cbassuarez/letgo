import AVKit
import ConductorCore
import SwiftUI

private enum ImportModuleKind: Identifiable {
    case scene(ShowState)
    case interstitial
    case fixedLane
    case coreML
    case synthPreset
    case samplePack
    case choirProfile

    var id: String {
        switch self {
        case .scene(let scene):
            return "scene-\(scene.rawValue)"
        case .interstitial:
            return "interstitial"
        case .fixedLane:
            return "fixed-lane"
        case .coreML:
            return "coreml"
        case .synthPreset:
            return "synth-preset"
        case .samplePack:
            return "sample-pack"
        case .choirProfile:
            return "choir-profile"
        }
    }

    var title: String {
        switch self {
        case .scene(let scene):
            return "Load \(scene.rawValue.capitalized) Media"
        case .interstitial:
            return "Load Interstitial Media"
        case .fixedLane:
            return "Add Static Lane Media"
        case .coreML:
            return "Import CoreML Bundle"
        case .synthPreset:
            return "Load Synth Preset Pack"
        case .samplePack:
            return "Load Sample Pack Manifest"
        case .choirProfile:
            return "Load Choir Profile"
        }
    }
}

struct SoundPerformanceSpineView: View {
    let snapshot: SoundSituationalSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SoundSpineDomainCard(
                title: "BANKS / IMPORT",
                level: snapshot.banksImport.level,
                lines: [
                    "MAIN B\(snapshot.banksImport.mainBank) · CHOIR B\(snapshot.banksImport.choirBank)",
                    "PACK \(snapshot.banksImport.sampleEntryCount) · \(snapshot.banksImport.samplePackFile)",
                    "SYN \(snapshot.banksImport.synthPresetFile) · CHOIR \(snapshot.banksImport.choirProfileFile)"
                ]
            )

            SoundSpineDomainCard(
                title: "SOUND MODE",
                level: snapshot.modeLevel,
                lines: [
                    "\(snapshot.modePrimary.rawValue) · \(snapshot.modeDetail.rawValue)",
                    snapshot.modePrimary == .phoneChoir ? "PHONE CHOIR PIPELINE ACTIVE" : "MAIN SAMPLE PIPELINE ACTIVE",
                    snapshot.modePrimary == .phoneChoir
                        ? "USE CUE/GATE FOR PHONE DISPATCH"
                        : "PHONE CHOIR CONTEXT OFF"
                ]
            )

            SoundSpineDomainCard(
                title: "CONNECTED I/O",
                level: snapshot.io.level,
                lines: [
                    "OUT \(snapshot.io.outputRouteName)",
                    snapshot.io.outputRouteSummary,
                    "MIDI \(snapshot.io.midiStatus) · HOTAS \(snapshot.io.hotasStatus) · PUSH \(snapshot.io.pushStatus)"
                ]
            )

            SoundSpineDomainCard(
                title: "ACTIVE SOUND",
                level: snapshot.manipulationIsStale ? .caution : .nominal,
                lines: [
                    "\(snapshot.activeTarget.label) · \(snapshot.activeTarget.bankDomain.rawValue) B\(snapshot.activeTarget.bank)",
                    "\(snapshot.activeTarget.fileName) · id \(snapshot.activeTarget.sampleID)",
                    focusLine(snapshot)
                ]
            )
        }
    }

    private func focusLine(_ snapshot: SoundSituationalSnapshot) -> String {
        guard let focus = snapshot.manipulation else {
            return "NO RECENT MANIPULATION"
        }
        let percent = Int((focus.normalizedValue * 100).rounded())
        let stale = snapshot.manipulationIsStale ? " · STALE" : ""
        return "\(focus.source) \(focus.controlID) · \(focus.lane) \(percent)%\(stale)"
    }
}

struct SoundSpineCompactView: View {
    let snapshot: SoundSituationalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                compactDomain(
                    "BANKS / IMPORT",
                    level: snapshot.banksImport.level,
                    line: "M\(snapshot.banksImport.mainBank)/C\(snapshot.banksImport.choirBank) · pack \(snapshot.banksImport.sampleEntryCount)"
                )
                compactDomain(
                    "SOUND MODE",
                    level: snapshot.modeLevel,
                    line: "\(snapshot.modePrimary.rawValue) · \(snapshot.modeDetail.rawValue)"
                )
            }
            HStack(alignment: .top, spacing: 8) {
                compactDomain(
                    "CONNECTED I/O",
                    level: snapshot.io.level,
                    line: "OUT \(snapshot.io.outputRouteSummary) · M \(snapshot.io.midiStatus) · H \(snapshot.io.hotasStatus) · P \(snapshot.io.pushStatus)"
                )
                compactDomain(
                    "ACTIVE SOUND",
                    level: snapshot.manipulationIsStale ? .caution : .nominal,
                    line: compactActiveLine
                )
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.11), lineWidth: 0.8)
        )
    }

    private var compactActiveLine: String {
        if let focus = snapshot.manipulation {
            let percent = Int((focus.normalizedValue * 100).rounded())
            let stale = snapshot.manipulationIsStale ? " · STALE" : ""
            return "\(snapshot.activeTarget.label) · \(focus.lane) \(percent)%\(stale)"
        }
        return "\(snapshot.activeTarget.label) · WAITING FOR INPUT"
    }

    private func compactDomain(_ title: String, level: SoundSignalLevel, line: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(SoundSpineTheme.textColor(level).opacity(0.95))
            Text(line)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(SoundSpineTheme.background(level))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(SoundSpineTheme.stroke(level), lineWidth: 0.8)
        )
    }
}

struct SoundSpineHUDView: View {
    let snapshot: SoundSituationalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            hudLine("BANKS / IMPORT", level: snapshot.banksImport.level, value: "M\(snapshot.banksImport.mainBank) C\(snapshot.banksImport.choirBank) · pack \(snapshot.banksImport.sampleEntryCount) · \(snapshot.banksImport.samplePackFile)")
            hudLine("SOUND MODE", level: snapshot.modeLevel, value: "\(snapshot.modePrimary.rawValue) · \(snapshot.modeDetail.rawValue)")
            hudLine("CONNECTED I/O", level: snapshot.io.level, value: "OUT \(snapshot.io.outputRouteSummary) · MIDI \(snapshot.io.midiStatus) · HOTAS \(snapshot.io.hotasStatus) · PUSH \(snapshot.io.pushStatus)")
            hudLine("ACTIVE SOUND", level: snapshot.manipulationIsStale ? .caution : .nominal, value: hudActiveValue)
            Text("READ-ONLY HERE · OPEN SAFETY/FULL FOR IMPORT")
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.28))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var hudActiveValue: String {
        guard let focus = snapshot.manipulation else {
            return "\(snapshot.activeTarget.label) · \(snapshot.activeTarget.fileName) · WAITING"
        }
        let percent = Int((focus.normalizedValue * 100).rounded())
        let stale = snapshot.manipulationIsStale ? " · STALE" : ""
        return "\(snapshot.activeTarget.label) · \(focus.lane) \(percent)%\(stale)"
    }

    private func hudLine(_ title: String, level: SoundSignalLevel, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(SoundSpineTheme.textColor(level).opacity(0.9))
                .frame(width: 108, alignment: .leading)
            Text(value)
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)
        }
    }
}

private struct SoundSpineDomainCard: View {
    let title: String
    let level: SoundSignalLevel
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.1)
                .foregroundStyle(SoundSpineTheme.textColor(level))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(ConsoleTheme.telemetryFont(size: 9))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(SoundSpineTheme.background(level))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(SoundSpineTheme.stroke(level), lineWidth: 0.7)
        )
    }
}

private enum SoundSpineTheme {
    static func background(_ level: SoundSignalLevel) -> Color {
        switch level {
        case .nominal:
            return Color.white.opacity(0.05)
        case .caution:
            return Color(red: 0.34, green: 0.24, blue: 0.08).opacity(0.42)
        case .critical:
            return Color(red: 0.4, green: 0.12, blue: 0.12).opacity(0.45)
        }
    }

    static func stroke(_ level: SoundSignalLevel) -> Color {
        switch level {
        case .nominal:
            return Color.white.opacity(0.18)
        case .caution:
            return ConsoleTheme.lampAmber.opacity(0.72)
        case .critical:
            return ConsoleTheme.lampRed.opacity(0.78)
        }
    }

    static func textColor(_ level: SoundSignalLevel) -> Color {
        switch level {
        case .nominal:
            return ConsoleTheme.lampBlue
        case .caution:
            return ConsoleTheme.lampAmber
        case .critical:
            return ConsoleTheme.lampRed
        }
    }
}

// MARK: - Perf-isolated subviews
//
// These structs are marked Equatable so SwiftUI can skip re-running their
// body when their minimal snapshot hasn't changed. The parent view still
// rebuilds view values on every model publish, but heavy children (bargraph
// cluster, action stream, device list, flight log) are diffed by value and
// only rerender when their inputs actually shift.

private struct ControlPlaneBargraphCluster: View, Equatable {
    struct Values: Equatable {
        var spatialX: Double
        var cutCadence: Double
        var fade: Double
        var sampleMorph: Double
        var articulation: Double
        var timbre: Double
        var choirSpread: Double
        var choirDepth: Double
        var choirDetune: Double
        var fxAIntensity: Double
        var fxBIntensity: Double
        var textProbability: Double
    }

    let values: Values
    let onSpatialX: (Double) -> Void
    let onCutCadence: (Double) -> Void
    let onFade: (Double) -> Void
    let onSampleMorph: (Double) -> Void
    let onArticulation: (Double) -> Void
    let onTimbre: (Double) -> Void
    let onChoirSpread: (Double) -> Void
    let onChoirDepth: (Double) -> Void
    let onChoirDetune: (Double) -> Void
    let onFxA: (Double) -> Void
    let onFxB: (Double) -> Void
    let onTextProbability: (Double) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.values == rhs.values }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                Bargraph(label: "SRC X", value: values.spatialX, onChange: onSpatialX)
                Bargraph(label: "CAD Y", value: values.cutCadence, onChange: onCutCadence)
                Bargraph(label: "CMP Z", value: values.fade, onChange: onFade)
            }
            HStack(alignment: .bottom, spacing: 4) {
                Bargraph(label: "MORPH", value: values.sampleMorph, onChange: onSampleMorph)
                Bargraph(label: "ARTIC", value: values.articulation, onChange: onArticulation)
                Bargraph(label: "TIMBRE", value: values.timbre, onChange: onTimbre)
            }
            HStack(alignment: .bottom, spacing: 4) {
                Bargraph(label: "CHOIR S", value: values.choirSpread, onChange: onChoirSpread)
                Bargraph(label: "CHOIR D", value: values.choirDepth, onChange: onChoirDepth)
                Bargraph(label: "CHOIR T", value: values.choirDetune, onChange: onChoirDetune)
            }
            HStack(alignment: .bottom, spacing: 4) {
                Bargraph(label: "A RHY", value: values.fxAIntensity, onChange: onFxA)
                Bargraph(label: "B SPC", value: values.fxBIntensity, onChange: onFxB)
                Bargraph(label: "TXT P", value: values.textProbability, onChange: onTextProbability)
            }
        }
    }
}

private struct MLActionStreamPanel: View, Equatable {
    struct Snapshot: Equatable {
        var proposal: MLProposal?
        var countdownSeconds: Double?
        var events: [HUDActionEvent]
    }

    let snapshot: Snapshot
    let onAccept: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.snapshot == rhs.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let proposal = snapshot.proposal {
                let countdown = snapshot.countdownSeconds ?? 0
                Text("ACTIVE \(proposal.lane.rawValue.uppercased()) · CONF \(decimalString(proposal.confidence)) · T-\(decimalString(countdown))s")
                    .font(ConsoleTheme.smallTagFont(size: 8))
                    .foregroundStyle(ConsoleTheme.lampAmber)
                Text(proposal.rationale)
                    .font(ConsoleTheme.telemetryFont(size: 9))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(2)
                Text(proposal.expectedEffect)
                    .font(ConsoleTheme.telemetryFont(size: 9))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                Button("ACCEPT PROPOSAL (JOY_1)", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Text("NO ACTIVE PROPOSAL · JOY_1 ARMED")
                    .font(ConsoleTheme.smallTagFont(size: 8))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Divider().overlay(Color.white.opacity(0.08))

            ForEach(Array(snapshot.events.prefix(8))) { event in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.severity.rawValue)
                        .font(ConsoleTheme.smallTagFont(size: 8))
                        .foregroundStyle(eventColor(event.severity))
                        .frame(width: 42, alignment: .leading)
                    Text(event.stage.rawValue.uppercased())
                        .font(ConsoleTheme.telemetryFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .frame(width: 48, alignment: .leading)
                    Text(event.semanticAction ?? event.controlID)
                        .font(ConsoleTheme.telemetryFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func decimalString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func eventColor(_ severity: HUDEventSeverity) -> Color {
        switch severity {
        case .info: return Color.white.opacity(0.7)
        case .act: return ConsoleTheme.lampBlue
        case .apply: return ConsoleTheme.lampGreen
        case .block: return ConsoleTheme.lampAmber
        case .error: return ConsoleTheme.lampRed
        }
    }
}

private struct TelemetryDevicePanel: View, Equatable {
    struct Snapshot: Equatable {
        var deviceCount: Int
        var poolSize: Int
        var voiceCount: Int
        var failoverCount: Int
        var zoneCount: Int
        var dominantZone: String
        var unhealthyCount: Int
        var cueLeadMs: Double
        var cueCohortSize: Int
        var cueCohortP95RttMs: Double
        var activationSkewP50Ms: Double
        var activationSkewP95Ms: Double
        var activationMissP95Ms: Double
        var devices: [DeviceTelemetry]
    }

    let snapshot: Snapshot
    let onPing: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.snapshot == rhs.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(snapshot.deviceCount) DEVICES")
                    .font(ConsoleTheme.smallTagFont(size: 9))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Button(action: onPing) {
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

            HStack {
                Text("POOL \(snapshot.poolSize) · VOICES \(snapshot.voiceCount)")
                Spacer()
                Text("FAILOVER \(snapshot.failoverCount)")
            }
            .font(ConsoleTheme.telemetryFont(size: 9))
            .foregroundStyle(Color.white.opacity(0.58))

            HStack {
                Text("ZONES \(snapshot.zoneCount) · TOP \(snapshot.dominantZone)")
                Spacer()
                Text("UNHEALTHY \(snapshot.unhealthyCount)")
            }
            .font(ConsoleTheme.telemetryFont(size: 9))
            .foregroundStyle(Color.white.opacity(0.58))

            HStack {
                Text("TAKE LEAD \(Int(snapshot.cueLeadMs))ms · COHORT \(snapshot.cueCohortSize)")
                Spacer()
                Text("RTT P95 \(Int(snapshot.cueCohortP95RttMs))ms")
            }
            .font(ConsoleTheme.telemetryFont(size: 9))
            .foregroundStyle(Color.white.opacity(0.58))

            HStack {
                Text("SKEW P50 \(Int(snapshot.activationSkewP50Ms))ms · P95 \(Int(snapshot.activationSkewP95Ms))ms")
                Spacer()
                Text("MISS P95 \(Int(snapshot.activationMissP95Ms))ms")
            }
            .font(ConsoleTheme.telemetryFont(size: 9))
            .foregroundStyle(Color.white.opacity(0.58))

            if snapshot.devices.isEmpty {
                Text("// no devices acquired")
                    .font(ConsoleTheme.telemetryFont(size: 10))
                    .foregroundStyle(Color.white.opacity(0.3))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(snapshot.devices) { device in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.id)
                                    .font(ConsoleTheme.telemetryFont(size: 10))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                Text("ZONE \(device.zoneName ?? "—") · A:\(device.permissions.audio ? "Y" : "N") G:\(device.permissions.geolocation ? "Y" : "N") M:\(device.permissions.motion ? "Y" : "N")")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlightLogPanelSection: View, Equatable {
    let entries: [StatusLineEvent]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.entries == rhs.entries }

    var body: some View {
        ConsolePanel("FLIGHT LOG · TELEMETRY TAPE", accent: ConsoleTheme.lampGreen) {
            FlightLogTape(entries: entries)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ConductorSurfaceView: View {
    @ObservedObject var model: ConductorHarnessViewModel
    @ObservedObject var inspectorPresentation: InspectorPresentationState

    @State private var blinkOn = false
    @State private var setupModalOpen = false
    @State private var activeImportModal: ImportModuleKind?

    private let blinkTimer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()
    private let sceneImportOrder: [ShowState] = [.preshow, .introduction, .ending]

    var body: some View {
        VStack(spacing: 12) {
            topStatusBar
            SoundPerformanceSpineView(snapshot: model.soundSituationalSnapshot)

            HStack(alignment: .top, spacing: 12) {
                ScrollView(.vertical, showsIndicators: false) {
                    leftColumn.padding(.trailing, 2)
                }
                .frame(width: 240)

                ScrollView(.vertical, showsIndicators: false) {
                    centerColumn.padding(.trailing, 2)
                }
                .frame(maxWidth: .infinity)

                ScrollView(.vertical, showsIndicators: false) {
                    rightColumn.padding(.trailing, 2)
                }
                .frame(width: 320)
            }
            .frame(maxHeight: .infinity)

            flightLogPanel
                .frame(height: 160)
        }
        .padding(14)
        .frame(minWidth: 1340, minHeight: 720)
        .background(ConsoleTheme.consoleBackground)
        .preferredColorScheme(.dark)
        .overlay {
            WindowAccessor { window in
                WindowChromeCoordinator.applyChromelessHUD(to: window, isResizable: true)
            }
            .allowsHitTesting(false)
        }
        .onReceive(blinkTimer) { _ in
            guard shouldAnimateBlink else {
                if blinkOn {
                    blinkOn = false
                }
                return
            }
            blinkOn.toggle()
        }
        .onAppear {
            inspectorPresentation.markActive(.fullConsole)
        }
        .sheet(item: $activeImportModal) { module in
            ImportModuleSheet(module: module, model: model)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $setupModalOpen) {
            SetupSheet(model: model)
                .preferredColorScheme(.dark)
        }
        .sheet(
            isPresented: Binding(
                get: {
                    inspectorPresentation.isPresented && inspectorPresentation.source == .fullConsole
                },
                set: { isPresented in
                    if isPresented {
                        inspectorPresentation.present(from: .fullConsole)
                    } else {
                        inspectorPresentation.dismiss()
                    }
                }
            )
        ) {
            InspectorModalView(model: model, presentation: inspectorPresentation)
        }
    }

    private var shouldAnimateBlink: Bool {
        model.linkState == .connecting
            || model.linkState == .backoff
            || model.state == .hold
            || model.state == .aborted
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
                    pulse: model.linkState == .connecting || model.linkState == .backoff,
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

            HStack(spacing: 8) {
                Button {
                    model.refreshSetupInventory()
                    setupModalOpen = true
                } label: {
                    Text("SETUP")
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

                Button {
                    inspectorPresentation.present(from: .fullConsole)
                } label: {
                    Text("INSPECTOR")
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
                        expiresAt: model.latchExpiresAt,
                        isArmed: model.isLatchArmed,
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

                    HStack(alignment: .top, spacing: 10) {
                        timelineStepChip(
                            "PRESHOW",
                            laneId: "preshow",
                            activeState: .preshow,
                            armAction: model.runPreshowTimelineStep
                        )
                        timelineStepChip(
                            "INTRO",
                            laneId: "introduction",
                            activeState: .introduction,
                            armAction: model.runIntroductionTimelineStep
                        )
                        timelineStepChip(
                            "ENDING",
                            laneId: "ending",
                            activeState: .ending,
                            armAction: model.runEndingTimelineStep
                        )
                        timelineTakeColumn
                        Spacer()
                        if let cue = model.latestCue {
                            Text("LAST CUE  \(cue.cueId)")
                                .font(ConsoleTheme.telemetryFont(size: 10))
                                .foregroundStyle(Color.white.opacity(0.4))
                            }
                    }

                    Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 2)

                    soundControlDeck
                }
            }
        }
    }

    private func timelineStepChip(
        _ label: String,
        laneId: String,
        activeState: ShowState,
        armAction: @escaping () -> Void
    ) -> some View {
        let isLocked = model.isTimelineStepLocked(laneId)
        let isArmed = model.isTimelineStepArmed(laneId)
        let isActive = model.state == activeState
        let canArm = model.canArmTimelineStep(laneId)

        let chipColor: Color = {
            if isActive { return ConsoleTheme.lampBlue }
            if isArmed { return ConsoleTheme.lampAmber }
            if isLocked { return ConsoleTheme.lampRed }
            return ConsoleTheme.lampStandby
        }()

        let statusLabel: String = {
            if isActive { return "LIVE" }
            if isArmed { return "ARMED" }
            if isLocked { return "LOCKED" }
            return "READY"
        }()

        return VStack(alignment: .leading, spacing: 5) {
            IlluminatedButton(
                label: label,
                subtitle: statusLabel.lowercased(),
                color: chipColor,
                isLit: isActive || isArmed || isLocked,
                isEnabled: canArm || isArmed,
                blinkOn: blinkOn,
                pulseWhenLit: isArmed,
                minWidth: 110,
                minHeight: 52,
                action: armAction
            )

            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                let progress = model.timelineStepProgress(for: laneId, at: timeline.date)
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.09))
                            Capsule()
                                .fill(chipColor.opacity(isActive ? 0.95 : 0.65))
                                .frame(width: max(2, geo.size.width * progress))
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int((progress * 100).rounded()))%")
                        .font(ConsoleTheme.telemetryFont(size: 8))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .frame(width: 26, alignment: .trailing)
                }
            }
            .frame(height: 10)
        }
        .frame(minWidth: 118, minHeight: 68, alignment: .topLeading)
        .opacity((isLocked && !isActive) ? 0.72 : 1.0)
    }

    private var timelineTakeColumn: some View {
        VStack(spacing: 6) {
            Text("TAKE")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.55))

            IlluminatedButton(
                label: "TAKE",
                color: ConsoleTheme.lampGreen,
                isLit: model.canTakeArmedTimelineStep(),
                isEnabled: model.canTakeArmedTimelineStep(),
                blinkOn: blinkOn,
                pulseWhenLit: true,
                minWidth: 70,
                minHeight: 78,
                action: model.takeArmedTimelineStep
            )
        }
        .frame(width: 90)
    }

    private var soundControlDeck: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CYBERNETIC SOUND LAYER")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))

            HStack(alignment: .top, spacing: 10) {
                soundModule(title: "SOUND ENGINE", accent: ConsoleTheme.lampGreen) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.audioRouteStatusSummary)
                            .font(ConsoleTheme.smallTagFont(size: 8))
                            .foregroundStyle(audioRouteColor)
                        Text("Route \(model.quadRouteChannelCount)ch")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.58))
                        Text("Bank \(model.activeSampleBank) · FX A \(model.effectsChainState.chainAActive ? "ON" : "OFF") · FX B \(model.effectsChainState.chainBActive ? "ON" : "OFF")")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text("Role \(rightStickRoleLabel) · Clutch \(model.hotasStaticVisualOverrideHeld ? "HELD" : "OFF")")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.52))
                        Text("Ultrachunk overlay \(model.hotasUltrachunkOverlayEnabled ? "ON" : "OFF")")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(model.hotasUltrachunkOverlayEnabled ? Color.white.opacity(0.64) : Color.white.opacity(0.42))
                        Text("Static m\(decimal(model.staticAudioMacroState.sampleMorph)) a\(decimal(model.staticAudioMacroState.articulation)) t\(decimal(model.staticAudioMacroState.timbre)) s\(decimal(model.staticAudioMacroState.textureSend))")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.48))
                        Text("Ultrachunk s\(decimal(model.ultrachunkControlFrame.speed)) g\(decimal(model.ultrachunkGranularity)) i\(decimal(model.ultrachunkIntensity)) twist \(model.ultrachunkDSPState.twistLane.rawValue.uppercased())")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.56))
                        Text("Active \(model.ultrachunkPrimarySampleID ?? "-") · sec \(model.ultrachunkSecondarySampleID ?? "-") · XY \(decimal(model.ultrachunkControlFrame.x))/\(decimal(model.ultrachunkControlFrame.y))")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.48))
                        HStack(spacing: 6) {
                            Button("CHECK") { model.refreshQuadRouteStatus() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Text("RMS \(Int(model.latestAudioFeatures.rms * 100))%")
                                .font(ConsoleTheme.telemetryFont(size: 9))
                                .foregroundStyle(Color.white.opacity(0.5))
                            Text("FLUX \(Int(model.latestAudioFeatures.flux * 100))%")
                                .font(ConsoleTheme.telemetryFont(size: 9))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                }

                soundModule(title: "SYNTH", accent: ConsoleTheme.lampBlue) {
                    VStack(alignment: .leading, spacing: 6) {
                        Stepper(value: $model.choirNote, in: 36 ... 96) {
                            Text("NOTE \(model.choirNote)")
                                .font(ConsoleTheme.telemetryFont(size: 9))
                                .foregroundStyle(Color.white.opacity(0.62))
                        }
                        HStack(spacing: 6) {
                            Button("NOTE ON") { model.triggerSynthNoteOn() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("NOTE OFF") { model.triggerSynthNoteOff() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }

                soundModule(title: "SAMPLES", accent: ConsoleTheme.lampAmber) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.sampleEntrySummary().uppercased())
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.62))
                        Text("Blend strict \(decimal(model.programProceduralState.strictLooseBlend)) · text p \(decimal(model.programProceduralState.textProbability))")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.5))
                        HStack(spacing: 6) {
                            Button("TRIGGER") { model.triggerSamplePlayback() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("PHONE") { model.triggerPhoneSample() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }

                soundModule(title: "PHONE CHOIR", accent: ConsoleTheme.lampRed) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.phoneAudioGateCommitted
                             ? "GATE COMMIT"
                             : (model.phoneAudioGateArmed ? "GATE ARMED" : "GATE SAFE"))
                            .font(ConsoleTheme.smallTagFont(size: 8))
                            .foregroundStyle(
                                model.phoneAudioGateCommitted
                                    ? ConsoleTheme.lampGreen
                                    : (model.phoneAudioGateArmed ? ConsoleTheme.lampAmber : Color.white.opacity(0.45))
                            )
                        Text("POOL \(model.phoneAudioAvailableDevices.count) · VOICES \(model.phoneAudioActiveVoices.count)")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.6))
                        Text("Zones \(model.phoneAudioZoneOccupancy.count) · Top \(dominantZoneLabel) · Failover \(model.phoneAudioFailoverCount) · Unhealthy \(unhealthyChoirDeviceCount)")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.52))
                        Text("Field s\(decimal(model.choirFieldState.spread)) d\(decimal(model.choirFieldState.depth)) t\(decimal(model.choirFieldState.detune)) · Ctx \(model.hotasPhoneChoirContextActive ? "ON" : "OFF")")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.52))
                        Picker("Target", selection: $model.phoneAudioTargetMode) {
                            ForEach(PhoneAudioTargetMode.allCases) { mode in
                                Text(mode.rawValue.uppercased()).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)

                        if model.phoneAudioTargetMode == .single {
                            Picker("Device", selection: $model.phoneAudioSingleTargetID) {
                                if model.phoneAudioAvailableDevices.isEmpty {
                                    Text("NO DEVICES").tag("")
                                } else {
                                    ForEach(model.phoneAudioAvailableDevices, id: \.self) { deviceID in
                                        Text(deviceID).tag(deviceID)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                        }

                        if model.phoneAudioTargetMode == .subset {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(model.phoneAudioAvailableDevices, id: \.self) { deviceID in
                                        let selected = model.phoneAudioSubsetTargetIDs.contains(deviceID)
                                        Button(deviceID) {
                                            model.togglePhoneAudioSubsetTarget(deviceID)
                                        }
                                        .buttonStyle(.plain)
                                        .font(ConsoleTheme.telemetryFont(size: 8))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(selected ? ConsoleTheme.lampBlue.opacity(0.35) : Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                            }
                        }

                        HStack(spacing: 6) {
                            Button("TAKE") { model.takePhoneAudioGate() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("GO") { model.goPhoneAudioGate() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Button("SAFE") { model.safePhoneAudioGate() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        HStack(spacing: 6) {
                            Button("NOTE ON") { model.triggerPhoneChoirNoteOn() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("OFF") { model.triggerPhoneChoirNoteOff() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("AMBI") { model.triggerPhoneAmbientNoise() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("STOP") { model.stopAllPhoneAudio() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func soundModule<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ConsoleTheme.smallTagFont(size: 8))
                .tracking(1.2)
                .foregroundStyle(accent)
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConsoleTheme.panelInnerFill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ConsoleTheme.panelStroke, lineWidth: 0.6)
        )
    }

    // MARK: - Right column: control plane + action stream + telemetry

    private var rightColumn: some View {
        VStack(spacing: 12) {
            ConsolePanel("CONTROL PLANE", accent: ConsoleTheme.lampGreen) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RIGHT STICK")
                            .font(ConsoleTheme.smallTagFont(size: 8))
                            .tracking(1.2)
                            .foregroundStyle(Color.white.opacity(0.5))
                        Spacer()
                        Text(rightStickRoleLabel)
                            .font(ConsoleTheme.smallTagFont(size: 8))
                            .tracking(1.0)
                            .foregroundStyle(rightStickRoleColor)
                    }

                    HStack {
                        Text("CLUTCH \(model.hotasStaticVisualOverrideHeld ? "HELD" : "OFF")")
                        Spacer()
                        Text("CTX \(model.hotasPhoneChoirContextActive ? "CHOIR" : "MAIN")")
                    }
                    .font(ConsoleTheme.telemetryFont(size: 9))
                    .foregroundStyle(Color.white.opacity(0.58))

                    HStack {
                        Text("BANK M\(model.activeSampleBank) / C\(model.activeChoirSampleBank)")
                        Spacer()
                        Text("FX \(model.activeEffectsPreset.chainAName)/\(model.activeEffectsPreset.chainBName)")
                    }
                    .font(ConsoleTheme.telemetryFont(size: 9))
                    .foregroundStyle(Color.white.opacity(0.58))

                    HStack {
                        Text("ULTRACHUNK \(model.hotasUltrachunkOverlayEnabled ? "ON" : "OFF")  S \(decimal(model.ultrachunkControlFrame.speed))  G \(decimal(model.ultrachunkGranularity))  I \(decimal(model.ultrachunkIntensity))")
                        Spacer()
                        Text("TWIST \(model.ultrachunkDSPState.twistLane.rawValue.uppercased())")
                    }
                    .font(ConsoleTheme.telemetryFont(size: 9))
                    .foregroundStyle(Color.white.opacity(0.62))

                    HStack {
                        Text("PRIMARY \(model.ultrachunkPrimarySampleID ?? "-")")
                        Spacer()
                        Text("SECONDARY \(model.ultrachunkSecondarySampleID ?? "-")")
                    }
                    .font(ConsoleTheme.telemetryFont(size: 8))
                    .foregroundStyle(Color.white.opacity(0.52))

                    ControlPlaneBargraphCluster(
                        values: ControlPlaneBargraphCluster.Values(
                            spatialX: model.vector.spatialX,
                            cutCadence: model.programProceduralState.cutCadence,
                            fade: model.programProceduralState.fade,
                            sampleMorph: model.staticAudioMacroState.sampleMorph,
                            articulation: model.staticAudioMacroState.articulation,
                            timbre: model.staticAudioMacroState.timbre,
                            choirSpread: model.choirFieldState.spread,
                            choirDepth: model.choirFieldState.depth,
                            choirDetune: model.choirFieldState.detune,
                            fxAIntensity: model.effectsChainState.chainAIntensity,
                            fxBIntensity: model.effectsChainState.chainBIntensity,
                            textProbability: model.programProceduralState.textProbability
                        ),
                        onSpatialX: { model.patchVector(ParamVectorPatch(spatialX: $0)) },
                        onCutCadence: { model.setCutCadenceFromControl($0) },
                        onFade: { model.setCompositorBlendFromControl($0) },
                        onSampleMorph: { model.setStaticSampleMorphFromControl($0) },
                        onArticulation: { model.setStaticArticulationFromControl($0) },
                        onTimbre: { model.setStaticTimbreFromControl($0) },
                        onChoirSpread: { model.setChoirFieldSpreadFromControl($0) },
                        onChoirDepth: { model.setChoirFieldDepthFromControl($0) },
                        onChoirDetune: { model.setChoirFieldDetuneFromControl($0) },
                        onFxA: { model.setEffectsChainFromControl(chain: .a, active: $0 > 0.05, intensity: $0) },
                        onFxB: { model.setEffectsChainFromControl(chain: .b, active: $0 > 0.05, intensity: $0) },
                        onTextProbability: { model.setTextProbabilityFromControl($0) }
                    )
                    .equatable()
                }
                .frame(maxWidth: .infinity)
            }

            ConsolePanel("ML COPILOT · ACTION STREAM", accent: ConsoleTheme.lampAmber) {
                MLActionStreamPanel(
                    snapshot: MLActionStreamPanel.Snapshot(
                        proposal: model.activeMLProposal,
                        countdownSeconds: model.activeMLProposalCountdownSeconds,
                        events: Array(model.hudTelemetryFrame.events.prefix(8))
                    ),
                    onAccept: { _ = model.acceptActiveProposalFromControl() }
                )
                .equatable()
            }

            ConsolePanel("CHOIR / AUDIENCE TELEMETRY", accent: ConsoleTheme.lampBlue) {
                TelemetryDevicePanel(
                    snapshot: TelemetryDevicePanel.Snapshot(
                        deviceCount: model.devices.count,
                        poolSize: model.phoneAudioAvailableDevices.count,
                        voiceCount: model.phoneAudioActiveVoices.count,
                        failoverCount: model.phoneAudioFailoverCount,
                        zoneCount: model.phoneAudioZoneOccupancy.count,
                        dominantZone: dominantZoneLabel,
                        unhealthyCount: unhealthyChoirDeviceCount,
                        cueLeadMs: model.cueTimingLeadMs,
                        cueCohortSize: model.cueTimingCohortSize,
                        cueCohortP95RttMs: model.cueTimingCohortP95RttMs,
                        activationSkewP50Ms: model.cueActivationSkewP50Ms,
                        activationSkewP95Ms: model.cueActivationSkewP95Ms,
                        activationMissP95Ms: model.cueActivationMissP95Ms,
                        devices: model.devices
                    ),
                    onPing: { model.refreshTelemetry() }
                )
                .equatable()
            }
        }
    }

    private var rightStickRoleLabel: String {
        if model.hotasPhoneChoirContextActive {
            return "CHOIR FIELD"
        }
        if model.effectiveOutputMode == .static {
            return model.hotasStaticVisualOverrideHeld ? "VISUAL OVERRIDE (CLUTCH)" : "ULTRACHUNK AUDIO"
        }
        if model.effectiveOutputMode == .off {
            return "ULTRACHUNK AUDIO (IDLE)"
        }
        return "ULTRACHUNK AUDIO"
    }

    private var rightStickRoleColor: Color {
        if model.hotasPhoneChoirContextActive {
            return ConsoleTheme.lampBlue
        }
        if model.effectiveOutputMode == .static {
            return model.hotasStaticVisualOverrideHeld ? ConsoleTheme.lampAmber : ConsoleTheme.lampGreen
        }
        if model.effectiveOutputMode == .dynamic {
            return ConsoleTheme.lampGreen
        }
        return Color.white.opacity(0.6)
    }

    private var unhealthyChoirDeviceCount: Int {
        model.phoneAudioDeviceHealth.values.reduce(into: 0) { result, health in
            if health.ackReliability < 0.65 || health.rttMs > 500 {
                result += 1
            }
        }
    }

    private var dominantZoneLabel: String {
        model.phoneAudioZoneOccupancy
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .first?.key ?? "-"
    }

    private func color(for severity: HUDEventSeverity) -> Color {
        switch severity {
        case .info:
            return Color.white.opacity(0.7)
        case .act:
            return ConsoleTheme.lampBlue
        case .apply:
            return ConsoleTheme.lampGreen
        case .block:
            return ConsoleTheme.lampAmber
        case .error:
            return ConsoleTheme.lampRed
        }
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - Flight log

    private var flightLogPanel: some View {
        FlightLogPanelSection(entries: model.statusLineHistory)
            .equatable()
    }

    // MARK: - Inspector drawer (preview / media / coreml / connection)

    private var inspectorDrawer: some View {
        HStack(alignment: .top, spacing: 12) {
            ConsolePanel("LINK · MEDIA", accent: ConsoleTheme.lampStandby) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WEBSOCKET")
                        .font(ConsoleTheme.smallTagFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))
                    VStack(alignment: .leading, spacing: 4) {
                        linkDiagRow("STATE", value: model.connectionStatus.uppercased())
                        linkDiagRow("URL", value: model.fixedHarnessLinkURL)
                        linkDiagRow("HEALTH", value: model.fixedHealthURL)
                        if let retryInSeconds = model.retryInSeconds, model.linkState == .backoff {
                            linkDiagRow("RETRY", value: "\(retryInSeconds)s")
                        }
                        linkDiagRow("HANDSHAKE", value: model.lastHandshakeAt.map(formatTimestamp) ?? "never")
                        if let lastLinkError = model.lastLinkError, !lastLinkError.isEmpty {
                            linkDiagRow("LAST ERR", value: lastLinkError)
                        }
                    }

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
                            Button("LOAD") { activeImportModal = .scene(scene) }
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
                        Button("LOAD") { activeImportModal = .interstitial }
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
                        Button("ADD") { activeImportModal = .fixedLane }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Text("\(model.showFixedLanes.count) LANES")
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    Text("SOUND MODULES")
                        .font(ConsoleTheme.smallTagFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))

                    HStack {
                        Text("SYNTH")
                            .font(ConsoleTheme.telemetryFont(size: 10))
                            .frame(width: 80, alignment: .leading)
                            .foregroundStyle(Color.white.opacity(0.65))
                        Button("LOAD") { activeImportModal = .synthPreset }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Text(model.synthPresetFilename())
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }

                    HStack {
                        Text("SAMPLES")
                            .font(ConsoleTheme.telemetryFont(size: 10))
                            .frame(width: 80, alignment: .leading)
                            .foregroundStyle(Color.white.opacity(0.65))
                        Button("LOAD") { activeImportModal = .samplePack }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Text(model.samplePackFilename())
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }

                    HStack {
                        Text("CHOIR")
                            .font(ConsoleTheme.telemetryFont(size: 10))
                            .frame(width: 80, alignment: .leading)
                            .foregroundStyle(Color.white.opacity(0.65))
                        Button("LOAD") { activeImportModal = .choirProfile }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Text(model.choirProfileFilename())
                            .font(ConsoleTheme.telemetryFont(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            ConsolePanel("PREVIEW MONITOR", accent: ConsoleTheme.lampAmber) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MODE \(model.effectiveOutputMode.uiLabel.uppercased())  ·  \(model.previewStatus)")
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
                        Button("IMPORT") { activeImportModal = .coreML }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("REFRESH") { model.refreshModelCatalog() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("AUTO RELOAD") { model.reloadPreferredModel() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    HStack(spacing: 6) {
                        Button("MODELS DIR…") { model.pickCoreMLSearchDirectory() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        if model.modelSearchOverridePath != nil {
                            Button("CLEAR DIR") { model.clearCoreMLSearchDirectoryOverride() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    if let overridePath = model.modelSearchOverridePath {
                        Text("OVERRIDE: \(overridePath)")
                            .font(ConsoleTheme.telemetryFont(size: 8))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !model.modelSearchPaths.isEmpty {
                        Text("SEARCH \(model.modelSearchPaths.count) PATHS · \(model.modelCandidates.count) FOUND")
                            .font(ConsoleTheme.telemetryFont(size: 8))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .lineLimit(1)
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
                label: mode.uiLabel,
                subtitle: mode == .static ? "fixed lane" : (mode == .dynamic ? "live render" : "interstitial loop"),
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

    private func linkDiagRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(ConsoleTheme.smallTagFont(size: 8))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(2)
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    // MARK: - Lamp helpers

    private var linkLampState: LampState {
        switch model.linkState {
        case .online:
            return .nominal
        case .connecting, .degraded, .backoff:
            return .caution
        case .offline:
            return .fault
        case .idle:
            return .standby
        }
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

    private var audioRouteColor: Color {
        switch model.audioRouteCapability {
        case .quad:
            return ConsoleTheme.lampGreen
        case .stereoFallback:
            return model.allowStereoFallback ? ConsoleTheme.lampAmber : ConsoleTheme.lampRed
        case .unavailable:
            return ConsoleTheme.lampRed
        }
    }
}

private struct ImportModuleSheet: View {
    let module: ImportModuleKind
    @ObservedObject var model: ConductorHarnessViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(module.title)
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.9))

            statusSection

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(primaryButtonTitle) {
                    performImport()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(minWidth: 480, minHeight: 230)
        .background(ConsoleTheme.consoleBackground)
    }

    private var primaryButtonTitle: String {
        switch module {
        case .fixedLane:
            return "Add Lane From Disk"
        case .coreML:
            return "Import .mlmodelc"
        case .synthPreset:
            return "Import Preset Pack"
        case .samplePack:
            return "Import Sample Manifest"
        case .choirProfile:
            return "Import Choir Profile"
        case .scene, .interstitial:
            return "Load From Disk"
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch module {
        case .scene(let scene):
            statusRow("Module", value: scene.rawValue.uppercased())
            statusRow(
                "Current",
                value: model.sceneMediaURLs[scene] == nil ? "none" : model.mediaFilename(for: scene)
            )
        case .interstitial:
            statusRow("Module", value: "INTERSTITIAL")
            statusRow(
                "Current",
                value: model.interstitialMediaURL == nil ? "none" : model.interstitialFilename()
            )
        case .fixedLane:
            statusRow("Module", value: "STATIC LANE BANK")
            statusRow("Current lanes", value: "\(model.showFixedLanes.count)")
        case .coreML:
            statusRow("Health", value: model.modelHealthLevel.rawValue.uppercased())
            statusRow("Summary", value: model.modelHealthSummary)
            statusRow("Selected", value: selectedModelLabel)
        case .synthPreset:
            statusRow("Module", value: "SYNTH PRESET PACK")
            statusRow("Current", value: model.synthPresetFilename())
        case .samplePack:
            statusRow("Module", value: "SAMPLE PACK MANIFEST")
            statusRow("Current", value: model.samplePackFilename())
            statusRow("Entries", value: model.sampleEntrySummary())
        case .choirProfile:
            statusRow("Module", value: "PHONE CHOIR PROFILE")
            statusRow("Current", value: model.choirProfileFilename())
        }
    }

    private var selectedModelLabel: String {
        if let selected = model.modelCandidates.first(where: { $0.id == model.selectedModelCandidateID }) {
            return selected.name
        }
        return "none"
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased())
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.48))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ConsoleTheme.panelInnerFill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
        )
    }

    private func performImport() {
        switch module {
        case .scene(let scene):
            model.importSceneMedia(for: scene)
        case .interstitial:
            model.importInterstitialMedia()
        case .fixedLane:
            model.importShowFixedLaneMedia()
        case .coreML:
            model.importModelBundleFromDisk()
        case .synthPreset:
            model.importSynthPresetPackFromDisk()
        case .samplePack:
            model.importSamplePackManifestFromDisk()
        case .choirProfile:
            model.importChoirProfileFromDisk()
        }
    }
}

private struct SetupSheet: View {
    @ObservedObject var model: ConductorHarnessViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let hotasModeBinding = Binding<ControlInputMode>(
            get: { model.hotasInputMode },
            set: { model.updateHOTASInputMode($0) }
        )

        VStack(alignment: .leading, spacing: 14) {
            Text("SYSTEM SETUP")
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 8) {
                Text("AUDIO OUTPUT")
                    .font(ConsoleTheme.smallTagFont(size: 9))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.55))

                setupMenuRow(label: "Interface", selectedValue: selectedAudioRouteName) {
                    if model.availableAudioRoutes.isEmpty {
                        Button("NO OUTPUT ROUTES") {}
                            .disabled(true)
                    } else {
                        ForEach(model.availableAudioRoutes) { route in
                            Button {
                                model.selectedAudioRouteID = route.id
                            } label: {
                                HStack(spacing: 8) {
                                    Text(model.audioRouteMenuLabel(route))
                                    if route.isSystemDefault {
                                        Text("SYSTEM")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(ConsoleTheme.lampGreen)
                                    }
                                    if route.id == model.selectedAudioRouteID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                }
                            }
                        }
                    }
                }

                setupToggleRow(
                    label: "Enable 2ch fallback when 4ch is unavailable",
                    isOn: $model.allowStereoFallback
                )

                Text(model.audioRouteStatusSummary)
                    .font(ConsoleTheme.telemetryFont(size: 10))
                    .foregroundStyle(Color.white.opacity(0.62))

                HStack(spacing: 8) {
                    setupActionButton("REFRESH AUDIO DEVICES") {
                        model.refreshSetupInventory()
                        model.refreshQuadRouteStatus()
                    }
                    setupActionButton("TEST OUTPUT", variant: .primary) {
                        model.testSelectedAudioOutput()
                    }
                }
            }
            .padding(10)
            .background(ConsoleTheme.panelInnerFill)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("MIDI INPUT")
                    .font(ConsoleTheme.smallTagFont(size: 9))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.55))

                setupMenuRow(label: "MIDI Source", selectedValue: selectedMIDIInputName) {
                    if model.availableMIDIInputs.isEmpty {
                        Button("NO MIDI INPUTS") {}
                            .disabled(true)
                    } else {
                        ForEach(model.availableMIDIInputs) { input in
                            Button(input.name) {
                                model.selectedMIDIInputID = input.id
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    setupActionButton("ARM MIDI", variant: .primary, isDisabled: model.selectedMIDIInputID.isEmpty) {
                        model.armMIDIInput()
                    }
                    setupActionButton("DISARM") {
                        model.stopMIDIInput()
                    }
                    setupActionButton("REFRESH IO") {
                        model.refreshSetupInventory()
                        model.refreshQuadRouteStatus()
                    }
                }

                Text(model.midiInputStatus)
                    .font(ConsoleTheme.telemetryFont(size: 10))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            .padding(10)
            .background(ConsoleTheme.panelInnerFill)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("HOTAS CONTROL")
                    .font(ConsoleTheme.smallTagFont(size: 9))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.55))

                setupSegmentedModeControl(selection: hotasModeBinding)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.hotasInputStatus)
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text("Profile: \(model.hotasProfileName)")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.58))
                    Text(model.hotasMissingRequiredRoles.isEmpty
                         ? "Required bindings: READY"
                         : "Required bindings missing: \(model.hotasMissingRequiredRoles.count)")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(model.hotasMissingRequiredRoles.isEmpty ? ConsoleTheme.lampGreen : ConsoleTheme.lampAmber)
                    Text(model.hotasBindingConflicts.isEmpty
                         ? "Binding conflicts: none"
                         : "Binding conflicts: \(model.hotasBindingConflicts.count)")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(model.hotasBindingConflicts.isEmpty ? Color.white.opacity(0.52) : ConsoleTheme.lampAmber)
                    Text("Sample banks — Main: \(model.activeSampleBank) / Choir: \(model.activeChoirSampleBank)")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Text(model.hotasLastSignalSummary)
                        .font(ConsoleTheme.telemetryFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(2)
                }

                setupToggleRow(
                    label: "Allow HOTAS vector override while STATIC video output is active",
                    isOn: Binding(
                        get: { model.hotasStaticVideoOverrideEnabled },
                        set: { model.updateHOTASStaticVideoOverride($0) }
                    )
                )

                HStack(spacing: 8) {
                    setupActionButton("TRAIN / MAP", variant: .primary) {
                        openWindow(id: AppWindowID.hotasMapper.rawValue)
                    }

                    setupActionButton("DISABLE HOTAS") {
                        model.disableHOTASControls()
                    }

                    setupActionButton("REVERT LAST GOOD") {
                        model.revertHOTASToLastKnownGood()
                    }
                }
            }
            .padding(10)
            .background(ConsoleTheme.panelInnerFill)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("PUSH COMPANION")
                    .font(ConsoleTheme.smallTagFont(size: 9))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.55))

                setupToggleRow(
                    label: "Enable Push Control lane (non-commit actions only)",
                    isOn: Binding(
                        get: { model.pushControlEnabled },
                        set: { model.updatePushControlEnabled($0) }
                    )
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.pushControlEnabled ? "Push lane ON" : "Push lane OFF")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(model.pushControlEnabled ? ConsoleTheme.lampGreen : Color.white.opacity(0.62))
                    Text("Trusted controllers: \(model.pushTrustedControllerIDs.count)")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.58))
                    Text(model.pushLastSignalSummary)
                        .font(ConsoleTheme.telemetryFont(size: 9))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(2)
                }

                Text("Recently Seen Controllers")
                    .font(ConsoleTheme.smallTagFont(size: 8))
                    .foregroundStyle(Color.white.opacity(0.52))

                if model.pushRecentControllerIDs.isEmpty {
                    Text("No Push controllers seen yet.")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.5))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.pushRecentControllerIDs, id: \.self) { controllerID in
                            HStack(spacing: 8) {
                                Text(controllerID)
                                    .font(ConsoleTheme.telemetryFont(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.72))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                let trusted = model.isPushControllerTrusted(controllerID)
                                setupActionButton(trusted ? "UNTRUST" : "TRUST", variant: trusted ? .normal : .primary) {
                                    model.setPushControllerTrusted(controllerID, trusted: !trusted)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ConsoleTheme.panelStroke, lineWidth: 0.6)
                            )
                        }
                    }
                }
            }
            .padding(10)
            .background(ConsoleTheme.panelInnerFill)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
            )

            Spacer(minLength: 0)

            HStack {
                setupActionButton("Close") {
                    dismiss()
                }

                Spacer()

                setupActionButton("Apply Setup", variant: .primary) {
                    model.applySetupConfiguration()
                    dismiss()
                }
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 520)
        .background(ConsoleTheme.consoleBackground)
        .onAppear {
            model.refreshSetupInventory()
            model.refreshQuadRouteStatus()
        }
    }

    private var selectedAudioRouteName: String {
        model.selectedAudioRouteDisplayName
    }

    private var selectedMIDIInputName: String {
        model.selectedMIDIInputDisplayName
    }

    @ViewBuilder
    private func setupMenuRow<Content: View>(
        label: String,
        selectedValue: String,
        @ViewBuilder menuContent: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(width: 84, alignment: .leading)

            Menu {
                menuContent()
            } label: {
                HStack(spacing: 8) {
                    Text(selectedValue)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ConsoleTheme.lampBlue.opacity(0.95))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func setupToggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.74))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isOn.wrappedValue.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 11)
                    .fill(isOn.wrappedValue ? ConsoleTheme.lampBlue.opacity(0.72) : Color.white.opacity(0.14))
                    .frame(width: 44, height: 24)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white.opacity(0.94))
                            .frame(width: 18, height: 18)
                            .padding(3)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func setupSegmentedModeControl(selection: Binding<ControlInputMode>) -> some View {
        HStack(spacing: 0) {
            ForEach(ControlInputMode.allCases, id: \.self) { mode in
                Button {
                    selection.wrappedValue = mode
                } label: {
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(selection.wrappedValue == mode ? 0.95 : 0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selection.wrappedValue == mode ? ConsoleTheme.lampBlue.opacity(0.34) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
        )
    }

    private enum SetupActionVariant {
        case normal
        case primary
    }

    private func setupActionButton(
        _ title: String,
        variant: SetupActionVariant = .normal,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(Color.white.opacity(isDisabled ? 0.44 : 0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Group {
                        if variant == .primary {
                            ConsoleTheme.lampBlue.opacity(isDisabled ? 0.20 : 0.56)
                        } else {
                            Color.white.opacity(0.12)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
