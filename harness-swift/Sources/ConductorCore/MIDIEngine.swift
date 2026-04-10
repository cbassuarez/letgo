import Foundation

public struct MIDIEvent {
    public let controller: Int
    public let value: Int

    public init(controller: Int, value: Int) {
        self.controller = controller
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
