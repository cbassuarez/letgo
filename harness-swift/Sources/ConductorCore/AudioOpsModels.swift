import Foundation

public struct HarnessAudioFeaturePayload: Codable {
    public let rms: Double
    public let spectralCentroid: Double
    public let flux: Double
    public let transientDensity: Double
    public let updatedAt: Double

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

public struct HarnessPhoneAudioPoolStatePayload: Codable {
    public let gateArmed: Bool
    public let gateCommitted: Bool
    public let quadRouteReady: Bool
    public let availableDevices: [String]
    public let activeVoices: [String: Int]
    public let updatedAt: Double

    public init(
        gateArmed: Bool,
        gateCommitted: Bool,
        quadRouteReady: Bool,
        availableDevices: [String] = [],
        activeVoices: [String: Int] = [:],
        updatedAt: Double
    ) {
        self.gateArmed = gateArmed
        self.gateCommitted = gateCommitted
        self.quadRouteReady = quadRouteReady
        self.availableDevices = availableDevices
        self.activeVoices = activeVoices
        self.updatedAt = updatedAt
    }
}

public enum PhoneAudioCommandKind: String, Codable {
    case noteOn = "note_on"
    case noteOff = "note_off"
    case sampleTrigger = "sample_trigger"
    case ambientNoise = "ambient_noise"
    case stopAll = "stop_all"
}

public struct HarnessPhoneAudioCommandPayload: Codable {
    public let commandId: String
    public let kind: PhoneAudioCommandKind
    public let targetHashedIds: [String]
    public let note: Int?
    public let velocity: Double?
    public let sampleId: String?
    public let gain: Double?
    public let seed: Int?
    public let issuedAt: Double

    public init(
        commandId: String,
        kind: PhoneAudioCommandKind,
        targetHashedIds: [String] = [],
        note: Int? = nil,
        velocity: Double? = nil,
        sampleId: String? = nil,
        gain: Double? = nil,
        seed: Int? = nil,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.kind = kind
        self.targetHashedIds = targetHashedIds
        self.note = note
        self.velocity = velocity
        self.sampleId = sampleId
        self.gain = gain
        self.seed = seed
        self.issuedAt = issuedAt
    }
}

public struct HarnessPhoneAudioAckPayload: Codable {
    public let commandId: String
    public let hashedId: String
    public let ok: Bool
    public let detail: String?
    public let receivedAt: Double

    public init(commandId: String, hashedId: String, ok: Bool, detail: String?, receivedAt: Double) {
        self.commandId = commandId
        self.hashedId = hashedId
        self.ok = ok
        self.detail = detail
        self.receivedAt = receivedAt
    }
}
