import AVFoundation
import Foundation

public struct QuadRouteStatus: Equatable {
    public let channelCount: Int
    public let quadReady: Bool
    public let routeName: String

    public init(channelCount: Int, quadReady: Bool, routeName: String) {
        self.channelCount = channelCount
        self.quadReady = quadReady
        self.routeName = routeName
    }
}

public struct QuadAudioFeatures: Codable, Equatable {
    public var rms: Double
    public var spectralCentroid: Double
    public var flux: Double
    public var transientDensity: Double
    public var updatedAt: Double

    public static let zero = QuadAudioFeatures(
        rms: 0,
        spectralCentroid: 0.5,
        flux: 0.5,
        transientDensity: 0,
        updatedAt: Date().timeIntervalSince1970 * 1000
    )

    public init(
        rms: Double,
        spectralCentroid: Double,
        flux: Double,
        transientDensity: Double,
        updatedAt: Double
    ) {
        self.rms = rms
        self.spectralCentroid = spectralCentroid
        self.flux = flux
        self.transientDensity = transientDensity
        self.updatedAt = updatedAt
    }
}

public final class QuadAudioEngine {
    public var onFeatures: ((QuadAudioFeatures) -> Void)?

    private let engine = AVAudioEngine()
    private let synthMixer = AVAudioMixerNode()
    private let sampleMixer = AVAudioMixerNode()
    private let ambientNoisePlayer = AVAudioPlayerNode()

    private var synthPlayers: [Int: AVAudioPlayerNode] = [:]
    private var samplePlayers: [UUID: AVAudioPlayerNode] = [:]
    private var ambientNoiseBuffer: AVAudioPCMBuffer?
    private var lastFeatureEmitAt: CFAbsoluteTime = 0

