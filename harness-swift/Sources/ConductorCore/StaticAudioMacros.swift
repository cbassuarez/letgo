import Foundation

public enum SampleRenderClass: String, Codable, CaseIterable, Sendable {
    case percussion
    case tonal
    case texture
    case vocal
    case misc
}

public enum SampleDepthClass: String, Codable, CaseIterable, Sendable {
    case transient
    case balanced
    case texture
}

public enum UltrachunkTwistLane: String, Codable, CaseIterable, Sendable {
    case neutral
    case spectral
    case crusher
}

public struct SampleAtlasEntry: Equatable, Sendable, Identifiable {
    public var id: String { sampleID }
    public var sampleID: String
    public var region: Int
    public var depthClass: SampleDepthClass
    public var isLongTexture: Bool

    public init(
        sampleID: String,
        region: Int,
        depthClass: SampleDepthClass,
        isLongTexture: Bool
    ) {
        self.sampleID = sampleID
        self.region = max(0, region)
        self.depthClass = depthClass
        self.isLongTexture = isLongTexture
    }
}

public struct UltrachunkControlFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var twist: Double
    public var speed: Double
    public var timestamp: TimeInterval

    public static let neutral = UltrachunkControlFrame(
        x: 0.5,
        y: 0.5,
        twist: 0.5,
        speed: 0,
        timestamp: Date().timeIntervalSince1970 * 1_000
    )

    public init(
        x: Double,
        y: Double,
        twist: Double,
        speed: Double,
        timestamp: TimeInterval
    ) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
        self.twist = min(1, max(0, twist))
        self.speed = min(1, max(0, speed))
        self.timestamp = timestamp
    }
}

public struct UltrachunkVoiceRecipe: Codable, Equatable, Sendable {
    public var sampleID: String
    public var startNormalized: Double
    public var chunkWindowMs: Double
    public var jitterMs: Double
    public var rate: Double
    public var gain: Double
    public var releaseMs: Double
    public var density: Double

    public init(
        sampleID: String,
        startNormalized: Double,
        chunkWindowMs: Double,
        jitterMs: Double,
        rate: Double,
        gain: Double,
        releaseMs: Double,
        density: Double
    ) {
        self.sampleID = sampleID
        self.startNormalized = min(1, max(0, startNormalized))
        self.chunkWindowMs = min(2_000, max(12, chunkWindowMs))
        self.jitterMs = min(960, max(0, jitterMs))
        self.rate = min(3, max(0.12, rate))
        self.gain = min(1, max(0, gain))
        self.releaseMs = min(2_400, max(8, releaseMs))
        self.density = min(1, max(0, density))
    }
}

public struct UltrachunkDSPState: Codable, Equatable, Sendable {
    public var twistLane: UltrachunkTwistLane
    public var spectralAmount: Double
    public var crushAmount: Double
    public var downsampleFactor: Double
    public var bitDepth: Double

    public static let neutral = UltrachunkDSPState(
        twistLane: .neutral,
        spectralAmount: 0,
        crushAmount: 0,
        downsampleFactor: 1,
        bitDepth: 16
    )

    public init(
        twistLane: UltrachunkTwistLane,
        spectralAmount: Double,
        crushAmount: Double,
        downsampleFactor: Double,
        bitDepth: Double
    ) {
        self.twistLane = twistLane
        self.spectralAmount = min(1, max(0, spectralAmount))
        self.crushAmount = min(1, max(0, crushAmount))
        self.downsampleFactor = min(24, max(1, downsampleFactor))
        self.bitDepth = min(24, max(2, bitDepth))
    }
}

public struct UltrachunkQualityProfile: Codable, Equatable, Sendable {
    public var maxVoices: Int
    public var maxChunkWindowMs: Double
    public var minChunkWindowMs: Double

    public static let maxQuality = UltrachunkQualityProfile(
        maxVoices: 24,
        maxChunkWindowMs: 640,
        minChunkWindowMs: 18
    )

    public init(
        maxVoices: Int,
        maxChunkWindowMs: Double,
        minChunkWindowMs: Double
    ) {
        self.maxVoices = max(2, min(64, maxVoices))
        self.maxChunkWindowMs = min(2_000, max(30, maxChunkWindowMs))
        self.minChunkWindowMs = min(self.maxChunkWindowMs, max(8, minChunkWindowMs))
    }
}

public enum UltrachunkMapping {
    public static func granularity(forSpeed speed: Double) -> Double {
        let normalized = remap01(speed, min: 0.02, max: 0.92)
        return smoothstep01(normalized)
    }

    public static func intensity(forSpeed speed: Double) -> Double {
        let normalized = remap01(speed, min: 0.015, max: 0.96)
        return min(1, max(0, pow(normalized, 0.78)))
    }

