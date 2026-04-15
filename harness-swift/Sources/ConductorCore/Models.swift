import Foundation

public enum ShowState: String, Codable, CaseIterable {
    case idle
    case preshow
    case introduction
    case main
    case ending
    case hold
    case aborted
    case recovery
}

public enum CueAction: String, Codable {
    case start
    case hold
    case jump
    case abort
    case recover
}

public struct ParamVector: Codable, Equatable, Sendable {
    public var textAmount: Double
    public var compositeBias: Double
    public var audioGain: Double
    public var spatialX: Double
    public var spatialY: Double
    public var spatialZ: Double

    public static let neutral = ParamVector(
        textAmount: 0,
        compositeBias: 0.5,
        audioGain: 0.5,
        spatialX: 0.5,
        spatialY: 0.5,
        spatialZ: 0.5
    )

    public func merged(_ patch: ParamVectorPatch) -> ParamVector {
        ParamVector(
            textAmount: clamp(patch.textAmount ?? textAmount),
            compositeBias: clamp(patch.compositeBias ?? compositeBias),
            audioGain: clamp(patch.audioGain ?? audioGain),
            spatialX: clamp(patch.spatialX ?? spatialX),
            spatialY: clamp(patch.spatialY ?? spatialY),
            spatialZ: clamp(patch.spatialZ ?? spatialZ)
        )
    }

    private func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

public struct ParamVectorPatch: Equatable, Sendable {
    public var textAmount: Double?
    public var compositeBias: Double?
    public var audioGain: Double?
    public var spatialX: Double?
    public var spatialY: Double?
    public var spatialZ: Double?

    public init(
        textAmount: Double? = nil,
        compositeBias: Double? = nil,
        audioGain: Double? = nil,
        spatialX: Double? = nil,
        spatialY: Double? = nil,
        spatialZ: Double? = nil
    ) {
        self.textAmount = textAmount
        self.compositeBias = compositeBias
        self.audioGain = audioGain
        self.spatialX = spatialX
        self.spatialY = spatialY
        self.spatialZ = spatialZ
    }
}

public struct CueCommand: Codable, Equatable {
    public let cueId: String
    public let showState: ShowState
    public let logicalTime: TimeInterval
    public let payload: [String: String]
    public let version: Int
    public let action: CueAction

    public init(
        cueId: String,
        showState: ShowState,
        logicalTime: TimeInterval,
        payload: [String: String] = [:],
        version: Int = 1,
        action: CueAction
    ) {
        self.cueId = cueId
        self.showState = showState
        self.logicalTime = logicalTime
        self.payload = payload
        self.version = version
        self.action = action
    }
}

public struct PresentationDirective: Codable, Equatable {
    public let displayDuration: Double
    public let compositeAlpha: Double
    public let fontSize: Double
    public let fontWeight: Double

    public static let fallback = PresentationDirective(
        displayDuration: 5.0,
        compositeAlpha: 0.85,
        fontSize: 0.5,
        fontWeight: 0.5
    )

    public init(displayDuration: Double, compositeAlpha: Double, fontSize: Double, fontWeight: Double) {
        self.displayDuration = displayDuration
        self.compositeAlpha = compositeAlpha
        self.fontSize = fontSize
        self.fontWeight = fontWeight
    }
}

public struct DeviceTelemetry: Identifiable, Codable, Equatable {
    public let id: String
    public var lastSeen: Date
    public var zoneName: String?
    public var permissions: DevicePermissions

    public init(id: String, lastSeen: Date, zoneName: String? = nil, permissions: DevicePermissions = .none) {
        self.id = id
        self.lastSeen = lastSeen
        self.zoneName = zoneName
        self.permissions = permissions
    }
}

public struct DevicePermissions: Codable, Equatable {
    public var audio: Bool
    public var geolocation: Bool
    public var motion: Bool

    public static let none = DevicePermissions(audio: false, geolocation: false, motion: false)

    public init(audio: Bool, geolocation: Bool, motion: Bool) {
        self.audio = audio
        self.geolocation = geolocation
        self.motion = motion
    }
}

public struct ReplayEvent: Identifiable, Codable {
    public enum Kind: String, Codable {
        case cue
        case telemetry
        case selection
        case system
    }

    public let id: UUID
    public let kind: Kind
    public let timestamp: Date
    public let logicalTime: TimeInterval
    public let payload: [String: String]

    public init(id: UUID = UUID(), kind: Kind, timestamp: Date, logicalTime: TimeInterval, payload: [String: String]) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.logicalTime = logicalTime
        self.payload = payload
    }
}
