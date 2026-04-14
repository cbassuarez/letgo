import AppKit
import SwiftUI

struct PerformanceLaunchView: View {
    @ObservedObject var performanceMode: PerformanceModeState
    @ObservedObject var displayCoordinator: VufineDisplayCoordinator

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var externalDisplayAvailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Performance Launch")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text("Is Vufine+ connected right now?")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Text(externalDisplayAvailable
                 ? "External display detected. You can start directly in Vufine realtime mode."
                 : "No external display detected. You can still open Vufine mode later from the menu or safety monitor.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(externalDisplayAvailable ? "Yes, Vufine Connected (Recommended)" : "Yes, Vufine Connected") {
                    applyStartupSelection(hasConnectedVufine: true)
                }
                .buttonStyle(.borderedProminent)

                Button("No, Start Safety View") {
                    applyStartupSelection(hasConnectedVufine: false)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Open Full Console") {
                    openWindow(id: AppWindowID.fullConsole.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)

                Button("Cancel") {
                    dismissWindow(id: AppWindowID.launchGate.rawValue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 220)
        .task {
            externalDisplayAvailable = displayCoordinator.externalDisplayCurrentlyAvailable()
        }
        .overlay {
            WindowAccessor { window in
                WindowChromeCoordinator.applyChromelessHUD(to: window, isResizable: false)
            }
            .allowsHitTesting(false)
        }
    }

    private func applyStartupSelection(hasConnectedVufine: Bool) {
        apply(performanceMode.transitionForStartupSelection(hasConnectedVufine: hasConnectedVufine))
        dismissWindow(id: AppWindowID.launchGate.rawValue)
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
