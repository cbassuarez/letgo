import AVFoundation
import Foundation

public enum AudioRouteMode: String, Codable, Equatable {
    case quad
    case stereoFallback
    case unavailable

    public var isOutputReady: Bool {
        self == .quad || self == .stereoFallback
    }
}

public struct QuadRouteStatus: Equatable {
    public let channelCount: Int
    public let quadReady: Bool
    public let stereoFallbackReady: Bool
    public let mode: AudioRouteMode
    public let routeName: String

    public init(
        channelCount: Int,
        quadReady: Bool,
        stereoFallbackReady: Bool,
        mode: AudioRouteMode,
        routeName: String
    ) {
        self.channelCount = channelCount
        self.quadReady = quadReady
        self.stereoFallbackReady = stereoFallbackReady
        self.mode = mode
        self.routeName = routeName
    }
}

public struct QuadAudioFeatures: Codable, Equatable, Sendable {
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
    public enum EngineError: LocalizedError {
        case engineNotRunning

        public var errorDescription: String? {
            switch self {
            case .engineNotRunning:
                return "audio engine is not running"
            }
        }
    }

    public var onFeatures: ((QuadAudioFeatures) -> Void)?

    private let engine = AVAudioEngine()
    private let synthMixer = AVAudioMixerNode()
    private let sampleMixer = AVAudioMixerNode()
    private let ambientNoisePlayer = AVAudioPlayerNode()

    private var synthPlayers: [Int: AVAudioPlayerNode] = [:]
    private var samplePlayers: [UUID: AVAudioPlayerNode] = [:]
    private var sampleFiles: [UUID: AVAudioFile] = [:]
    private var paulstretchPlayers: [UUID: AVAudioPlayerNode] = [:]
    private var paulstretchTimePitchUnits: [UUID: AVAudioUnitTimePitch] = [:]
    private var paulstretchFiles: [UUID: AVAudioFile] = [:]
    private var ambientNoiseBuffer: AVAudioPCMBuffer?
    private var lastFeatureEmitAt: CFAbsoluteTime = 0
    private let baseSynthVolume: Float = 0.9
    private let baseSampleVolume: Float = 0.9
    private let baseAmbientVolume: Float = 0.16
    private var effectsChainState: EffectsChainState = .idle
    private var staticMacroFrame = EffectsMacroFrame(
        chainAIntensity: 0,
        chainBIntensity: 0,
        articulation: 0.5,
        timbre: 0.5,
        textureSend: 0
    )
    private var choirFieldState: ChoirFieldState = .neutral

