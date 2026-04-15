import ConductorCore
import Foundation

@MainActor
protocol ControlActionRouting: AnyObject {
    var isLatchArmed: Bool { get }
    var phoneAudioGateArmed: Bool { get }
    var hotasPhoneChoirContextActive: Bool { get }

    @discardableResult
    func acceptActiveProposalFromControl() -> MLProposalDecision
    func startEngineFromControl()
    func stopEngineFromControl()
    func canTakeArmedTimelineStep() -> Bool
    func takeArmedTimelineStep()
    func fireOutputGO()
    func goPhoneAudioGate()
    func patchVector(_ patch: ParamVectorPatch)
    func armOutputMode(_ mode: FlightOutputMode)
    func armTransportLane(_ laneId: String)
    func queueTimelineStepFromControl(_ laneId: String)
    func setDynamicBinSelectionFromControl(_ value: Double)
    func setCutCadenceFromControl(_ value: Double)
    func setCompositorBlendFromControl(_ value: Double)
    func setStaticVisualOverrideHoldFromControl(_ isHeld: Bool)
    func setStaticSampleMorphFromControl(_ value: Double)
    func setStaticArticulationFromControl(_ value: Double)
    func setStaticTimbreFromControl(_ value: Double)
    func setStaticTextureSendFromControl(_ value: Double)
    func setChoirFieldSpreadFromControl(_ value: Double)
    func setChoirFieldDepthFromControl(_ value: Double)
    func setChoirFieldDetuneFromControl(_ value: Double)
    func setTextProbabilityFromControl(_ value: Double)
    func setStrictLooseBlendFromControl(_ value: Double)
    func setVisualVarianceFromControl(_ value: Double)
    func toggleUltrachunkOverlayFromControl()
    func setMasterArmFromControl(_ isArmed: Bool)
    func takePhoneAudioGate()
    func safePhoneAudioGate()
    func togglePreviewPlayback()
    func setActiveSampleBankFromControl(_ bank: Int, domain: SampleBankDomain)
    func triggerPhoneChoirNoteOn()
    func triggerPhoneChoirNoteOff()
    func stopAllPhoneAudio()
    func setPhoneChoirContextActiveFromControl(_ active: Bool)
    func setEffectsChainFromControl(chain: EffectsChainID, active: Bool, intensity: Double)
}

@MainActor
final class ControlActionRouter {
    enum RouteResult: Equatable, Sendable {
        case applied
        case blocked(reason: String)
    }

    private weak var delegate: ControlActionRouting?
    private var lastCommitAtByKey: [String: TimeInterval] = [:]
    private let commitCooldownSeconds: TimeInterval

    init(delegate: ControlActionRouting, commitCooldownSeconds: TimeInterval = 0.12) {
        self.delegate = delegate
        self.commitCooldownSeconds = commitCooldownSeconds
    }

