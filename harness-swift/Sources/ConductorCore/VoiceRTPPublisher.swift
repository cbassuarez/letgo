import Foundation

#if canImport(AVFoundation) && canImport(AudioToolbox) && canImport(Network)
import AVFoundation
import AudioToolbox
import Network

public struct VoiceRTPIngestEndpoint: Equatable, Sendable {
    public let ip: String
    public let port: Int
    public let payloadType: Int
    public let ssrc: Int
    public let clockRate: Int
    public let channels: Int

    public init(
        ip: String,
        port: Int,
        payloadType: Int,
        ssrc: Int,
        clockRate: Int = 48_000,
        channels: Int = 2
    ) {
        self.ip = ip
        self.port = port
        self.payloadType = payloadType
        self.ssrc = ssrc
        self.clockRate = clockRate
        self.channels = channels
    }
}

public enum VoiceTrackSource: Equatable, Sendable {
    case synthesizedTone(note: Int)
    case returnBus(index: Int)
}

public enum VoiceReturnCaptureFallbackMode: String, Equatable, Sendable {
    case silence
    case synthesizedTone
}

public struct VoiceReturnCaptureConfiguration: Equatable, Sendable {
    public let enabled: Bool
    public let preferredSampleRate: Double
    public let preferredBusCount: Int
    public let bufferDurationSeconds: Double
    public let fallbackMode: VoiceReturnCaptureFallbackMode

    public init(
        enabled: Bool = true,
        preferredSampleRate: Double = 48_000,
        preferredBusCount: Int = 8,
        bufferDurationSeconds: Double = 6,
        fallbackMode: VoiceReturnCaptureFallbackMode = .silence
    ) {
        self.enabled = enabled
        self.preferredSampleRate = max(8_000, preferredSampleRate)
        self.preferredBusCount = max(1, preferredBusCount)
        self.bufferDurationSeconds = max(1, bufferDurationSeconds)
        self.fallbackMode = fallbackMode
    }
}

private final class InterleavedStereoRingBuffer {
    private let capacityFrames: Int
    private var samples: [Float]
    private(set) var writeFrame: UInt64 = 0

    init(capacityFrames: Int) {
        self.capacityFrames = max(512, capacityFrames)
        self.samples = Array(repeating: 0, count: max(512, capacityFrames) * 2)
    }

    func write(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }
        let capacity = UInt64(capacityFrames)
        for frame in 0 ..< frameCount {
            let destination = Int((writeFrame + UInt64(frame)) % capacity) * 2
            samples[destination] = left[frame]
            samples[destination + 1] = right[frame]
        }
        writeFrame &+= UInt64(frameCount)
    }

    func read(into output: inout [Float], cursor: inout UInt64, frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        let requiredSamples = frameCount * 2
        if output.count != requiredSamples {
            output = Array(repeating: 0, count: requiredSamples)
        } else {
            output.withUnsafeMutableBufferPointer { pointer in
                pointer.initialize(repeating: 0)
            }
        }

        let capacity = UInt64(capacityFrames)
        let availableStart = writeFrame > capacity ? writeFrame - capacity : 0
        if cursor < availableStart {
            cursor = availableStart
        }

        let availableFrames = Int(writeFrame >= cursor ? writeFrame - cursor : 0)
        if availableFrames <= 0 {
            cursor = writeFrame
            return 0
        }

        let framesToRead = min(frameCount, availableFrames)
        for frame in 0 ..< framesToRead {
            let source = Int((cursor + UInt64(frame)) % capacity) * 2
            let destination = frame * 2
            output[destination] = samples[source]
            output[destination + 1] = samples[source + 1]
        }

        cursor &+= UInt64(framesToRead)
        return framesToRead
    }
}

private final class VoiceReturnCaptureEngine {
    struct Snapshot {
        let running: Bool
        let busCount: Int
        let channelCount: Int
        let sampleRate: Double
        let lastError: String?
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()

    private var rings: [InterleavedStereoRingBuffer] = []
    private var channelCount: Int = 0
    private var sampleRate: Double = 48_000
    private var running = false
    private var lastError: String?
    private var appliedConfiguration = VoiceReturnCaptureConfiguration()

