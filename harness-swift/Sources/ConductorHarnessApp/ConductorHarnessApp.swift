import SwiftUI

@main
struct ConductorHarnessApp: App {
    @StateObject private var model = ConductorHarnessViewModel()

    var body: some Scene {
        WindowGroup("Conductor Harness") {
            ConductorSurfaceView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
