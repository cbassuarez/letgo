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

public enum HarnessTextSemanticMode: String, Codable, Equatable, CaseIterable {
    case off
    case openai
}

public struct HarnessRuntimeScriptCandidate: Codable, Equatable {
    public let id: String?
    public let text: String
    public let weight: Double?

    public init(id: String? = nil, text: String, weight: Double? = nil) {
        self.id = id
        self.text = text
        self.weight = weight
    }
}

public struct HarnessTextModelHealthPayload: Codable, Equatable {
    public let active: Bool
    public let summary: String
    public let modelPath: String?
    public let source: String
    public let sourceLabel: String?
    public let version: String?
    public let lastLoadedAt: Double?
    public let runtimeFailures: Int

    public init(
        active: Bool,
        summary: String,
        modelPath: String?,
        source: String,
        sourceLabel: String? = nil,
        version: String? = nil,
        lastLoadedAt: Double? = nil,
        runtimeFailures: Int
    ) {
        self.active = active
        self.summary = summary
        self.modelPath = modelPath
        self.source = source
        self.sourceLabel = sourceLabel
        self.version = version
        self.lastLoadedAt = lastLoadedAt
        self.runtimeFailures = runtimeFailures
    }
}

public struct HarnessTextSemanticStatusPayload: Codable, Equatable {
    public let mode: HarnessTextSemanticMode
    public let enabled: Bool
    public let provider: String
    public let model: String?
    public let apiKeyConfigured: Bool?
    public let refreshMs: Double
    public let ttlMs: Double
    public let timeoutMs: Double
    public let cacheEntries: Int
    public let inFlight: Int
    public let lastSuccessAt: Double?
    public let lastError: String?

    public init(
        mode: HarnessTextSemanticMode,
        enabled: Bool,
        provider: String,
        model: String? = nil,
        apiKeyConfigured: Bool? = nil,
        refreshMs: Double,
        ttlMs: Double,
        timeoutMs: Double,
        cacheEntries: Int,
        inFlight: Int,
        lastSuccessAt: Double? = nil,
        lastError: String? = nil
    ) {
        self.mode = mode
        self.enabled = enabled
        self.provider = provider
        self.model = model
        self.apiKeyConfigured = apiKeyConfigured
        self.refreshMs = refreshMs
        self.ttlMs = ttlMs
        self.timeoutMs = timeoutMs
        self.cacheEntries = cacheEntries
        self.inFlight = inFlight
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
    }
}

public struct HarnessTextRuntimeStatusPayload: Codable, Equatable {
    public let updatedAt: Double
    public let strictCount: Int
    public let looseCount: Int
    public let strictSource: String
    public let looseSource: String
    public let warnings: [String]
    public let modelHealth: HarnessTextModelHealthPayload?
    public let semantic: HarnessTextSemanticStatusPayload?

    public init(
        updatedAt: Double,
        strictCount: Int,
        looseCount: Int,
        strictSource: String,
        looseSource: String,
        warnings: [String] = [],
        modelHealth: HarnessTextModelHealthPayload? = nil,
        semantic: HarnessTextSemanticStatusPayload? = nil
    ) {
        self.updatedAt = updatedAt
        self.strictCount = strictCount
        self.looseCount = looseCount
        self.strictSource = strictSource
        self.looseSource = looseSource
        self.warnings = warnings
        self.modelHealth = modelHealth
        self.semantic = semantic
    }
}

public struct HarnessTextRuntimeUpdatePayload: Codable, Equatable {
    public let requestStatus: Bool?
    public let reload: Bool?
    public let strictCandidates: [HarnessRuntimeScriptCandidate]?
    public let looseCandidates: [HarnessRuntimeScriptCandidate]?
    public let modelPayloadJSON: String?
    public let semanticMode: HarnessTextSemanticMode?
    public let semanticApiKey: String?
    public let semanticModel: String?