    func ensureRunning(configuration: VoiceReturnCaptureConfiguration) -> Bool {
        if running && appliedConfiguration == configuration {
            return true
        }
        stop()
        guard configuration.enabled else {
            appliedConfiguration = configuration
            return false
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let resolvedChannels = max(1, Int(inputFormat.channelCount))
        let requestedBusCount = max(1, configuration.preferredBusCount)
        let availableBusCount = max(1, Int(ceil(Double(resolvedChannels) / 2.0)))
        let busCount = min(requestedBusCount, availableBusCount)
        let resolvedSampleRate = max(8_000, configuration.preferredSampleRate)
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: resolvedSampleRate,
            channels: AVAudioChannelCount(resolvedChannels),
            interleaved: false
        ) ?? inputFormat

        let ringCapacity = Int(configuration.bufferDurationSeconds * resolvedSampleRate)

        lock.lock()
        rings = (0 ..< busCount).map { _ in
            InterleavedStereoRingBuffer(capacityFrames: ringCapacity)
        }
        channelCount = resolvedChannels
        sampleRate = resolvedSampleRate
        lock.unlock()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 960, format: tapFormat) { [weak self] buffer, _ in
            self?.ingest(buffer: buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            running = true
            lastError = nil
            appliedConfiguration = configuration
            return true
        } catch {
            running = false
            lastError = "capture_engine_start_failed: \(error.localizedDescription)"
            appliedConfiguration = configuration
            return false
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    func snapshot() -> Snapshot {
        lock.lock()
        let snapshot = Snapshot(
            running: running,
            busCount: rings.count,
            channelCount: channelCount,
            sampleRate: sampleRate,
            lastError: lastError
        )
        lock.unlock()
        return snapshot
    }

    func cursorStart(forBus busIndex: Int) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard !rings.isEmpty else { return 0 }
        let normalized = normalizeBusIndex(busIndex, count: rings.count)
        return rings[normalized].writeFrame
    }

    func read(bus busIndex: Int, cursor: inout UInt64, frameCount: Int, into output: inout [Float]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !rings.isEmpty else {
            if output.count != frameCount * 2 {
                output = Array(repeating: 0, count: frameCount * 2)
            } else {
                output.withUnsafeMutableBufferPointer { pointer in
                    pointer.initialize(repeating: 0)
                }
            }
            return 0
        }
        let normalized = normalizeBusIndex(busIndex, count: rings.count)
        return rings[normalized].read(into: &output, cursor: &cursor, frameCount: frameCount)
    }

    private func ingest(buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        guard let channels = buffer.floatChannelData else { return }
        let incomingChannelCount = Int(buffer.format.channelCount)
        guard incomingChannelCount > 0 else { return }

        lock.lock()
        guard !rings.isEmpty else {
            lock.unlock()
            return
        }

        for index in 0 ..< rings.count {
            let leftChannel = min(index * 2, incomingChannelCount - 1)
            let rightChannel = min(leftChannel + 1, incomingChannelCount - 1)
            rings[index].write(
                left: channels[leftChannel],
                right: channels[rightChannel],
                frameCount: frameCount
            )
        }

        lock.unlock()
    }

    private func normalizeBusIndex(_ busIndex: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let clamped = max(0, busIndex)
        if clamped < count {
            return clamped
        }
        return clamped % count
    }
}

public final class VoiceRTPPublisher {
    private final class TrackRuntime {
        let trackID: String
        let note: Int
        let ingest: VoiceRTPIngestEndpoint
        let source: VoiceTrackSource
        let connection: NWConnection
        let inputFormat: AVAudioFormat
        let outputFormat: AVAudioFormat
        let converter: AVAudioConverter
        let maximumPacketSize: Int
        let phaseStep: Double
        var phase: Double
        var captureCursorFrame: UInt64
        var captureScratch: [Float]
        var sequence: UInt16
        var timestamp: UInt32

