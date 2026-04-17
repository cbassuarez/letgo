import Foundation
import SwiftUI

enum AppWindowID: String, CaseIterable, Sendable {
    case launchGate = "launch-gate"
    case safetyMonitor = "safety-monitor"
    case vufineRealtime = "vufine-realtime"
    case videoOut = "video-out"
    case fullConsole = "full-console"
    case hotasMapper = "hotas-mapper"
}

enum AppPresentationMode: String, Sendable {
    case performancePrimary
}

enum PerformanceWindowLayout: String, Equatable, Sendable {
    case safetyOnly
    case safetyAndVufine
}

struct PerformanceWindowTransition: Equatable, Sendable {
    let open: [AppWindowID]
    let close: [AppWindowID]
}

@MainActor
final class PerformanceModeState: ObservableObject {
    @Published private(set) var mode: AppPresentationMode
    @Published private(set) var activeLayout: PerformanceWindowLayout = .safetyOnly
    @Published private(set) var vufineSelectedAtLaunch = false

    init(mode: AppPresentationMode = .performancePrimary) {
        self.mode = mode
    }

    func transitionForStartupSelection(hasConnectedVufine: Bool) -> PerformanceWindowTransition {
        vufineSelectedAtLaunch = hasConnectedVufine
        return transitionToLayout(hasConnectedVufine ? .safetyAndVufine : .safetyOnly)
    }

    func transitionToLayout(_ layout: PerformanceWindowLayout) -> PerformanceWindowTransition {
        activeLayout = layout
        switch layout {
        case .safetyOnly:
            return PerformanceWindowTransition(open: [.safetyMonitor], close: [.vufineRealtime])
        case .safetyAndVufine:
            return PerformanceWindowTransition(open: [.safetyMonitor, .vufineRealtime], close: [])
        }
    }

    func reopenStartupChooserTransition() -> PerformanceWindowTransition {
        PerformanceWindowTransition(open: [.launchGate], close: [])
    }
}
