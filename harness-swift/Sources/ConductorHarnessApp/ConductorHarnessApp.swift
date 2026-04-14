import AppKit
import SwiftUI

@main
struct ConductorHarnessApp: App {
    @StateObject private var model = ConductorHarnessViewModel()
    @StateObject private var performanceMode = PerformanceModeState(mode: .performancePrimary)
    @StateObject private var vufineDisplayCoordinator = VufineDisplayCoordinator()
    @StateObject private var inspectorPresentation = InspectorPresentationState()

    var body: some Scene {
        WindowGroup("Performance Launch", id: AppWindowID.launchGate.rawValue) {
            PerformanceLaunchView(
                performanceMode: performanceMode,
                displayCoordinator: vufineDisplayCoordinator
            )
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            PerformanceModeCommands(
                performanceMode: performanceMode,
                inspectorPresentation: inspectorPresentation
            )
        }

        WindowGroup("Safety Monitor", id: AppWindowID.safetyMonitor.rawValue) {
            SafetyMonitorView(
                model: model,
                performanceMode: performanceMode,
                displayCoordinator: vufineDisplayCoordinator,
                inspectorPresentation: inspectorPresentation
            )
        }
        .windowResizability(.contentSize)

        WindowGroup("Vufine Realtime", id: AppWindowID.vufineRealtime.rawValue) {
            VufineRealtimeView(
                model: model,
                performanceMode: performanceMode,
                displayCoordinator: vufineDisplayCoordinator,
                inspectorPresentation: inspectorPresentation
            )
        }
        .windowResizability(.contentSize)

        WindowGroup("Conductor Harness", id: AppWindowID.fullConsole.rawValue) {
            ConductorSurfaceView(
                model: model,
                inspectorPresentation: inspectorPresentation
            )
        }
        .windowResizability(.contentSize)
    }
}

private struct PerformanceModeCommands: Commands {
    let performanceMode: PerformanceModeState
    let inspectorPresentation: InspectorPresentationState

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        CommandMenu("Performance") {
            Button("Show Startup Chooser") {
                apply(performanceMode.reopenStartupChooserTransition())
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])

            Button("Start Safety View") {
                apply(performanceMode.transitionToLayout(.safetyOnly))
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])

            Button("Start Vufine View") {
                apply(performanceMode.transitionToLayout(.safetyAndVufine))
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])

            Button("Open Full Console") {
                openWindow(id: AppWindowID.fullConsole.rawValue)
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Inspector") {
                let source = inspectorPresentation.lastActiveSource
                switch source {
                case .fullConsole:
                    openWindow(id: AppWindowID.fullConsole.rawValue)
                case .vufine:
                    openWindow(id: AppWindowID.vufineRealtime.rawValue)
                case .safety:
                    openWindow(id: AppWindowID.safetyMonitor.rawValue)
                }
                inspectorPresentation.present(from: source)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("i", modifiers: [.command])
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
