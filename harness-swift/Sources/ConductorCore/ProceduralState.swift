import Foundation

public enum TransitionMode: String, Codable, CaseIterable, Sendable {
    case cut
    case crossfade
    case stutter
    case fade
}

public enum CompositorPreset: String, Codable, CaseIterable, Sendable {
    case blend
    case multiply
    case screen
    case mask
    case pip
    case stutter
}

public enum SplitLayout: String, Codable, CaseIterable, Sendable {
    case none
    case split2 = "split-2"
    case split3 = "split-3"
    case split4 = "split-4"
    case pip
}

public struct DynamicBinClip: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var mediaRef: String
    public var tags: [String]
    public var weight: Double
    public var scopes: [String]

    public init(
        id: String,
        mediaRef: String,
        tags: [String] = [],
        weight: Double = 1,
        scopes: [String] = []
    ) {
        self.id = id
        self.mediaRef = mediaRef
        self.tags = tags
        self.weight = max(0, weight)
        self.scopes = scopes
    }
}

public struct TextBlendState: Codable, Equatable, Sendable {
    public var mode: String
    public var probability: Double
    public var strictRatio: Double
    public var looseRatio: Double

    public init(
        mode: String = "always-mixed",
        probability: Double,
        strictRatio: Double
    ) {
        self.mode = mode
        self.probability = clamp01(probability)
        self.strictRatio = clamp01(strictRatio)
        self.looseRatio = clamp01(1 - self.strictRatio)
    }
}

public struct ProgramProceduralState: Codable, Equatable, Sendable {
    public var epoch: Int
    public var seed: Int
    public var updatedAt: TimeInterval
    public var dynamicBinSelection: Double
    public var dynamicBinIndex: Int
    public var dynamicBinClipId: String?
    public var dynamicBinManifest: [DynamicBinClip]
    public var cutCadence: Double
    public var transitionMode: TransitionMode
    public var compositorPreset: CompositorPreset
    public var splitLayout: SplitLayout
    public var fade: Double
    public var textProbability: Double
    public var strictLooseBlend: Double
    public var visualVariance: Double
    public var crowdSteeringLevel: Double
    public var promptInfluence: Double?
    public var directPickInfluence: Double?
    public var echoProbabilityGlobal: Double?
    public var echoProbabilityByStem: [String: Double]?
    public var performerVector: ParamVector
    public var audienceVector: ParamVector
    public var textBlend: TextBlendState

    public init(
        epoch: Int,
        seed: Int,
        updatedAt: TimeInterval,
        dynamicBinSelection: Double,
        dynamicBinIndex: Int,
        dynamicBinClipId: String?,
        dynamicBinManifest: [DynamicBinClip],
        cutCadence: Double,
        transitionMode: TransitionMode,
        compositorPreset: CompositorPreset,
        splitLayout: SplitLayout,
        fade: Double,
        textProbability: Double,
        strictLooseBlend: Double,
        visualVariance: Double,
        crowdSteeringLevel: Double,
        promptInfluence: Double? = nil,
        directPickInfluence: Double? = nil,
        echoProbabilityGlobal: Double? = nil,
        echoProbabilityByStem: [String: Double]? = nil,
        performerVector: ParamVector,
        audienceVector: ParamVector
    ) {
        self.epoch = max(0, epoch)
        self.seed = seed
        self.updatedAt = updatedAt
        self.dynamicBinSelection = clamp01(dynamicBinSelection)
        self.dynamicBinIndex = max(0, dynamicBinIndex)
        self.dynamicBinClipId = dynamicBinClipId
        self.dynamicBinManifest = dynamicBinManifest
        self.cutCadence = clamp01(cutCadence)
        self.transitionMode = transitionMode
        self.compositorPreset = compositorPreset
        self.splitLayout = splitLayout
        self.fade = clamp01(fade)
        self.textProbability = clamp01(textProbability)
        self.strictLooseBlend = clamp01(strictLooseBlend)
        self.visualVariance = clamp01(visualVariance)
        self.crowdSteeringLevel = clamp01(crowdSteeringLevel)
        self.promptInfluence = promptInfluence.map(clamp01)
        self.directPickInfluence = directPickInfluence.map(clamp01)
        self.echoProbabilityGlobal = echoProbabilityGlobal.map(clamp01)
        self.echoProbabilityByStem = echoProbabilityByStem?.reduce(into: [String: Double]()) { result, element in
            result[element.key] = clamp01(element.value)
        }
        self.performerVector = performerVector
        self.audienceVector = audienceVector
        self.textBlend = TextBlendState(
            probability: self.textProbability,
            strictRatio: self.strictLooseBlend
        )
    }

    public static func `default`(seed: Int = Int(Date().timeIntervalSince1970)) -> ProgramProceduralState {
        ProgramProceduralState(
            epoch: 0,
            seed: seed,
            updatedAt: Date().timeIntervalSince1970 * 1000,
            dynamicBinSelection: 0.5,
            dynamicBinIndex: 0,
            dynamicBinClipId: nil,
            dynamicBinManifest: [],
            cutCadence: 0.5,
            transitionMode: .cut,
            compositorPreset: .blend,
            splitLayout: .none,
            fade: 0.0,
            textProbability: 0.5,
            strictLooseBlend: 0.5,
            visualVariance: 0.5,
            crowdSteeringLevel: 0,
            promptInfluence: 0,
            directPickInfluence: 0,
            echoProbabilityGlobal: 0,
            echoProbabilityByStem: [
                "pads": 0,
                "hotas": 0,
                "choir": 0,
                "fx": 0
            ],
            performerVector: .neutral,
            audienceVector: .neutral
        )
    }

    public mutating func updateBlend() {
        textBlend = TextBlendState(probability: textProbability, strictRatio: strictLooseBlend)
    }
}

private func clamp01(_ value: Double) -> Double {
    min(1, max(0, value))
}
