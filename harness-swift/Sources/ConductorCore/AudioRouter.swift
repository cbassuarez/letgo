import AVFoundation
import Foundation

public struct AudioRoute: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let channelCount: Int

    public init(id: String, name: String, channelCount: Int) {
        self.id = id
        self.name = name
        self.channelCount = channelCount
    }
}

public final class AudioRouter {
    private let engine = AVAudioEngine()

    public init() {}

    public func availableRoutes() -> [AudioRoute] {
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        return [
            AudioRoute(
                id: "default-output",
                name: "Default Output Device",
                channelCount: Int(outputFormat.channelCount)
            )
        ]
    }

    public func startEngine() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    public func stopEngine() {
        engine.stop()
    }
}