    @discardableResult
    func route(_ action: ControlAction) -> RouteResult {
        guard let delegate else {
            return .blocked(reason: "router delegate unavailable")
        }

        switch action {
        case .acceptActiveProposal:
            let decision = delegate.acceptActiveProposalFromControl()
            switch decision {
            case .accepted:
                return .applied
            case .expired:
                return .blocked(reason: "proposal expired")
            case .rejected:
                return .blocked(reason: "proposal rejected")
            case .blocked:
                return .blocked(reason: "no active proposal")
            }

        case .startEngine:
            delegate.startEngineFromControl()
            return .applied

        case .stopEngine:
            delegate.stopEngineFromControl()
            return .applied

        case .patchVector(let patch):
            delegate.patchVector(patch)
            return .applied

        case .armOutputMode(let mode):
            delegate.armOutputMode(Self.flightMode(for: mode))
            return .applied

        case .armTransportLane(let laneId):
            delegate.armTransportLane(laneId)
            return .applied

        case .queueTimelineStep(let laneId):
            delegate.queueTimelineStepFromControl(laneId)
            return .applied

        case .setDynamicBinSelection(let value):
            delegate.setDynamicBinSelectionFromControl(value)
            return .applied

        case .setCutCadence(let value):
            delegate.setCutCadenceFromControl(value)
            return .applied

        case .setCompositorBlend(let value):
            delegate.setCompositorBlendFromControl(value)
            return .applied

        case .setStaticVisualOverrideHold(let isHeld):
            delegate.setStaticVisualOverrideHoldFromControl(isHeld)
            return .applied

        case .setStaticSampleMorph(let value):
            delegate.setStaticSampleMorphFromControl(value)
            return .applied

        case .setStaticArticulation(let value):
            delegate.setStaticArticulationFromControl(value)
            return .applied

        case .setStaticTimbre(let value):
            delegate.setStaticTimbreFromControl(value)
            return .applied

        case .setStaticTextureSend(let value):
            delegate.setStaticTextureSendFromControl(value)
            return .applied

        case .setChoirFieldSpread(let value):
            delegate.setChoirFieldSpreadFromControl(value)
            return .applied

        case .setChoirFieldDepth(let value):
            delegate.setChoirFieldDepthFromControl(value)
            return .applied

        case .setChoirFieldDetune(let value):
            delegate.setChoirFieldDetuneFromControl(value)
            return .applied

        case .setTextProbability(let value):
            delegate.setTextProbabilityFromControl(value)
            return .applied

        case .setStrictLooseBlend(let value):
            delegate.setStrictLooseBlendFromControl(value)
            return .applied

        case .setVisualVariance(let value):
            delegate.setVisualVarianceFromControl(value)
            return .applied

        case .toggleUltrachunkOverlay:
            delegate.toggleUltrachunkOverlayFromControl()
            return .applied

        case .contextualTake:
            guard passesCommitCooldown(for: "contextual_take") else {
                return .blocked(reason: "contextual TAKE cooldown")
            }
            if delegate.canTakeArmedTimelineStep() {
                delegate.takeArmedTimelineStep()
                return .applied
            }
            if delegate.isLatchArmed {
                delegate.fireOutputGO()
                return .applied
            }
            if delegate.phoneAudioGateArmed, delegate.hotasPhoneChoirContextActive {
                delegate.goPhoneAudioGate()
                return .applied
            }
            return .blocked(reason: "contextual TAKE has no armed target")

        case .setMasterArm(let isArmed):
            delegate.setMasterArmFromControl(isArmed)
            return .applied

        case .phoneGateTake:
            delegate.takePhoneAudioGate()
            return .applied

        case .phoneGateGo:
            guard passesCommitCooldown(for: "phone_gate_go") else {
                return .blocked(reason: "phone GO cooldown")
            }
            delegate.goPhoneAudioGate()
            return .applied

        case .phoneGateSafe:
            delegate.safePhoneAudioGate()
            return .applied

        case .togglePreviewPlayback:
            delegate.togglePreviewPlayback()
            return .applied

        case .setSampleBank(let bank, let domain):
            delegate.setActiveSampleBankFromControl(bank, domain: domain)
            return .applied

        case .setEffectsChain(let chain, let active, let intensity):
            delegate.setEffectsChainFromControl(chain: chain, active: active, intensity: intensity)
            return .applied

        case .triggerPhoneChoirNoteOn:
            delegate.triggerPhoneChoirNoteOn()
            return .applied

        case .triggerPhoneChoirNoteOff:
            delegate.triggerPhoneChoirNoteOff()
            return .applied

        case .stopAllPhoneAudio:
            delegate.stopAllPhoneAudio()
            return .applied

        case .setPhoneChoirContextActive(let active):
            delegate.setPhoneChoirContextActiveFromControl(active)
            return .applied
        }
    }

    private func passesCommitCooldown(for key: String) -> Bool {
        let now = Date().timeIntervalSince1970
        if let previous = lastCommitAtByKey[key], now - previous < commitCooldownSeconds {
            return false
        }
        lastCommitAtByKey[key] = now
        return true
    }

    private static func flightMode(for id: FlightOutputModeID) -> FlightOutputMode {
        switch id {
        case .off:
            return .off
        case .dynamic:
            return .dynamic
        case .static:
            return .static
        }
    }
}
