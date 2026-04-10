import AVKit
import ConductorCore
import SwiftUI

struct ConductorPreviewView: View {
    @ObservedObject var model: ConductorHarnessViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview Window")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Scene: \(model.previewScene.rawValue) • mode: \(model.effectiveOutputMode.rawValue) • \(model.previewStatus)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Play") {
                    model.playPreview()
                }
                .buttonStyle(.bordered)
                Button("Pause") {
                    model.pausePreview()
                }
                .buttonStyle(.bordered)
            }

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))

                VideoPlayer(player: model.previewPlayer)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if !model.generatedLine.isEmpty {
                    Text(model.generatedLine)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(12)
                }
            }
            .frame(minHeight: 520)

            HStack {
                Text("Current media")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(model.effectiveOutputMode == .interstitial ? model.interstitialFilename() : model.mediaFilename(for: model.previewScene))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(minWidth: 980, minHeight: 680)
        .background(Color.black.opacity(0.94))
        .preferredColorScheme(.dark)
    }
}