        init?(trackID: String, note: Int, ingest: VoiceRTPIngestEndpoint, source: VoiceTrackSource, captureCursorFrame: UInt64) {
            guard let port = NWEndpoint.Port(rawValue: UInt16(max(1, min(65_535, ingest.port)))) else {
                return nil
            }

            let channelCount = max(1, min(2, ingest.channels))
            guard let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(ingest.clockRate),
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
            ) else {
                return nil
            }
            guard let outputFormat = AVAudioFormat(settings: [
                AVFormatIDKey: kAudioFormatOpus,
                AVSampleRateKey: Double(ingest.clockRate),
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: 64_000
            ]) else {
                return nil
            }
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                return nil
            }

            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let connection = NWConnection(host: NWEndpoint.Host(ingest.ip), port: port, using: params)
            connection.stateUpdateHandler = { _ in }

            self.trackID = trackID
            self.note = max(0, min(127, note))
            self.ingest = ingest
            self.source = source
            self.connection = connection
            self.inputFormat = inputFormat
            self.outputFormat = outputFormat
            self.converter = converter
            self.maximumPacketSize = max(256, Int(converter.maximumOutputPacketSize))

            let frequency = 440.0 * pow(2.0, Double(self.note - 69) / 12.0)
            self.phase = 0
            self.phaseStep = (2.0 * Double.pi * frequency) / Double(ingest.clockRate)

            self.captureCursorFrame = captureCursorFrame
            self.captureScratch = []

            self.sequence = UInt16.random(in: UInt16.min ... UInt16.max)
            self.timestamp = UInt32.random(in: UInt32.min ... UInt32.max)
        }
    }

    private let queue = DispatchQueue(label: "ConductorHarness.VoiceRTPPublisher", qos: .userInitiated)
    private var tracksByID: [String: TrackRuntime] = [:]
    private var timer: DispatchSourceTimer?

    private let packetFrames = 960
    private let packetDuration: TimeInterval = 0.02

    private let returnCapture = VoiceReturnCaptureEngine()
    private var returnCaptureConfiguration = VoiceReturnCaptureConfiguration()

    public init() {}

    deinit {
        stopAll()
    }

    public func configureReturnCapture(_ configuration: VoiceReturnCaptureConfiguration) {
        queue.async { [weak self] in
            guard let self else { return }
            self.returnCaptureConfiguration = configuration
            if !configuration.enabled {
                self.returnCapture.stop()
                return
            }
            if self.hasReturnBusTracksLocked() {
                _ = self.returnCapture.ensureRunning(configuration: configuration)
            }
        }
    }

