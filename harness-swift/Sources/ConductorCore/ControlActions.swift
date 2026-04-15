import Foundation

public enum FlightOutputModeID: String, Codable, CaseIterable, Sendable {
    case off
    case `static`
    case dynamic
}

public enum SampleBankDomain: String, Codable, CaseIterable, Sendable {
    case main
    case choir
}

public enum EffectsChainID: String, Codable, CaseIterable, Sendable {
    case a
    case b
}

public struct EffectsChainState: Equatable, Codable, Sendable {
    public var chainAActive: Bool
    public var chainAIntensity: Double
    public var chainBActive: Bool
    public var chainBIntensity: Double

    public static let idle = EffectsChainState(
        chainAActive: false,
        chainAIntensity: 0,
        chainBActive: false,
        chainBIntensity: 0
    )

    public init(
        chainAActive: Bool,
        chainAIntensity: Double,
        chainBActive: Bool,
        chainBIntensity: Double
    ) {
        self.chainAActive = chainAActive
        self.chainAIntensity = min(1, max(0, chainAIntensity))
        self.chainBActive = chainBActive
        self.chainBIntensity = min(1, max(0, chainBIntensity))
    }

    public mutating func set(chain: EffectsChainID, active: Bool, intensity: Double) {
        let clamped = min(1, max(0, intensity))
        switch chain {
        case .a:
            chainAActive = active
            chainAIntensity = clamped
        case .b:
            chainBActive = active
            chainBIntensity = clamped
        }
    }
}

public enum ControlAction: Equatable, Sendable {
    case acceptActiveProposal
    case startEngine
    case stopEngine
    case patchVector(ParamVectorPatch)
    case armOutputMode(FlightOutputModeID)
    case armTransportLane(String)
    case queueTimelineStep(String)
    case setDynamicBinSelection(Double)
    case setCutCadence(Double)
    case setCompositorBlend(Double)
    case setStaticVisualOverrideHold(Bool)
    case setStaticSampleMorph(Double)
    case setStaticArticulation(Double)
    case setStaticTimbre(Double)
    case setStaticTextureSend(Double)
    case setChoirFieldSpread(Double)
    case setChoirFieldDepth(Double)
    case setChoirFieldDetune(Double)
    case setTextProbability(Double)
    case setStrictLooseBlend(Double)
    case setVisualVariance(Double)
    case contextualTake
    case setMasterArm(isArmed: Bool)
    case phoneGateTake
    case phoneGateGo
    case phoneGateSafe
    case togglePreviewPlayback
    case setSampleBank(Int, domain: SampleBankDomain)
    case setEffectsChain(chain: EffectsChainID, active: Bool, intensity: Double)
    case triggerPhoneChoirNoteOn
    case triggerPhoneChoirNoteOff
    case stopAllPhoneAudio
    case setPhoneChoirContextActive(Bool)
}
