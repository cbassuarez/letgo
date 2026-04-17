import AppKit
import Foundation
import SwiftUI

@main
struct ConductorHarnessApp: App {
    @StateObject private var model = ConductorHarnessViewModel()
    @StateObject private var performanceMode = PerformanceModeState(mode: .performancePrimary)
    @StateObject private var vufineDisplayCoordinator = VufineDisplayCoordinator()
    @StateObject private var videoOutDisplayCoordinator = VideoOutDisplayCoordinator()
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
                vufineDisplayCoordinator: vufineDisplayCoordinator,
                videoOutDisplayCoordinator: videoOutDisplayCoordinator,
                inspectorPresentation: inspectorPresentation
            )
        }

        WindowGroup("Safety Monitor", id: AppWindowID.safetyMonitor.rawValue) {
            SafetyMonitorView(
                model: model,
                performanceMode: performanceMode,
                displayCoordinator: vufineDisplayCoordinator,
                videoOutDisplayCoordinator: videoOutDisplayCoordinator,
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
        .windowResizability(.automatic)
        .defaultSize(width: 1280, height: 720)

        WindowGroup("Video Out", id: AppWindowID.videoOut.rawValue) {
            VideoOutView(
                model: model,
                displayCoordinator: videoOutDisplayCoordinator,
                vufineDisplayCoordinator: vufineDisplayCoordinator
            )
        }
        .windowResizability(.automatic)
        .defaultSize(width: 1280, height: 720)

        WindowGroup("Conductor Harness", id: AppWindowID.fullConsole.rawValue) {
            ConductorSurfaceView(
                model: model,
                inspectorPresentation: inspectorPresentation
            )
        }
        .windowResizability(.contentSize)

        WindowGroup("HOTAS Mapper Studio", id: AppWindowID.hotasMapper.rawValue) {
            HOTASMapperStudioView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

private struct PerformanceModeCommands: Commands {
    let performanceMode: PerformanceModeState
    let vufineDisplayCoordinator: VufineDisplayCoordinator
    let videoOutDisplayCoordinator: VideoOutDisplayCoordinator
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

            Button("Open Video Out Window") {
                openVideoOutWindowAndRoute()
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])
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

            Button("HOTAS Mapper Studio") {
                openWindow(id: AppWindowID.hotasMapper.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Button("Route Vufine To Preferred Display") {
                vufineDisplayCoordinator.refreshPlacement()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Button("Route Video Out To House Display") {
                openVideoOutWindowAndRoute()
            }
            .keyboardShortcut("h", modifiers: [.command, .option])

            Button("Toggle Video Out Full Screen") {
                videoOutDisplayCoordinator.toggleFullScreen()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
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
            videoOutDisplayCoordinator.refreshPlacement(avoidingScreenID: vufineDisplayCoordinator.activeScreenID)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