    public init(
        requestStatus: Bool? = nil,
        reload: Bool? = nil,
        strictCandidates: [HarnessRuntimeScriptCandidate]? = nil,
        looseCandidates: [HarnessRuntimeScriptCandidate]? = nil,
        modelPayloadJSON: String? = nil,
        semanticMode: HarnessTextSemanticMode? = nil,
        semanticApiKey: String? = nil,
        semanticModel: String? = nil
    ) {
        self.requestStatus = requestStatus
        self.reload = reload
        self.strictCandidates = strictCandidates
        self.looseCandidates = looseCandidates
        self.modelPayloadJSON = modelPayloadJSON
        self.semanticMode = semanticMode
        self.semanticApiKey = semanticApiKey
        self.semanticModel = semanticModel
    }
}

public struct HarnessVoiceStreamDescriptor: Codable, Equatable {
    public let voiceId: String
    public let trackId: String
    public let sessionId: String
    public let token: String?
    public let codec: String
    public let transport: String?
    public let expiresAt: Double
    public let streamUrl: String?
    public let fallbackGroup: String?
    public let webrtc: HarnessVoiceStreamWebRTCDescriptor?

    public init(
        voiceId: String,
        trackId: String,
        sessionId: String,
        token: String? = nil,
        codec: String,
        transport: String? = nil,
        expiresAt: Double,
        streamUrl: String? = nil,
        fallbackGroup: String? = nil,
        webrtc: HarnessVoiceStreamWebRTCDescriptor? = nil
    ) {
        self.voiceId = voiceId
        self.trackId = trackId
        self.sessionId = sessionId
        self.token = token
        self.codec = codec
        self.transport = transport
        self.expiresAt = expiresAt
        self.streamUrl = streamUrl
        self.fallbackGroup = fallbackGroup
        self.webrtc = webrtc
    }
}

public struct HarnessGroupStemDescriptor: Codable, Equatable {
    public let groupId: String
    public let sessionId: String
    public let token: String?
    public let codec: String
    public let transport: String?
    public let expiresAt: Double
    public let streamUrl: String?
    public let webrtc: HarnessVoiceStreamWebRTCDescriptor?

    public init(
        groupId: String,
        sessionId: String,
        token: String? = nil,
        codec: String,
        transport: String? = nil,
        expiresAt: Double,
        streamUrl: String? = nil,
        webrtc: HarnessVoiceStreamWebRTCDescriptor? = nil
    ) {
        self.groupId = groupId
        self.sessionId = sessionId
        self.token = token
        self.codec = codec
        self.transport = transport
        self.expiresAt = expiresAt
        self.streamUrl = streamUrl
        self.webrtc = webrtc
    }
}

public struct HarnessVoiceStreamWebRTCDescriptor: Codable, Equatable {
    public struct IceServer: Codable, Equatable {
        public let urls: [String]
        public let username: String?
        public let credential: String?

        public init(urls: [String], username: String? = nil, credential: String? = nil) {
            self.urls = urls
            self.username = username
            self.credential = credential
        }
    }

    public let roomId: String
    public let streamId: String
    public let publisherId: String?
    public let iceServers: [IceServer]?

