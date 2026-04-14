import Foundation

public enum MIDIEventKind: String, Sendable {
    case controlChange
    case noteOn
    case noteOff
}

public struct MIDIEvent {
    public let kind: MIDIEventKind
    public let channel: Int
    public let controller: Int
    public let note: Int
    public let value: Int

    public init(controller: Int, value: Int, channel: Int = 0) {
        kind = .controlChange
        self.channel = max(0, min(15, channel))
        self.controller = controller
        note = -1
        self.value = value
    }

    public static func noteOn(note: Int, velocity: Int, channel: Int = 0) -> MIDIEvent {
        MIDIEvent(
            kind: .noteOn,
            channel: channel,
            controller: -1,
            note: note,
            value: velocity
        )
    }

    public static func noteOff(note: Int, velocity: Int = 0, channel: Int = 0) -> MIDIEvent {
        MIDIEvent(
            kind: .noteOff,
            channel: channel,
            controller: -1,
            note: note,
            value: velocity
        )
    }

    public init(kind: MIDIEventKind, channel: Int, controller: Int, note: Int, value: Int) {
        self.kind = kind
        self.channel = max(0, min(15, channel))
        self.controller = controller
        self.note = note
        self.value = value
    }
}

public protocol MIDIEventSource {
    func start(onEvent: @escaping (MIDIEvent) -> Void)
    func stop()
}

public enum MIDIControlMap: Int {
    case textAmount = 20
    case compositeBias = 21
    case audioGain = 22
    case spatialX = 23
    case spatialY = 24
    case spatialZ = 25
}

public final class MIDIIngestor {
    private let source: MIDIEventSource
    private let onVectorPatch: (ParamVectorPatch) -> Void

    public init(source: MIDIEventSource, onVectorPatch: @escaping (ParamVectorPatch) -> Void) {
        self.source = source
        self.onVectorPatch = onVectorPatch
    }

    public func start() {
        source.start { [onVectorPatch] event in
            guard event.kind == .controlChange else {
                return
            }
            let normalized = max(0.0, min(1.0, Double(event.value) / 127.0))
            guard let mapping = MIDIControlMap(rawValue: event.controller) else {
                return
            }

            switch mapping {
            case .textAmount:
                onVectorPatch(ParamVectorPatch(textAmount: normalized))
            case .compositeBias:
                onVectorPatch(ParamVectorPatch(compositeBias: normalized))
            case .audioGain:
                onVectorPatch(ParamVectorPatch(audioGain: normalized))
            case .spatialX:
                onVectorPatch(ParamVectorPatch(spatialX: normalized))
            case .spatialY:
                onVectorPatch(ParamVectorPatch(spatialY: normalized))
            case .spatialZ:
                onVectorPatch(ParamVectorPatch(spatialZ: normalized))
            }
        }
    }

    public func stop() {
        source.stop()
    }
}

public final class SimulatedMIDIEventSource: MIDIEventSource {
    private var onEvent: ((MIDIEvent) -> Void)?

    public init() {}

    public func start(onEvent: @escaping (MIDIEvent) -> Void) {
        self.onEvent = onEvent
    }

    public func stop() {
        onEvent = nil
    }

    public func inject(_ event: MIDIEvent) {
        onEvent?(event)
    }
}
