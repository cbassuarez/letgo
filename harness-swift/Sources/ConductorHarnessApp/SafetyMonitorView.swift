import AppKit
import SwiftUI

struct SafetyMonitorView: View {
    @ObservedObject var model: ConductorHarnessViewModel
    @ObservedObject var performanceMode: PerformanceModeState
    @ObservedObject var displayCoordinator: VufineDisplayCoordinator
    @ObservedObject var inspectorPresentation: InspectorPresentationState

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

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

            Group {
                statusLine("Vufine", displayCoordinator.route.summary)
                statusLine("Link", model.connectionStatus)
                statusLine("Engine", model.engineRunning ? "RUNNING" : "STOPPED")
                statusLine("Arm", model.masterArmKey == .armed ? "ARMED" : "SAFE")
                statusLine("Latch", model.latchSummary)
                statusLine("Route", model.audioRouteStatusSummary)
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

                Spacer(minLength: 0)

                Button("INSPECTOR") {
                    inspectorPresentation.present(from: .safety)
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

            Button("VUFINE VIEW") {
                apply(performanceMode.transitionToLayout(.safetyAndVufine))
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
                Button("Open Vufine Realtime") {
                    openWindow(id: AppWindowID.vufineRealtime.rawValue)
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
}
