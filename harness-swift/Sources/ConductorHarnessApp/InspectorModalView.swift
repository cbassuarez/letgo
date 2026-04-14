import ConductorCore
import SwiftUI

struct InspectorModalView: View {
    @ObservedObject var model: ConductorHarnessViewModel
    @ObservedObject var presentation: InspectorPresentationState

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            header

            TabView(selection: $presentation.selectedTab) {
                linkTab
                    .tabItem { Text("Link") }
                    .tag(InspectorModalTab.link)

                mediaTab
                    .tabItem { Text("Media") }
                    .tag(InspectorModalTab.media)

                coreMLTab
                    .tabItem { Text("CoreML") }
                    .tag(InspectorModalTab.coreML)

                controlsTab
                    .tabItem { Text("Controls") }
                    .tag(InspectorModalTab.controls)

                hudDebugTab
                    .tabItem { Text("HUD Debug") }
                    .tag(InspectorModalTab.hudDebug)

                actionStreamTab
                    .tabItem { Text("Action Stream") }
                    .tag(InspectorModalTab.actionStream)
            }
            .tabViewStyle(.automatic)

            HStack {
                Button("Close") {
                    presentation.dismiss()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Text("\(presentation.source.title) · ⌘I")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 640)
        .background(Color.black.opacity(0.94))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("INSPECTOR")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Global Modal · \(presentation.source.title)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            Spacer(minLength: 0)

            Text("Live feed: \(model.hudTelemetryFrame.events.count) events")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.62))
        }
    }

    private var linkTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                inspectorSection("WEBSOCKET") {
                    inspectorRow("State", model.connectionStatus)
                    inspectorRow("Link", model.fixedHarnessLinkURL)
                    inspectorRow("Health", model.fixedHealthURL)
                    inspectorRow("Retry", model.retryInSeconds.map { "\($0)s" } ?? "-")
                    inspectorRow("Last Error", model.lastLinkError ?? "none")
                    inspectorRow("Handshake", model.lastHandshakeAt.map(formatTimestamp) ?? "never")
                }

                inspectorSection("SAFETY") {
                    inspectorRow("Engine", model.engineRunning ? "RUNNING" : "STOPPED")
                    inspectorRow("Master Arm", model.masterArmKey == .armed ? "ARMED" : "SAFE")
                    inspectorRow("Latch", model.latchSummary)
                    inspectorRow("Route", model.audioRouteStatusSummary)
                    inspectorRow("GO Ready", model.canFireWithMasterArm ? "YES" : "NO")
                }

                inspectorSection("STATUS") {
                    inspectorRow("Current", "[\(model.statusLineTimestamp)] \(model.statusLineEvent.severity.rawValue.uppercased()) \(model.statusLineEvent.message)")
                    ForEach(
                        Array(model.statusLineHistory.suffix(12).reversed()),
                        id: \.timestamp
                    ) { event in
                        Text("[\(formatTimestamp(event.timestamp))] \(event.severity.rawValue.uppercased()) \(event.message)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var mediaTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                inspectorSection("SCENE MEDIA") {
                    mediaActionRow(label: "Preshow", value: model.mediaFilename(for: .preshow)) {
                        model.importSceneMedia(for: .preshow)
                    }
                    mediaActionRow(label: "Introduction", value: model.mediaFilename(for: .introduction)) {
                        model.importSceneMedia(for: .introduction)
                    }
                    mediaActionRow(label: "Ending", value: model.mediaFilename(for: .ending)) {
                        model.importSceneMedia(for: .ending)
                    }
                    mediaActionRow(label: "Interstitial", value: model.interstitialFilename()) {
                        model.importInterstitialMedia()
                    }
                    mediaActionRow(label: "Static Lane +", value: "\(model.showFixedLanes.count) lanes") {
                        model.importShowFixedLaneMedia()
                    }
                }

                inspectorSection("SOUND MODULES") {
                    mediaActionRow(label: "Synth Preset", value: model.synthPresetFilename()) {
                        model.importSynthPresetPackFromDisk()
                    }
                    mediaActionRow(label: "Sample Pack", value: model.samplePackFilename()) {
                        model.importSamplePackManifestFromDisk()
                    }
                    mediaActionRow(label: "Choir Profile", value: model.choirProfileFilename()) {
                        model.importChoirProfileFromDisk()
                    }
                }

                inspectorSection("DYNAMIC BIN") {
                    inspectorRow("Clip Count", "\(model.dynamicBinManifest.count)")
                    ForEach(model.dynamicBinManifest.prefix(16)) { clip in
                        Text("\(clip.id) · \(clip.mediaRef)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var coreMLTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                inspectorSection("RUNTIME") {
                    inspectorRow("Health", model.modelHealthLevel.rawValue.uppercased())
                    inspectorRow("Summary", model.modelHealthSummary)
                    inspectorRow("Failures", "\(model.modelRuntimeFailures)")
                    HStack(spacing: 8) {
                        Button("Refresh Catalog") {
                            model.refreshModelCatalog()
                        }
                        .buttonStyle(.bordered)

                        Button("Reload Preferred") {
                            model.reloadPreferredModel()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                inspectorSection("CANDIDATES") {
                    if model.modelCandidates.isEmpty {
                        Text("No compiled models detected.")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.58))
                    } else {
                        ForEach(model.modelCandidates) { candidate in
                            HStack(spacing: 8) {
                                Text(candidate.name)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.8))
                                Spacer(minLength: 0)
                                Button("Load") {
                                    model.selectedModelCandidateID = candidate.id
                                    model.loadSelectedModelBundle()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var controlsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                inspectorSection("INPUT MODES") {
                    let rightRole: String = {
                        if model.hotasPhoneChoirContextActive {
                            return "CHOIR FIELD"
                        }
                        if model.effectiveOutputMode == .static {
                            return model.hotasStaticVisualOverrideHeld ? "VISUAL OVERRIDE (CLUTCH)" : "AUDIO MACRO"
                        }
                        if model.effectiveOutputMode == .dynamic {
                            return "DYNAMIC VIDEO"
                        }
                        return "VECTOR PATCH"
                    }()
                    inspectorRow("MIDI", model.midiInputStatus)
                    inspectorRow("HOTAS", model.hotasInputStatus)
                    inspectorRow("Right Stick Role", rightRole)
                    inspectorRow("Clutch", model.hotasStaticVisualOverrideHeld ? "HELD" : "OFF")
                    inspectorRow("Profile", model.hotasProfileName)
                    inspectorRow("Last Signal", model.hotasLastSignalSummary)
                    inspectorRow("Missing Required", model.hotasMissingRequiredRoles.isEmpty ? "none" : model.hotasMissingRequiredRoles.map(\.rawValue).joined(separator: ", "))
                    inspectorRow("Conflicts", model.hotasBindingConflicts.isEmpty ? "none" : model.hotasBindingConflicts.joined(separator: " | "))
                }

                inspectorSection("PHONE CHOIR ALLOCATOR") {
                    let zoneSummary = model.phoneAudioZoneOccupancy.isEmpty
                        ? "none"
                        : model.phoneAudioZoneOccupancy
                            .sorted { lhs, rhs in
                                if lhs.value == rhs.value {
                                    return lhs.key < rhs.key
                                }
                                return lhs.value > rhs.value
                            }
                            .map { "\($0.key):\($0.value)" }
                            .joined(separator: "  ")
                    let unhealthy = model.phoneAudioDeviceHealth.values.filter { device in
                        device.ackReliability < 0.65 || device.rttMs > 500
                    }.count
                    inspectorRow("Pool Devices", "\(model.phoneAudioAvailableDevices.count)")
                    inspectorRow("Active Voices", "\(model.phoneAudioActiveVoices.count)")
                    inspectorRow("Failovers", "\(model.phoneAudioFailoverCount)")
                    inspectorRow("Zones", zoneSummary)
                    inspectorRow("Unhealthy", "\(unhealthy)")

                    if model.phoneAudioDeviceHealth.isEmpty {
                        Text("No device health samples yet.")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.58))
                    } else {
                        ForEach(model.phoneAudioDeviceHealth.keys.sorted(), id: \.self) { hashedId in
                            if let health = model.phoneAudioDeviceHealth[hashedId] {
                                let reliability = Int((health.ackReliability * 100).rounded())
                                Text("\(hashedId) · rtt \(Int(health.rttMs))ms · drift \(Int(health.driftMs))ms · ack \(reliability)%")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                inspectorSection("HOTAS PROFILE") {
                    HStack(spacing: 8) {
                        Button("Train / Map") {
                            model.beginHOTASTraining()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Disable HOTAS") {
                            model.disableHOTASControls()
                        }
                        .buttonStyle(.bordered)

                        Button("Revert Last Good") {
                            model.revertHOTASToLastKnownGood()
                        }
                        .buttonStyle(.bordered)
                    }

                    ForEach(model.hotasProfileBindings.prefix(24)) { binding in
                        let source = binding.sourceDeviceID ?? "any-device"
                        Text("\(binding.role.rawValue) → \(binding.controlID) [\(binding.sourceKind?.rawValue ?? "any") @ \(source)]")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                inspectorSection("ML COPILOT") {
                    if let proposal = model.activeMLProposal {
                        inspectorRow("Lane", proposal.lane.rawValue.uppercased())
                        inspectorRow("Confidence", String(format: "%.2f", proposal.confidence))
                        inspectorRow("Window", String(format: "%.1fs", model.activeMLProposalCountdownSeconds ?? 0))
                        inspectorRow("Rationale", proposal.rationale)
                        inspectorRow("Expected", proposal.expectedEffect)
                    } else {
                        inspectorRow("Active", "none")
                    }
                    inspectorRow("Need", String(format: "%.2f", model.stateDevelopmentMetrics.interventionNeedScore))
                    inspectorRow("SDI", String(format: "%.2f", model.stateDevelopmentMetrics.stateDevelopmentIndex))
                    inspectorRow("Repeatability", String(format: "%.2f", model.stateDevelopmentMetrics.repeatability))
                    inspectorRow("Intensity", String(format: "%.2f", model.stateDevelopmentMetrics.intensityTrend))
                    inspectorRow("NoveltySat", String(format: "%.2f", model.stateDevelopmentMetrics.noveltySaturation))
                    inspectorRow("Headroom", String(format: "%.2f", model.stateDevelopmentMetrics.headroom))
                    inspectorRow("Safety", String(format: "%.2f", model.stateDevelopmentMetrics.safetyContext))
                    inspectorRow("Last Decision", model.lastMLProposalDecision?.rawValue.uppercased() ?? "-")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var hudDebugTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                inspectorSection("HUD SNAPSHOT") {
                    let snapshot = model.vufineHUDSnapshot
                    inspectorRow("State", snapshot.stateLine)
                    inspectorRow("Transport", snapshot.transportLine)
                    inspectorRow("Safety", snapshot.safetyLine)
                    inspectorRow("Procedural", snapshot.proceduralLine)
                    inspectorRow("Text", snapshot.textBlendLine)
                    inspectorRow("Vector", snapshot.vectorLine)
                    inspectorRow("Audio", snapshot.audioLine)
                    inspectorRow("Proposal", snapshot.proposalLine)
                    inspectorRow("Audio Ops", snapshot.audioStateLine)
                }

                inspectorSection("ANALOG GAUGES") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(model.vufineHUDSnapshot.dynamicGauges) { gauge in
                            HUDNeedleGaugeView(descriptor: gauge)
                        }
                    }
                }

                inspectorSection("TRACE IDS") {
                    ForEach(model.hudTelemetryFrame.traces.prefix(20)) { trace in
                        inspectorRow(trace.id, String(format: "%.2f (%d)", trace.latest, trace.values.count))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var actionStreamTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(model.hudTelemetryFrame.events.prefix(240)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortTimestamp(event.timestamp))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.52))
                            .frame(width: 72, alignment: .leading)

                        Text(event.severity.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(color(for: event.severity))
                            .frame(width: 44, alignment: .leading)

                        Text(event.stage.rawValue.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.66))
                            .frame(width: 62, alignment: .leading)

                        Text(event.controlID)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.84))
                            .frame(width: 132, alignment: .leading)

                        Text(event.semanticAction ?? "-")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .frame(width: 180, alignment: .leading)

                        Text(event.blockReason ?? event.detail ?? event.outcome)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.55))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
        )
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 138, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
    }

    private func mediaActionRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.58))
                .frame(width: 132, alignment: .leading)

            Button("Load") {
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    private func shortTimestamp(_ timestamp: TimeInterval) -> String {
        Date(timeIntervalSince1970: timestamp)
            .formatted(date: .omitted, time: .standard)
    }

    private func color(for severity: HUDEventSeverity) -> Color {
        switch severity {
        case .info:
            return Color.white.opacity(0.7)
        case .act:
            return Color(red: 0.35, green: 0.89, blue: 1.0)
        case .apply:
            return Color(red: 0.43, green: 1.0, blue: 0.53)
        case .block:
            return Color(red: 1.0, green: 0.80, blue: 0.3)
        case .error:
            return Color(red: 1.0, green: 0.38, blue: 0.38)
        }
    }
}