    public init() {
        engine.attach(synthMixer)
        engine.attach(sampleMixer)
        engine.attach(ambientNoisePlayer)

        engine.connect(synthMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(sampleMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(ambientNoisePlayer, to: sampleMixer, format: nil)

        synthMixer.outputVolume = baseSynthVolume
        sampleMixer.outputVolume = baseSampleVolume
        ambientNoisePlayer.volume = baseAmbientVolume

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
        let quadReady = channelCount >= 4
        let stereoFallbackReady = !quadReady && channelCount >= 2
        let mode: AudioRouteMode = quadReady
            ? .quad
            : (stereoFallbackReady ? .stereoFallback : .unavailable)
        return QuadRouteStatus(
            channelCount: channelCount,
            quadReady: quadReady,
            stereoFallbackReady: stereoFallbackReady,
            mode: mode,
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
        effectsChainState = .idle
        staticMacroFrame = EffectsMacroFrame(
            chainAIntensity: 0,
            chainBIntensity: 0,
            articulation: 0.5,
            timbre: 0.5,
            textureSend: 0
        )
        choirFieldState = .neutral
        applyEffectsState()
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
        guard engine.isRunning else { throw EngineError.engineNotRunning }
        let file = try AVAudioFile(forReading: url)
        let player = AVAudioPlayerNode()
        let playerID = UUID()
        player.volume = Float(max(0, min(1, gain)))
        engine.attach(player)
        engine.connect(player, to: sampleMixer, format: file.processingFormat)
        samplePlayers[playerID] = player
        // Keep the file alive for the full scheduled playback window.
        sampleFiles[playerID] = file
        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let finishedPlayer = self.samplePlayers.removeValue(forKey: playerID) else { return }
                finishedPlayer.stop()
                self.engine.detach(finishedPlayer)
                self.sampleFiles.removeValue(forKey: playerID)
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
        sampleFiles.removeAll()

        for (_, player) in paulstretchPlayers {
            player.stop()
            engine.detach(player)
        }
        for (_, timePitch) in paulstretchTimePitchUnits {
            engine.detach(timePitch)
        }
        paulstretchPlayers.removeAll()
        paulstretchTimePitchUnits.removeAll()
        paulstretchFiles.removeAll()
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

    public func setEffectsChainState(chain: EffectsChainID, active: Bool, intensity: Double) {
        effectsChainState.set(chain: chain, active: active, intensity: intensity)
        applyEffectsState()
    }

    public func setStaticMacroFrame(_ frame: EffectsMacroFrame) {
        staticMacroFrame = frame
        applyEffectsState()
    }

    public func setChoirFieldState(_ state: ChoirFieldState) {
        choirFieldState = state
        applyEffectsState()
    }

    public func currentEffectsChainState() -> EffectsChainState {
        effectsChainState
    }

    public func triggerPaulstretchedSample(
        url: URL,
        gain: Double = 0.16,
        rate: Double = 0.14
    ) throws {
        guard engine.isRunning else { throw EngineError.engineNotRunning }
        let file = try AVAudioFile(forReading: url)
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        let playerID = UUID()

        player.volume = Float(max(0, min(1, gain)))
        timePitch.rate = Float(max(0.03, min(0.38, rate)))
        timePitch.overlap = 8

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: file.processingFormat)
        engine.connect(timePitch, to: sampleMixer, format: file.processingFormat)

        paulstretchPlayers[playerID] = player
        paulstretchTimePitchUnits[playerID] = timePitch
        paulstretchFiles[playerID] = file

        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if let finished = self.paulstretchPlayers.removeValue(forKey: playerID) {
                    finished.stop()
                    self.engine.detach(finished)
                }
                if let finishedPitch = self.paulstretchTimePitchUnits.removeValue(forKey: playerID) {
                    self.engine.detach(finishedPitch)
                }
                self.paulstretchFiles.removeValue(forKey: playerID)
            }
        }
        player.play()
    }

    private func applyEffectsState() {
        // Chain A is Rhythm: transient/gate/pump emphasis.
        let rhythmBoost = effectsChainState.chainAActive ? Float(0.45 * effectsChainState.chainAIntensity) : 0
        // Chain B is Space: smear/shimmer/spread emphasis.
        let spaceBoost = effectsChainState.chainBActive ? Float(0.45 * effectsChainState.chainBIntensity) : 0

        let articulation = Float(staticMacroFrame.articulation)
        let timbre = Float(staticMacroFrame.timbre)
        let textureSend = Float(staticMacroFrame.textureSend)
        let choirSpread = Float(choirFieldState.spread)
        let choirDepth = Float(choirFieldState.depth)
        let choirDetune = Float(choirFieldState.detune)

        sampleMixer.outputVolume = min(
            1.0,
            baseSampleVolume
                + rhythmBoost * 0.44
                + articulation * 0.16
                + choirSpread * 0.08
        )
        synthMixer.outputVolume = min(
            1.0,
            baseSynthVolume
                + spaceBoost * 0.34
                + timbre * 0.14
                + choirDetune * 0.12
        )
        ambientNoisePlayer.volume = min(
            1.0,
            baseAmbientVolume
                + rhythmBoost * 0.12
                + spaceBoost * 0.24
                + textureSend * 0.28
                + choirDepth * 0.16
        )
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
            if now - self.lastFeatureEmitAt < 0.1 {
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
