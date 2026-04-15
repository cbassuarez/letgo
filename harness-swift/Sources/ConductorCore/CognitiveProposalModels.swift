import Foundation

public enum ProposalLane: String, Codable, CaseIterable, Sendable {
    case audio
    case visualText = "visual_text"
}

public struct StateDevelopmentMetrics: Codable, Equatable, Sendable {
    public var repeatability: Double
    public var intensityTrend: Double
    public var noveltySaturation: Double
    public var headroom: Double
    public var safetyContext: Double
    public var stateDevelopmentIndex: Double
    public var interventionNeedScore: Double
    public var updatedAt: TimeInterval

    public static let neutral = StateDevelopmentMetrics(
        repeatability: 0,
        intensityTrend: 0,
        noveltySaturation: 0,
        headroom: 1,
        safetyContext: 0,
        stateDevelopmentIndex: 0,
        interventionNeedScore: 0,
        updatedAt: Date().timeIntervalSince1970 * 1000
    )

    public init(
        repeatability: Double,
        intensityTrend: Double,
        noveltySaturation: Double,
        headroom: Double,
        safetyContext: Double,
        stateDevelopmentIndex: Double,
        interventionNeedScore: Double,
        updatedAt: TimeInterval
    ) {
        self.repeatability = Self.clamp01(repeatability)
        self.intensityTrend = Self.clamp01(intensityTrend)
        self.noveltySaturation = Self.clamp01(noveltySaturation)
        self.headroom = Self.clamp01(headroom)
        self.safetyContext = Self.clamp01(safetyContext)
        self.stateDevelopmentIndex = Self.clamp01(stateDevelopmentIndex)
        self.interventionNeedScore = Self.clamp01(interventionNeedScore)
        self.updatedAt = updatedAt
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public enum AudioProposalKind: String, Codable, CaseIterable, Sendable {
    case textureNudge = "texture_nudge"
    case structuredLatch = "structured_latch"
}

public struct MLProposalPayloadAudio: Codable, Equatable, Sendable {
    public var kind: AudioProposalKind
    public var suggestedBank: Int?
    public var suggestedSampleID: String?
    public var chainAIntensityTarget: Double?
    public var chainBIntensityTarget: Double?
    public var densityTarget: Double?
    public var latchSuggested: Bool

    public init(
        kind: AudioProposalKind,
        suggestedBank: Int? = nil,
        suggestedSampleID: String? = nil,
        chainAIntensityTarget: Double? = nil,
        chainBIntensityTarget: Double? = nil,
        densityTarget: Double? = nil,
        latchSuggested: Bool
    ) {
        self.kind = kind
        self.suggestedBank = suggestedBank.map { min(3, max(1, $0)) }
        self.suggestedSampleID = suggestedSampleID
        self.chainAIntensityTarget = chainAIntensityTarget.map(Self.clamp01)
        self.chainBIntensityTarget = chainBIntensityTarget.map(Self.clamp01)
        self.densityTarget = densityTarget.map(Self.clamp01)
        self.latchSuggested = latchSuggested
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public struct MLProposalPayloadVisualText: Codable, Equatable, Sendable {
    public var dynamicBinSelection: Double?
    public var transitionMode: TransitionMode?
    public var compositorPreset: CompositorPreset?
    public var splitLayout: SplitLayout?
    public var fade: Double?
    public var textProbability: Double?
    public var strictLooseBlend: Double?

    public init(
        dynamicBinSelection: Double? = nil,
        transitionMode: TransitionMode? = nil,
        compositorPreset: CompositorPreset? = nil,
        splitLayout: SplitLayout? = nil,
        fade: Double? = nil,
        textProbability: Double? = nil,
        strictLooseBlend: Double? = nil
    ) {
        self.dynamicBinSelection = dynamicBinSelection.map(Self.clamp01)
        self.transitionMode = transitionMode
        self.compositorPreset = compositorPreset
        self.splitLayout = splitLayout
        self.fade = fade.map(Self.clamp01)
        self.textProbability = textProbability.map(Self.clamp01)
        self.strictLooseBlend = strictLooseBlend.map(Self.clamp01)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public struct MLProposal: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var lane: ProposalLane
    public var confidence: Double
    public var rationale: String
    public var expectedEffect: String
    public var timeoutMs: TimeInterval
    public var createdAt: TimeInterval
    public var audio: MLProposalPayloadAudio?
    public var visualText: MLProposalPayloadVisualText?

    public init(
        id: String,
        lane: ProposalLane,
        confidence: Double,
        rationale: String,
        expectedEffect: String,
        timeoutMs: TimeInterval,
        createdAt: TimeInterval,
        audio: MLProposalPayloadAudio? = nil,
        visualText: MLProposalPayloadVisualText? = nil
    ) {
        self.id = id
        self.lane = lane
        self.confidence = min(1, max(0, confidence))
        self.rationale = rationale
        self.expectedEffect = expectedEffect
        self.timeoutMs = max(400, timeoutMs)
        self.createdAt = createdAt
        self.audio = audio
        self.visualText = visualText
    }

    public var expiresAt: TimeInterval {
        createdAt + timeoutMs
    }
}

public enum MLProposalDecision: String, Codable, CaseIterable, Sendable {
    case accepted
    case expired
    case rejected
    case blocked
}

public enum AudioStemID: String, Codable, CaseIterable, Sendable {
    case master
    case mainSamples = "main_samples"
    case synthAmbient = "synth_ambient"
    case choir
    case ipadIn = "ipad_in"
}

public struct AudioStemFeatureFrame: Codable, Equatable, Sendable, Identifiable {
    public var id: String { stem.rawValue }

    public var stem: AudioStemID
    public var rms: Double
    public var spectralCentroid: Double
    public var flux: Double
    public var transientDensity: Double

    public init(
        stem: AudioStemID,
        rms: Double,
        spectralCentroid: Double,
        flux: Double,
        transientDensity: Double
    ) {
        self.stem = stem
        self.rms = Self.clamp01(rms)
        self.spectralCentroid = Self.clamp01(spectralCentroid)
        self.flux = Self.clamp01(flux)
        self.transientDensity = Self.clamp01(transientDensity)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public struct ProgramAudioState: Codable, Equatable, Sendable {
    public var epoch: Int
    public var updatedAt: TimeInterval
    public var activeSampleBank: Int
    public var activeChoirSampleBank: Int
    public var choirContextActive: Bool
    public var phoneGateCommitted: Bool
    public var estimatedDensity: Double
    public var effects: EffectsChainState
    public var master: QuadAudioFeatures
    public var stems: [AudioStemFeatureFrame]
    public var activeProposalID: String?
    public var structuredLatchActive: Bool
    public var staticMacros: StaticAudioMacroState
    public var choirField: ChoirFieldState
    public var staticVisualOverrideHeld: Bool
    public var ultrachunkFrame: UltrachunkControlFrame
    public var ultrachunkDSPState: UltrachunkDSPState
    public var ultrachunkPrimarySampleID: String?
    public var ultrachunkSecondarySampleID: String?

    public static let `default` = ProgramAudioState(
        epoch: 0,
        updatedAt: Date().timeIntervalSince1970 * 1000,
        activeSampleBank: 1,
        activeChoirSampleBank: 1,
        choirContextActive: false,
        phoneGateCommitted: false,
        estimatedDensity: 0,
        effects: .idle,
        master: .zero,
        stems: [],
        activeProposalID: nil,
        structuredLatchActive: false,
        staticMacros: .neutral,
        choirField: .neutral,
        staticVisualOverrideHeld: false,
        ultrachunkFrame: .neutral,
        ultrachunkDSPState: .neutral,
        ultrachunkPrimarySampleID: nil,
        ultrachunkSecondarySampleID: nil
    )

    public init(
        epoch: Int,
        updatedAt: TimeInterval,
        activeSampleBank: Int,
        activeChoirSampleBank: Int,
        choirContextActive: Bool,
        phoneGateCommitted: Bool,
        estimatedDensity: Double,
        effects: EffectsChainState,
        master: QuadAudioFeatures,
        stems: [AudioStemFeatureFrame],
        activeProposalID: String?,
        structuredLatchActive: Bool,
        staticMacros: StaticAudioMacroState,
        choirField: ChoirFieldState,
        staticVisualOverrideHeld: Bool,
        ultrachunkFrame: UltrachunkControlFrame = .neutral,
        ultrachunkDSPState: UltrachunkDSPState = .neutral,
        ultrachunkPrimarySampleID: String? = nil,
        ultrachunkSecondarySampleID: String? = nil
    ) {
        self.epoch = max(0, epoch)
        self.updatedAt = updatedAt
        self.activeSampleBank = min(3, max(1, activeSampleBank))
        self.activeChoirSampleBank = min(3, max(1, activeChoirSampleBank))
        self.choirContextActive = choirContextActive
        self.phoneGateCommitted = phoneGateCommitted
        self.estimatedDensity = min(1, max(0, estimatedDensity))
        self.effects = effects
        self.master = master
        self.stems = stems
        self.activeProposalID = activeProposalID
        self.structuredLatchActive = structuredLatchActive
        self.staticMacros = staticMacros
        self.choirField = choirField
        self.staticVisualOverrideHeld = staticVisualOverrideHeld
        self.ultrachunkFrame = ultrachunkFrame
        self.ultrachunkDSPState = ultrachunkDSPState
        self.ultrachunkPrimarySampleID = ultrachunkPrimarySampleID
        self.ultrachunkSecondarySampleID = ultrachunkSecondarySampleID
    }
}
