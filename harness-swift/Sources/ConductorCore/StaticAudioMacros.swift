import Foundation

public enum SampleRenderClass: String, Codable, CaseIterable, Sendable {
    case percussion
    case tonal
    case texture
    case vocal
    case misc
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
