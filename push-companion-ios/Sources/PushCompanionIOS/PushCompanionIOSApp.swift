import SwiftUI

@main
struct PushCompanionIOSApp: App {
    @StateObject private var viewModel = PushDeckViewModel()

    var body: some Scene {
        WindowGroup("Push Companion") {
            DeckSceneView(model: viewModel)
        }
    }
}
