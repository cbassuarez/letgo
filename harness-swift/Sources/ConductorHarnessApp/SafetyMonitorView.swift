import AppKit
import Foundation
import SwiftUI

struct SafetyMonitorView: View {
    @ObservedObject var model: ConductorHarnessViewModel
    @ObservedObject var performanceMode: PerformanceModeState
    @ObservedObject var displayCoordinator: VufineDisplayCoordinator
    @ObservedObject var videoOutDisplayCoordinator: VideoOutDisplayCoordinator
    @ObservedObject var inspectorPresentation: InspectorPresentationState

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var pendingSoundImport: SoundImportKind?

    private enum SoundImportKind: String, Identifiable {
        case samplePack = "Sample Pack"
        case choirProfile = "Choir Profile"
        case synthPreset = "Synth Preset"

        var id: String { rawValue }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: {
                inspectorPresentation.isPresented && inspectorPresentation.source == .safety
            },
            set: { isPresented in
                if isPresented {
                    inspectorPresentation.present(from: .safety)
                } else {
                    inspectorPresentation.dismiss()
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topBar

            Text("PERFORMANCE SAFETY MONITOR")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.88))

            SoundSpineCompactView(snapshot: model.soundSituationalSnapshot)

            Group {
                statusLine("Vufine", displayCoordinator.route.summary)
                statusLine("Video Out", videoOutDisplayCoordinator.route.summary)
                statusLine("Link", model.connectionStatus)
                statusLine("Engine", model.engineRunning ? "RUNNING" : "STOPPED")
                statusLine("Arm", model.masterArmKey == .armed ? "ARMED" : "SAFE")
                statusLine("Latch", model.latchSummary)
                statusLine("Route", model.audioRouteStatusSummary)
                statusLine(
                    "Ultrachunk",
                    "\(model.hotasUltrachunkOverlayEnabled ? "ON" : "OFF") · S \(decimal(model.ultrachunkControlFrame.speed)) · G \(decimal(model.ultrachunkGranularity)) · I \(decimal(model.ultrachunkIntensity)) · \(model.ultrachunkDSPState.twistLane.rawValue.uppercased()) · \(model.ultrachunkPrimarySampleID ?? "-")"
                )
                statusLine("Last", "[\(model.statusLineTimestamp)] \(model.statusLineEvent.message)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ACTION FEED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.56))
                ForEach(model.hudTelemetryFrame.events.prefix(4)) { event in
                    HStack(spacing: 8) {
                        Text(event.severity.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(severityColor(event.severity))
                            .frame(width: 44, alignment: .leading)
                        Text(event.stage.rawValue.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .frame(width: 58, alignment: .leading)
                        Text(event.blockReason ?? event.semanticAction ?? event.detail ?? event.outcome)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .lineLimit(1)
                    }
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
            )

            HStack(spacing: 8) {
                Button("MASTER SAFE") {
                    model.setMasterArmFromControl(false)
                }
                .buttonStyle(.borderedProminent)

                Button(model.abortCoverOpen ? "ABORT NOW" : "LIFT ABORT COVER") {
                    if model.abortCoverOpen {
                        model.commitAbort()
                    } else {
                        model.openAbortCover()
                    }
                }
                .buttonStyle(.bordered)

                Button("ENGINE STOP") {
                    model.stopEngine()
                }
                .buttonStyle(.bordered)

                Menu("IMPORT SOUND") {
                    Button("Sample Pack…") {
                        pendingSoundImport = .samplePack
                    }
                    Button("Choir Profile…") {
                        pendingSoundImport = .choirProfile
                    }
                    Button("Synth Preset…") {
                        pendingSoundImport = .synthPreset
                    }
                }
                .menuStyle(.borderlessButton)

                Spacer(minLength: 0)

                Button("INSPECTOR") {
                    inspectorPresentation.present(from: .safety)
                }
                .buttonStyle(.bordered)

                Button("HOTAS MAPPER") {
                    openWindow(id: AppWindowID.hotasMapper.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)

                Button("OPEN FULL CONSOLE") {
                    openWindow(id: AppWindowID.fullConsole.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)

                Button("OPEN VUFINE") {
                    openWindow(id: AppWindowID.vufineRealtime.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)

                Button("OPEN VIDEO OUT") {
                    openVideoOutWindowAndRoute()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(minWidth: 720, minHeight: 300)
        .background(Color.black.opacity(0.94))
        .preferredColorScheme(.dark)
        .overlay {
            WindowAccessor { window in
                WindowChromeCoordinator.applyChromelessHUD(to: window, isResizable: false)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            inspectorPresentation.markActive(.safety)
        }
        .sheet(isPresented: inspectorBinding) {
            InspectorModalView(model: model, presentation: inspectorPresentation)
        }
        .confirmationDialog(
            "Confirm Sound Import",
            isPresented: Binding(
                get: { pendingSoundImport != nil },
                set: { presented in
                    if !presented {
                        pendingSoundImport = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingSoundImport {
                Button("Import \(pendingSoundImport.rawValue)") {
                    runSoundImport(pendingSoundImport)
                    self.pendingSoundImport = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSoundImport = nil
            }
        } message: {
            if let pendingSoundImport {
                Text("Load \(pendingSoundImport.rawValue) from disk now?")
            }
        }
    }

    private func statusLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.56))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
        }
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("LIVE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text("Mac Safety Window")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))

            Spacer(minLength: 0)

            Button("INSPECTOR") {
                inspectorPresentation.present(from: .safety)
            }
            .buttonStyle(.bordered)

            Button("HOTAS MAPPER") {
                openWindow(id: AppWindowID.hotasMapper.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)

            Button("VUFINE VIEW") {
                apply(performanceMode.transitionToLayout(.safetyAndVufine))
            }
            .buttonStyle(.bordered)

            Button("VIDEO OUT") {
                openVideoOutWindowAndRoute()
            }
            .buttonStyle(.bordered)

            Button("MAC ONLY") {
                apply(performanceMode.transitionToLayout(.safetyOnly))
            }
            .buttonStyle(.bordered)

            Menu("MENU") {
                Button("Open Inspector") {
                    inspectorPresentation.present(from: .safety)
                }
                Button("Startup Chooser") {
                    apply(performanceMode.reopenStartupChooserTransition())
                }
                Button("Open Full Console") {
                    openWindow(id: AppWindowID.fullConsole.rawValue)
                }
                Button("Open HOTAS Mapper Studio") {
                    openWindow(id: AppWindowID.hotasMapper.rawValue)
                }
                Button("Open Vufine Realtime") {
                    openWindow(id: AppWindowID.vufineRealtime.rawValue)
                }
                Button("Open Video Out") {
                    openVideoOutWindowAndRoute()
                }
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func severityColor(_ severity: HUDEventSeverity) -> Color {
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

    private func apply(_ transition: PerformanceWindowTransition) {
        for id in transition.close {
            dismissWindow(id: id.rawValue)
        }
        for id in transition.open {
            openWindow(id: id.rawValue)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openVideoOutWindowAndRoute() {
        openWindow(id: AppWindowID.videoOut.rawValue)
        DispatchQueue.main.async {
            videoOutDisplayCoordinator.refreshPlacement(avoidingScreenID: displayCoordinator.activeScreenID)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func runSoundImport(_ kind: SoundImportKind) {
        switch kind {
        case .samplePack:
            model.importSamplePackManifestFromDisk()
        case .choirProfile:
            model.importChoirProfileFromDisk()
        case .synthPreset:
            model.importSynthPresetPackFromDisk()
        }
    }
}
