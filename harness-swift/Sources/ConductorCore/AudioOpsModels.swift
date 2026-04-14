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
    public let zoneOccupancy: [String: Int]?
    public let deviceHealth: [String: DeviceHealth]?
    public let failoverCount: Int?
    public let updatedAt: Double

    public struct DeviceHealth: Codable, Equatable {
        public let rttMs: Double
        public let driftMs: Double
        public let ackReliability: Double
        public let lastSeenAt: Double

        public init(rttMs: Double, driftMs: Double, ackReliability: Double, lastSeenAt: Double) {
            self.rttMs = rttMs
            self.driftMs = driftMs
            self.ackReliability = ackReliability
            self.lastSeenAt = lastSeenAt
        }
    }

    public init(
        gateArmed: Bool,
        gateCommitted: Bool,
        quadRouteReady: Bool,
        availableDevices: [String] = [],
        activeVoices: [String: Int] = [:],
        zoneOccupancy: [String: Int]? = nil,
        deviceHealth: [String: DeviceHealth]? = nil,
        failoverCount: Int? = nil,
        updatedAt: Double
    ) {
        self.gateArmed = gateArmed
        self.gateCommitted = gateCommitted
        self.quadRouteReady = quadRouteReady
        self.availableDevices = availableDevices
        self.activeVoices = activeVoices
        self.zoneOccupancy = zoneOccupancy
        self.deviceHealth = deviceHealth
        self.failoverCount = failoverCount
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
    public let renderHints: RenderHints?
    public let renderHintsByTarget: [String: RenderHints]?
    public let issuedAt: Double

    public struct RenderHints: Codable {
        public let zoneId: String?
        public let pan: Double?
        public let detuneCents: Double?
        public let grainMix: Double?
        public let motionEnergy: Double?
        public let priority: String?

        public init(
            zoneId: String? = nil,
            pan: Double? = nil,
            detuneCents: Double? = nil,
            grainMix: Double? = nil,
            motionEnergy: Double? = nil,
            priority: String? = nil
        ) {
            self.zoneId = zoneId
            self.pan = pan
            self.detuneCents = detuneCents
            self.grainMix = grainMix
            self.motionEnergy = motionEnergy
            self.priority = priority
        }
    }

    public init(
        commandId: String,
        kind: PhoneAudioCommandKind,
        targetHashedIds: [String] = [],
        note: Int? = nil,
        velocity: Double? = nil,
        sampleId: String? = nil,
        gain: Double? = nil,
        seed: Int? = nil,
        renderHints: RenderHints? = nil,
        renderHintsByTarget: [String: RenderHints]? = nil,
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
        self.renderHints = renderHints
        self.renderHintsByTarget = renderHintsByTarget
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
