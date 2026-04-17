import SwiftUI

struct VideoOutView: View {
    @ObservedObject var model: ConductorHarnessViewModel
    @ObservedObject var displayCoordinator: VideoOutDisplayCoordinator
    @ObservedObject var vufineDisplayCoordinator: VufineDisplayCoordinator

    var body: some View {
        LowLatencyPlayerLayerView(player: model.previewPlayer, gravity: .resizeAspectFill)
            .ignoresSafeArea()
        .background(Color.black)
        .preferredColorScheme(.dark)
        .overlay {
            WindowAccessor { window in
                displayCoordinator.attach(window: window)
                displayCoordinator.refreshPlacement(avoidingScreenID: vufineDisplayCoordinator.activeScreenID)
            }
            .allowsHitTesting(false)
        }
        .onChange(of: vufineDisplayCoordinator.activeScreenID) { _, newValue in
            displayCoordinator.refreshPlacement(avoidingScreenID: newValue)
        }
        .onDisappear {
            displayCoordinator.detach()
        }
    }
}
