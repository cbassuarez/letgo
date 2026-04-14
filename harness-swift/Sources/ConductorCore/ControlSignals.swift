import Foundation

public enum ControlSourceKind: String, Codable, CaseIterable, Sendable {
    case hotas
    case midi
}

public enum ControlInputMode: String, Codable, CaseIterable, Sendable {
    case hotas
    case midi
    case hybrid

    public var includesHOTAS: Bool {
        self == .hotas || self == .hybrid
    }

    public var includesMIDI: Bool {
        self == .midi || self == .hybrid
    }
}

public enum ControlSignalKind: String, Codable, CaseIterable, Sendable {
    case axis
    case button
    case hat
    case note
    case unknown
}

public enum ControlSignalPhase: String, Codable, CaseIterable, Sendable {
    case began
    case changed
    case ended
}

public struct ControlSignal: Equatable, Codable, Sendable {
    public let controlID: String
    public let kind: ControlSignalKind
    public let phase: ControlSignalPhase
    public let normalizedValue: Double
    public let rawValue: Int
    public let timestamp: TimeInterval
    public let sourceDeviceID: String
    public let sourceKind: ControlSourceKind

    public init(
        controlID: String,
        kind: ControlSignalKind,
        phase: ControlSignalPhase,
        normalizedValue: Double,
        rawValue: Int,
        timestamp: TimeInterval,
        sourceDeviceID: String,
        sourceKind: ControlSourceKind
    ) {
        self.controlID = controlID
        self.kind = kind
        self.phase = phase
        self.normalizedValue = min(1.0, max(0.0, normalizedValue))
        self.rawValue = rawValue
        self.timestamp = timestamp
        self.sourceDeviceID = sourceDeviceID
        self.sourceKind = sourceKind
    }
}

public protocol ControlSignalSource: AnyObject {
    var sourceKind: ControlSourceKind { get }
    var sourceName: String { get }
    func start(onEvent: @escaping (ControlSignal) -> Void)
    func stop()
}