    public init() {
        engine.attach(synthMixer)
        engine.attach(sampleMixer)
        engine.attach(ambientNoisePlayer)

        engine.connect(synthMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(sampleMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(ambientNoisePlayer, to: sampleMixer, format: nil)

        synthMixer.outputVolume = 0.9
        sampleMixer.outputVolume = 0.9
        ambientNoisePlayer.volume = 0.16

        installFeatureTap()
        engine.prepare()
    }

    deinit {
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    public var isRunning: Bool {
        engine.isRunning
    }

    public func routeStatus() -> QuadRouteStatus {
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let channelCount = Int(outputFormat.channelCount)
        let routeName = "default-output"
        return QuadRouteStatus(
            channelCount: channelCount,
            quadReady: channelCount >= 4,
            routeName: routeName
        )
    }

    @discardableResult
    public func start() throws -> QuadRouteStatus {
        if !engine.isRunning {
            try engine.start()
        }
        return routeStatus()
    }

    public func stop() {
        stopAllSynthNotes()
        stopAllSamples()
        stopAmbientNoise()
        engine.stop()
        onFeatures?(QuadAudioFeatures.zero)
    }

    public func playSynthNote(note: Int, velocity: Double = 0.8, gain: Double = 0.24) {
        guard engine.isRunning else { return }
        guard synthPlayers[note] == nil else { return }
        guard let buffer = makeSineBuffer(
            note: note,
            duration: 1.0,
            gain: max(0.01, min(1, velocity * gain))
        ) else {
            return
        }

        let player = AVAudioPlayerNode()
        player.volume = 1.0
        engine.attach(player)
        engine.connect(player, to: synthMixer, format: buffer.format)
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.play()
        synthPlayers[note] = player
    }

    public func stopSynthNote(note: Int) {
        guard let player = synthPlayers.removeValue(forKey: note) else { return }
        player.stop()
        engine.detach(player)
    }

    public func stopAllSynthNotes() {
        for (_, player) in synthPlayers {
            player.stop()
            engine.detach(player)
        }
        synthPlayers.removeAll()
    }

    public func triggerSample(url: URL, gain: Double = 0.32) throws {
        guard engine.isRunning else { return }
        let file = try AVAudioFile(forReading: url)
        let player = AVAudioPlayerNode()
        let playerID = UUID()
        player.volume = Float(max(0, min(1, gain)))
        engine.attach(player)
        engine.connect(player, to: sampleMixer, format: file.processingFormat)
        samplePlayers[playerID] = player
        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let finishedPlayer = self.samplePlayers.removeValue(forKey: playerID) else { return }
                finishedPlayer.stop()
                self.engine.detach(finishedPlayer)
            }
        }
        player.play()
    }

    public func stopAllSamples() {
        for (_, player) in samplePlayers {
            player.stop()
            engine.detach(player)
        }
        samplePlayers.removeAll()
    }

    public func startAmbientNoise(gain: Double = 0.08, seed: UInt64 = 0xC1A0_0A11) {
        guard engine.isRunning else { return }

        if ambientNoiseBuffer == nil {
            ambientNoiseBuffer = makeNoiseBuffer(duration: 1.5, seed: seed)
        }
        guard let ambientNoiseBuffer else { return }

        ambientNoisePlayer.stop()
        ambientNoisePlayer.volume = Float(max(0, min(1, gain)))
        ambientNoisePlayer.scheduleBuffer(ambientNoiseBuffer, at: nil, options: [.loops], completionHandler: nil)
        ambientNoisePlayer.play()
    }

    public func stopAmbientNoise() {
        ambientNoisePlayer.stop()
    }

    private func installFeatureTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channelData = buffer.floatChannelData?.pointee else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 8 else { return }

            var sumSquares: Float = 0
            var spectralProxy: Float = 0
            var fluxSum: Float = 0
            var transientCount: Float = 0
            var previous: Float = channelData[0]

            for index in 0 ..< frameLength {
                let sample = channelData[index]
                sumSquares += sample * sample

                if index > 0 {
                    let delta = sample - previous
                    let absDelta = abs(delta)
                    spectralProxy += absDelta
                    fluxSum += absDelta
                    if absDelta > 0.18 {
                        transientCount += 1
                    }
                }
                previous = sample
            }

            let now = CFAbsoluteTimeGetCurrent()
            if now - self.lastFeatureEmitAt < 0.05 {
                return
            }
            self.lastFeatureEmitAt = now

            let rms = sqrt(sumSquares / Float(frameLength))
            let centroid = min(1, max(0, (spectralProxy / Float(frameLength)) * 4.5))
            let flux = min(1, max(0, (fluxSum / Float(frameLength)) * 6))
            let transientDensity = min(1, max(0, transientCount / Float(max(1, frameLength / 24))))
            let featureVector = QuadAudioFeatures(
                rms: Double(min(1, max(0, rms * 2.2))),
                spectralCentroid: Double(centroid),
                flux: Double(flux),
                transientDensity: Double(transientDensity),
                updatedAt: Date().timeIntervalSince1970 * 1000
            )

            DispatchQueue.main.async { [weak self] in
                self?.onFeatures?(featureVector)
            }
        }
    }

    private func makeSineBuffer(note: Int, duration: TimeInterval, gain: Double) -> AVAudioPCMBuffer? {
        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let frameCount = AVAudioFrameCount(max(32, Int(sampleRate * duration)))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?.pointee else { return nil }

        let frequency = 440.0 * pow(2.0, Double(note - 69) / 12.0)
        let angular = 2.0 * Double.pi * frequency / sampleRate
        let amp = Float(max(0, min(1, gain)))
        for frame in 0 ..< Int(frameCount) {
            let sample = sin(Double(frame) * angular)
            channel[frame] = amp * Float(sample)
        }
        return buffer
    }

    private func makeNoiseBuffer(duration: TimeInterval, seed: UInt64) -> AVAudioPCMBuffer? {
        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let frameCount = AVAudioFrameCount(max(32, Int(sampleRate * duration)))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?.pointee else { return nil }

        var state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        for index in 0 ..< Int(frameCount) {
            state = 6364136223846793005 &* state &+ 1
            let normalized = Float((state >> 33) & 0xFFFF) / Float(0xFFFF)
            channel[index] = (normalized * 2) - 1
        }
        return buffer
    }
}
