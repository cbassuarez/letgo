import SwiftUI

struct DeckSceneView: View {
    @ObservedObject var model: PushDeckViewModel

    var body: some View {
        PushDeckView(model: model)
    }
}