    public func upsertTrack(
        trackID: String,
        note: Int,
        ingest: VoiceRTPIngestEndpoint,
        source: VoiceTrackSource? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.upsertTrackLocked(trackID: trackID, note: note, ingest: ingest, source: source)
        }
    }

    public func removeTrack(trackID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.removeTrackLocked(trackID: trackID)
        }
    }

    public func stopAll() {
        queue.async { [weak self] in
            guard let self else { return }
            for (_, runtime) in self.tracksByID {
                runtime.connection.cancel()
            }
            self.tracksByID.removeAll()
            self.timer?.setEventHandler {}
            self.timer?.cancel()
            self.timer = nil
            self.returnCapture.stop()
        }
    }

    private func upsertTrackLocked(
        trackID: String,
        note: Int,
        ingest: VoiceRTPIngestEndpoint,
        source: VoiceTrackSource?
    ) {
        let resolvedSource = source ?? .synthesizedTone(note: note)

        if let existing = tracksByID[trackID],
           existing.note == note,
           existing.ingest == ingest,
           existing.source == resolvedSource {
            return
        }

        if case .returnBus = resolvedSource {
            _ = returnCapture.ensureRunning(configuration: returnCaptureConfiguration)
        }

        let captureCursorFrame: UInt64
        switch resolvedSource {
        case .returnBus(let busIndex):
            captureCursorFrame = returnCapture.cursorStart(forBus: busIndex)
        case .synthesizedTone:
            captureCursorFrame = 0
        }

        removeTrackLocked(trackID: trackID)
        guard let runtime = TrackRuntime(
            trackID: trackID,
            note: note,
            ingest: ingest,
            source: resolvedSource,
            captureCursorFrame: captureCursorFrame
        ) else {
            return
        }

        runtime.connection.start(queue: queue)
        tracksByID[trackID] = runtime
        ensureTimerLocked()
    }

    private func removeTrackLocked(trackID: String) {
        guard let runtime = tracksByID.removeValue(forKey: trackID) else { return }
        runtime.connection.cancel()
        stopTimerIfIdleLocked()
    }

    private func ensureTimerLocked() {
        guard timer == nil else { return }
        let nextTimer = DispatchSource.makeTimerSource(queue: queue)
        nextTimer.schedule(deadline: .now() + packetDuration, repeating: packetDuration, leeway: .milliseconds(2))
        nextTimer.setEventHandler { [weak self] in
            self?.tickLocked()
        }
        nextTimer.resume()
        timer = nextTimer
    }

    private func stopTimerIfIdleLocked() {
        guard tracksByID.isEmpty else { return }
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        returnCapture.stop()
    }

    private func hasReturnBusTracksLocked() -> Bool {
        tracksByID.values.contains { runtime in
            if case .returnBus = runtime.source {
                return true
            }
            return false
        }
    }

    private func tickLocked() {
        guard !tracksByID.isEmpty else {
            stopTimerIfIdleLocked()
            return
        }

        if hasReturnBusTracksLocked() {
            _ = returnCapture.ensureRunning(configuration: returnCaptureConfiguration)
        }

        for runtime in tracksByID.values {
            sendPacketLocked(runtime)
        }
    }

    private func sendPacketLocked(_ runtime: TrackRuntime) {
        guard let pcm = AVAudioPCMBuffer(
            pcmFormat: runtime.inputFormat,
            frameCapacity: AVAudioFrameCount(packetFrames)
        ) else {
            return
        }
        pcm.frameLength = AVAudioFrameCount(packetFrames)

        renderPCM(into: pcm, for: runtime)

        let compressed = AVAudioCompressedBuffer(
            format: runtime.outputFormat,
            packetCapacity: 8,
            maximumPacketSize: runtime.maximumPacketSize
        )

        var didProvideInput = false
        var conversionError: NSError?
        let status = runtime.converter.convert(to: compressed, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return pcm
        }

        guard conversionError == nil else { return }
        guard status == .haveData || status == .inputRanDry else { return }
        guard compressed.byteLength > 0 else { return }

        let payload = Data(bytes: compressed.data, count: Int(compressed.byteLength))
        var packet = Data()
        packet.reserveCapacity(12 + payload.count)

        packet.append(0x80)
        packet.append(UInt8(runtime.ingest.payloadType & 0x7F))

        var sequenceBE = runtime.sequence.bigEndian
        withUnsafeBytes(of: &sequenceBE) { packet.append(contentsOf: $0) }

        var timestampBE = runtime.timestamp.bigEndian
        withUnsafeBytes(of: &timestampBE) { packet.append(contentsOf: $0) }

        var ssrcBE = UInt32(truncatingIfNeeded: runtime.ingest.ssrc).bigEndian
        withUnsafeBytes(of: &ssrcBE) { packet.append(contentsOf: $0) }

        packet.append(payload)

        runtime.connection.send(content: packet, completion: .idempotent)
        runtime.sequence &+= 1
        runtime.timestamp &+= UInt32(packetFrames)
    }

    private func renderPCM(into pcm: AVAudioPCMBuffer, for runtime: TrackRuntime) {
        switch runtime.source {
        case .synthesizedTone:
            fillPCMWithSynthTone(into: pcm, runtime: runtime)
        case .returnBus(let busIndex):
            let readFrames = returnCapture.read(
                bus: busIndex,
                cursor: &runtime.captureCursorFrame,
                frameCount: packetFrames,
                into: &runtime.captureScratch
            )
            if readFrames > 0 {
                fillPCMFromInterleavedCapture(into: pcm, interleavedStereo: runtime.captureScratch)
            } else {
                switch returnCaptureConfiguration.fallbackMode {
                case .silence:
                    fillPCMSilence(into: pcm)
                case .synthesizedTone:
                    fillPCMWithSynthTone(into: pcm, runtime: runtime)
                }
            }
        }
    }

    private func fillPCMFromInterleavedCapture(into pcm: AVAudioPCMBuffer, interleavedStereo: [Float]) {
        guard let channels = pcm.floatChannelData else {
            return
        }
        let channelCount = Int(pcm.format.channelCount)
        let frameLength = Int(pcm.frameLength)
        guard channelCount >= 1 else { return }

        if channelCount == 1 {
            let mono = channels[0]
            for frame in 0 ..< frameLength {
                let source = frame * 2
                mono[frame] = (interleavedStereo[source] + interleavedStereo[source + 1]) * 0.5
            }
            return
        }

        let left = channels[0]
        let right = channels[1]
        for frame in 0 ..< frameLength {
            let source = frame * 2
            left[frame] = interleavedStereo[source]
            right[frame] = interleavedStereo[source + 1]
        }
    }

    private func fillPCMWithSynthTone(into pcm: AVAudioPCMBuffer, runtime: TrackRuntime) {
        let level: Float = 0.18
        guard let channels = pcm.floatChannelData else { return }
        let channelCount = Int(runtime.inputFormat.channelCount)
        var phase = runtime.phase
        for frame in 0 ..< packetFrames {
            let sample = sin(phase) * Double(level)
            phase += runtime.phaseStep
            if phase >= 2.0 * Double.pi {
                phase -= 2.0 * Double.pi
            }
            for channel in 0 ..< channelCount {
                channels[channel][frame] = Float(sample)
            }
        }
        runtime.phase = phase
    }

    private func fillPCMSilence(into pcm: AVAudioPCMBuffer) {
        guard let channels = pcm.floatChannelData else { return }
        let channelCount = Int(pcm.format.channelCount)
        let frameLength = Int(pcm.frameLength)
        for channel in 0 ..< channelCount {
            for frame in 0 ..< frameLength {
                channels[channel][frame] = 0
            }
        }
    }
}