    public init(
        roomId: String,
        streamId: String,
        publisherId: String? = nil,
        iceServers: [IceServer]? = nil
    ) {
        self.roomId = roomId
        self.streamId = streamId
        self.publisherId = publisherId
        self.iceServers = iceServers
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

public struct HarnessVoiceStreamSubscribePayload: Codable, Equatable {
    public let commandId: String
    public let hashedId: String
    public let voiceId: String
    public let trackId: String
    public let sessionId: String
    public let requestType: String
    public let transportId: String?
    public let rtpCapabilities: [String: String]?
    public let dtlsParameters: [String: String]?
    public let consumerId: String?
    public let issuedAt: Double

    public init(
        commandId: String,
        hashedId: String,
        voiceId: String,
        trackId: String,
        sessionId: String,
        requestType: String,
        transportId: String? = nil,
        rtpCapabilities: [String: String]? = nil,
        dtlsParameters: [String: String]? = nil,
        consumerId: String? = nil,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.hashedId = hashedId
        self.voiceId = voiceId
        self.trackId = trackId
        self.sessionId = sessionId
        self.requestType = requestType
        self.transportId = transportId
        self.rtpCapabilities = rtpCapabilities
        self.dtlsParameters = dtlsParameters
        self.consumerId = consumerId
        self.issuedAt = issuedAt
    }
}

public struct HarnessVoiceStreamSubscribedPayload: Codable, Equatable {
    public let commandId: String
    public let hashedId: String
    public let voiceId: String
    public let trackId: String
    public let sessionId: String
    public let requestType: String
    public let transportId: String?
    public let routerRtpCapabilities: [String: String]?
    public let transportOptions: [String: String]?
    public let consumerOptions: [String: String]?
    public let consumerId: String?
    public let issuedAt: Double

    public init(
        commandId: String,
        hashedId: String,
        voiceId: String,
        trackId: String,
        sessionId: String,
        requestType: String,
        transportId: String? = nil,
        routerRtpCapabilities: [String: String]? = nil,
        transportOptions: [String: String]? = nil,
        consumerOptions: [String: String]? = nil,
        consumerId: String? = nil,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.hashedId = hashedId
        self.voiceId = voiceId
        self.trackId = trackId
        self.sessionId = sessionId
        self.requestType = requestType
        self.transportId = transportId
        self.routerRtpCapabilities = routerRtpCapabilities
        self.transportOptions = transportOptions
        self.consumerOptions = consumerOptions
        self.consumerId = consumerId
        self.issuedAt = issuedAt
    }
}

public struct HarnessVoiceStreamUnsubscribePayload: Codable, Equatable {
    public let commandId: String
    public let hashedId: String
    public let voiceId: String
    public let trackId: String
    public let sessionId: String
    public let reason: String?
    public let issuedAt: Double

    public init(
        commandId: String,
        hashedId: String,
        voiceId: String,
        trackId: String,
        sessionId: String,
        reason: String? = nil,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.hashedId = hashedId
        self.voiceId = voiceId
        self.trackId = trackId
        self.sessionId = sessionId
        self.reason = reason
        self.issuedAt = issuedAt
    }
}

public struct HarnessVoiceStreamIceCandidatePayload: Codable, Equatable {
    public let commandId: String
    public let hashedId: String
    public let voiceId: String
    public let trackId: String
    public let sessionId: String
    public let transportId: String?
    public let candidate: String
    public let sdpMid: String?
    public let sdpMLineIndex: Int?
    public let issuedAt: Double

    public init(
        commandId: String,
        hashedId: String,
        voiceId: String,
        trackId: String,
        sessionId: String,
        transportId: String? = nil,
        candidate: String,
        sdpMid: String? = nil,
        sdpMLineIndex: Int? = nil,
        issuedAt: Double
    ) {
        self.commandId = commandId
        self.hashedId = hashedId
        self.voiceId = voiceId
        self.trackId = trackId
        self.sessionId = sessionId
        self.transportId = transportId
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
        self.issuedAt = issuedAt
    }
}

public struct HarnessVoicePublisherAnnouncePayload: Codable, Equatable {
    public struct Ingest: Codable, Equatable {
        public let ip: String
        public let port: Int
        public let rtcpPort: Int?
        public let payloadType: Int
        public let ssrc: Int
        public let mimeType: String
        public let clockRate: Int
        public let channels: Int

        public init(
            ip: String,
            port: Int,
            rtcpPort: Int? = nil,
            payloadType: Int,
            ssrc: Int,
            mimeType: String,
            clockRate: Int,
            channels: Int
        ) {
            self.ip = ip
            self.port = port
            self.rtcpPort = rtcpPort
            self.payloadType = payloadType
            self.ssrc = ssrc
            self.mimeType = mimeType
            self.clockRate = clockRate
            self.channels = channels
        }
    }

    public let publisherId: String
    public let sessionId: String
    public let trackId: String
    public let codec: String
    public let active: Bool
    public let ingest: Ingest?
    public let error: String?
    public let updatedAt: Double

    public init(
        publisherId: String,
        sessionId: String,
        trackId: String,
        codec: String,
        active: Bool,
        ingest: Ingest? = nil,
        error: String? = nil,
        updatedAt: Double
    ) {
        self.publisherId = publisherId
        self.sessionId = sessionId
        self.trackId = trackId
        self.codec = codec
        self.active = active
        self.ingest = ingest
        self.error = error
        self.updatedAt = updatedAt
    }
}