    public static func twistDSPState(
        twistNormalized: Double,
        intensity: Double,
        spaceBoost: Double = 0
    ) -> UltrachunkDSPState {
        let signed = (clamp01(twistNormalized) - 0.5) * 2
        let deadband = 0.09
        if signed > deadband {
            let normalized = remap01(signed, min: deadband, max: 1)
            let spectral = clamp01((normalized * 0.82) + (spaceBoost * 0.26) + (intensity * 0.14))
            return UltrachunkDSPState(
                twistLane: .spectral,
                spectralAmount: spectral,
                crushAmount: 0,
                downsampleFactor: 1,
                bitDepth: 16
            )
        }
        if signed < -deadband {
            let normalized = remap01(-signed, min: deadband, max: 1)
            let crush = clamp01((normalized * 0.88) + (intensity * 0.28))
            let downsample = 1 + (crush * 11)
            let bitDepth = max(4, 16 - (crush * 11))
            return UltrachunkDSPState(
                twistLane: .crusher,
                spectralAmount: 0,
                crushAmount: crush,
                downsampleFactor: downsample,
                bitDepth: bitDepth
            )
        }
        return .neutral
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func remap01(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return value >= max ? 1 : 0 }
        return clamp01((value - min) / (max - min))
    }

    private static func smoothstep01(_ value: Double) -> Double {
        let t = clamp01(value)
        return t * t * (3 - (2 * t))
    }
}

public struct SampleMetadata: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var renderClass: SampleRenderClass
    public var key: String?
    public var bpm: Double?
    public var energy: Double
    public var timbre: Double
    public var isLoop: Bool

    public init(
        id: String,
        renderClass: SampleRenderClass = .misc,
        key: String? = nil,
        bpm: Double? = nil,
        energy: Double = 0.5,
        timbre: Double = 0.5,
        isLoop: Bool = false
    ) {
        self.id = id
        self.renderClass = renderClass
        self.key = key
        self.bpm = bpm
        self.energy = min(1, max(0, energy))
        self.timbre = min(1, max(0, timbre))
        self.isLoop = isLoop
    }
}

public struct StaticAudioMacroState: Codable, Equatable, Sendable {
    public var sampleMorph: Double
    public var articulation: Double
    public var timbre: Double
    public var textureSend: Double

    public static let neutral = StaticAudioMacroState(
        sampleMorph: 0.5,
        articulation: 0.5,
        timbre: 0.5,
        textureSend: 0.0
    )

    public init(
        sampleMorph: Double,
        articulation: Double,
        timbre: Double,
        textureSend: Double
    ) {
        self.sampleMorph = min(1, max(0, sampleMorph))
        self.articulation = min(1, max(0, articulation))
        self.timbre = min(1, max(0, timbre))
        self.textureSend = min(1, max(0, textureSend))
    }
}

public struct EffectsMacroFrame: Codable, Equatable, Sendable {
    public var chainAIntensity: Double
    public var chainBIntensity: Double
    public var articulation: Double
    public var timbre: Double
    public var textureSend: Double

    public init(
        chainAIntensity: Double,
        chainBIntensity: Double,
        articulation: Double,
        timbre: Double,
        textureSend: Double
    ) {
        self.chainAIntensity = min(1, max(0, chainAIntensity))
        self.chainBIntensity = min(1, max(0, chainBIntensity))
        self.articulation = min(1, max(0, articulation))
        self.timbre = min(1, max(0, timbre))
        self.textureSend = min(1, max(0, textureSend))
    }
}

public struct EffectsChainPreset: Codable, Equatable, Sendable {
    public var chainAName: String
    public var chainBName: String
    public var bankID: Int
    public var renderClass: SampleRenderClass

    public init(
        chainAName: String,
        chainBName: String,
        bankID: Int,
        renderClass: SampleRenderClass = .misc
    ) {
        self.chainAName = chainAName
        self.chainBName = chainBName
        self.bankID = min(3, max(1, bankID))
        self.renderClass = renderClass
    }
}

public struct ChoirFieldState: Codable, Equatable, Sendable {
    public var spread: Double
    public var depth: Double
    public var detune: Double

    public static let neutral = ChoirFieldState(spread: 0.5, depth: 0.5, detune: 0.5)

    public init(spread: Double, depth: Double, detune: Double) {
        self.spread = min(1, max(0, spread))
        self.depth = min(1, max(0, depth))
        self.detune = min(1, max(0, detune))
    }
}

public final class SampleMorphEngine {
    public init() {}

    public func resolveSampleID(
        morph: Double,
        candidateIDs: [String],
        metadata: [String: SampleMetadata]
    ) -> String? {
        guard !candidateIDs.isEmpty else { return nil }
        let normalizedMorph = min(1, max(0, morph))
        let sorted = candidateIDs.sorted { lhs, rhs in
            let l = metadata[lhs]
            let r = metadata[rhs]
            let lEnergy = l?.energy ?? 0.5
            let rEnergy = r?.energy ?? 0.5
            if abs(lEnergy - rEnergy) > 0.0001 {
                return lEnergy < rEnergy
            }
            let lTimbre = l?.timbre ?? 0.5
            let rTimbre = r?.timbre ?? 0.5
            if abs(lTimbre - rTimbre) > 0.0001 {
                return lTimbre < rTimbre
            }
            return lhs < rhs
        }

        let maxIndex = max(0, sorted.count - 1)
        let index = Int((normalizedMorph * Double(maxIndex)).rounded())
        return sorted[min(max(0, index), maxIndex)]
    }
}
