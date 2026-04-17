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

    public struct RenderHints: Codable, Equatable {
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
    public let streamStatus: String?
    public let streamReason: String?
    public let voiceId: String?
    public let trackId: String?
    public let receivedAt: Double

    public init(
        commandId: String,
        hashedId: String,
        ok: Bool,
        detail: String?,
        streamStatus: String? = nil,
        streamReason: String? = nil,
        voiceId: String? = nil,
        trackId: String? = nil,
        receivedAt: Double
    ) {
        self.commandId = commandId
        self.hashedId = hashedId
        self.ok = ok
        self.detail = detail
        self.streamStatus = streamStatus
        self.streamReason = streamReason
        self.voiceId = voiceId
        self.trackId = trackId
        self.receivedAt = receivedAt
    }
}

public struct HarnessKeyboardPatchSnapshot: Codable, Equatable {
    public let patchId: String
    public let patchName: String?
    public let bank: Int
    public let program: Int
    public let updatedAt: Double

    public init(
        patchId: String,
        patchName: String? = nil,
        bank: Int,
        program: Int,
        updatedAt: Double
    ) {
        self.patchId = patchId
        self.patchName = patchName
        self.bank = bank
        self.program = program
        self.updatedAt = updatedAt
    }
}

public struct HarnessKeyboardStatePayload: Codable, Equatable {
    public let profileId: String
    public let profileName: String
    public let page: Int
    public let pageName: String
    public let hostLink: String
    public let clockMaster: Bool
    public let clockBpm: Double
    public let transportRunning: Bool
    public let patch: HarnessKeyboardPatchSnapshot
    public let cueVersion: Int?
    public let activeScene: String?
    public let updatedAt: Double

    public init(
        profileId: String,
        profileName: String,
        page: Int,
        pageName: String,
        hostLink: String,
        clockMaster: Bool,
        clockBpm: Double,
        transportRunning: Bool,
        patch: HarnessKeyboardPatchSnapshot,
        cueVersion: Int? = nil,
        activeScene: String? = nil,
        updatedAt: Double
    ) {
        self.profileId = profileId
        self.profileName = profileName
        self.page = page
        self.pageName = pageName
        self.hostLink = hostLink
        self.clockMaster = clockMaster
        self.clockBpm = clockBpm
        self.transportRunning = transportRunning
        self.patch = patch
        self.cueVersion = cueVersion
        self.activeScene = activeScene
        self.updatedAt = updatedAt
    }
}

public struct HarnessKeyboardPatchChangePayload: Codable, Equatable {
    public let patchId: String
    public let patchName: String?
    public let bank: Int
    public let program: Int
    public let source: String
    public let updatedAt: Double

    public init(
        patchId: String,
        patchName: String? = nil,
        bank: Int,
        program: Int,
        source: String,
        updatedAt: Double
    ) {
        self.patchId = patchId
        self.patchName = patchName
        self.bank = bank
        self.program = program
        self.source = source
        self.updatedAt = updatedAt
    }
}

public struct HarnessVoiceStreamDescriptor: Codable, Equatable {
    public let voiceId: String
    public let trackId: String
    public let sessionId: String
    public let token: String?
    public let codec: String
    public let expiresAt: Double
    public let streamUrl: String?
    public let fallbackGroup: String?

    public init(
        voiceId: String,
        trackId: String,
        sessionId: String,
        token: String? = nil,
        codec: String,
        expiresAt: Double,
        streamUrl: String? = nil,
        fallbackGroup: String? = nil
    ) {
        self.voiceId = voiceId
        self.trackId = trackId
        self.sessionId = sessionId
        self.token = token
        self.codec = codec
        self.expiresAt = expiresAt
        self.streamUrl = streamUrl
        self.fallbackGroup = fallbackGroup
    }
}

public struct HarnessGroupStemDescriptor: Codable, Equatable {
    public let groupId: String
    public let sessionId: String
    public let token: String?
    public let codec: String
    public let expiresAt: Double
    public let streamUrl: String?

    public init(
        groupId: String,
        sessionId: String,
        token: String? = nil,
        codec: String,
        expiresAt: Double,
        streamUrl: String? = nil
    ) {
        self.groupId = groupId
        self.sessionId = sessionId
        self.token = token
        self.codec = codec
        self.expiresAt = expiresAt
        self.streamUrl = streamUrl
    }
}

public struct HarnessVoiceStreamStartPayload: Codable, Equatable {
    public let commandId: String
    public let hashedId: String
    public let note: Int?
    public let velocity: Double?
    public let renderHints: HarnessPhoneAudioCommandPayload.RenderHints?
    public let stream: HarnessVoiceStreamDescriptor
    public let issuedAt: Double

    public init(
        commandId: String,
        hashedId: String,
        note: Int? = nil,
        velocity: Double? = nil,
        renderHints: HarnessPhoneAudioCommandPayload.RenderHints? = nil,
        stream: HarnessVoiceStreamDescriptor,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.hashedId = hashedId
        self.note = note
        self.velocity = velocity
        self.renderHints = renderHints
        self.stream = stream
        self.issuedAt = issuedAt
    }
}

public struct HarnessVoiceStreamStopPayload: Codable, Equatable {
    public let commandId: String
    public let hashedId: String
    public let voiceId: String
    public let trackId: String
    public let note: Int?
    public let reason: String?
    public let issuedAt: Double

    public init(
        commandId: String,
        hashedId: String,
        voiceId: String,
        trackId: String,
        note: Int? = nil,
        reason: String? = nil,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.hashedId = hashedId
        self.voiceId = voiceId
        self.trackId = trackId
        self.note = note
        self.reason = reason
        self.issuedAt = issuedAt
    }
}

public struct HarnessGroupStemStartPayload: Codable, Equatable {
    public let commandId: String
    public let hashedIds: [String]
    public let group: HarnessGroupStemDescriptor
    public let reason: String?
    public let issuedAt: Double

    public init(
        commandId: String,
        hashedIds: [String],
        group: HarnessGroupStemDescriptor,
        reason: String? = nil,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.hashedIds = hashedIds
        self.group = group
        self.reason = reason
        self.issuedAt = issuedAt
    }
}

public struct HarnessGroupStemStopPayload: Codable, Equatable {
    public let commandId: String
    public let hashedIds: [String]
    public let groupId: String
    public let reason: String?
    public let issuedAt: Double

    public init(
        commandId: String,
        hashedIds: [String],
        groupId: String,
        reason: String? = nil,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.hashedIds = hashedIds
        self.groupId = groupId
        self.reason = reason
        self.issuedAt = issuedAt
    }
}