#else

public struct VoiceRTPIngestEndpoint: Equatable, Sendable {
    public let ip: String
    public let port: Int
    public let payloadType: Int
    public let ssrc: Int
    public let clockRate: Int
    public let channels: Int

    public init(
        ip: String,
        port: Int,
        payloadType: Int,
        ssrc: Int,
        clockRate: Int = 48_000,
        channels: Int = 2
    ) {
        self.ip = ip
        self.port = port
        self.payloadType = payloadType
        self.ssrc = ssrc
        self.clockRate = clockRate
        self.channels = channels
    }
}

public enum VoiceTrackSource: Equatable, Sendable {
    case synthesizedTone(note: Int)
    case returnBus(index: Int)
}

public enum VoiceReturnCaptureFallbackMode: String, Equatable, Sendable {
    case silence
    case synthesizedTone
}

public struct VoiceReturnCaptureConfiguration: Equatable, Sendable {
    public let enabled: Bool
    public let preferredSampleRate: Double
    public let preferredBusCount: Int
    public let bufferDurationSeconds: Double
    public let fallbackMode: VoiceReturnCaptureFallbackMode

    public init(
        enabled: Bool = true,
        preferredSampleRate: Double = 48_000,
        preferredBusCount: Int = 8,
        bufferDurationSeconds: Double = 6,
        fallbackMode: VoiceReturnCaptureFallbackMode = .silence
    ) {
        self.enabled = enabled
        self.preferredSampleRate = preferredSampleRate
        self.preferredBusCount = preferredBusCount
        self.bufferDurationSeconds = bufferDurationSeconds
        self.fallbackMode = fallbackMode
    }
}

public final class VoiceRTPPublisher {
    public init() {}

    public func configureReturnCapture(_ configuration: VoiceReturnCaptureConfiguration) {
        _ = configuration
    }

    public func upsertTrack(
        trackID: String,
        note: Int,
        ingest: VoiceRTPIngestEndpoint,
        source: VoiceTrackSource? = nil
    ) {
        _ = (trackID, note, ingest, source)
    }

    public func removeTrack(trackID: String) {
        _ = trackID
    }

    public func stopAll() {}
}

#endif
