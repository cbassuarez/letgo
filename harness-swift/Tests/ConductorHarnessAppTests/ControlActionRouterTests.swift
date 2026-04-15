@testable import ConductorHarnessApp
import ConductorCore
import XCTest

@MainActor
final class ControlActionRouterTests: XCTestCase {
    func testContextualTakePrioritizesTimelineThenLatchThenPhoneGate() {
        let delegate = RouterDelegateMock()
        let router = ControlActionRouter(delegate: delegate, commitCooldownSeconds: 0)

        delegate.canTakeArmedTimeline = true
        router.route(.contextualTake)
        XCTAssertEqual(delegate.timelineTakeCount, 1)
        XCTAssertEqual(delegate.outputGoCount, 0)
        XCTAssertEqual(delegate.phoneGateGoCount, 0)

        delegate.canTakeArmedTimeline = false
        delegate.isLatchArmedStorage = true
        router.route(.contextualTake)
        XCTAssertEqual(delegate.outputGoCount, 1)

        delegate.isLatchArmedStorage = false
        delegate.phoneAudioGateArmedStorage = true
        delegate.hotasPhoneChoirContextActiveStorage = true
        router.route(.contextualTake)
        XCTAssertEqual(delegate.phoneGateGoCount, 1)
    }

    func testCommitCooldownDebouncesRepeatedGO() {
        let delegate = RouterDelegateMock()
        let router = ControlActionRouter(delegate: delegate, commitCooldownSeconds: 0.12)

        let first = router.route(.phoneGateGo)
        let second = router.route(.phoneGateGo)
        XCTAssertEqual(delegate.phoneGateGoCount, 1)
        XCTAssertEqual(first, .applied)
        XCTAssertEqual(second, .blocked(reason: "phone GO cooldown"))
    }

    func testMasterArmAndEffectsRouting() {
        let delegate = RouterDelegateMock()
        let router = ControlActionRouter(delegate: delegate, commitCooldownSeconds: 0)

        router.route(.setMasterArm(isArmed: true))
        router.route(.setEffectsChain(chain: .a, active: true, intensity: 0.8))
        router.route(.setSampleBank(3, domain: .main))

        XCTAssertEqual(delegate.masterArmState, true)
        XCTAssertEqual(delegate.effectsUpdates.count, 1)
        XCTAssertEqual(delegate.effectsUpdates.first?.chain, .a)
        XCTAssertEqual(delegate.effectsUpdates.first?.active, true)
        XCTAssertEqual(delegate.sampleBank, 3)
        XCTAssertEqual(delegate.sampleBankDomain, .main)
    }

    func testChoirSampleBankRoutingPreservesDomain() {
        let delegate = RouterDelegateMock()
        let router = ControlActionRouter(delegate: delegate, commitCooldownSeconds: 0)
        router.route(.setSampleBank(2, domain: .choir))
        XCTAssertEqual(delegate.sampleBank, 2)
        XCTAssertEqual(delegate.sampleBankDomain, .choir)
    }

    func testProceduralScalarControlsRouteToDelegate() {
        let delegate = RouterDelegateMock()
        let router = ControlActionRouter(delegate: delegate, commitCooldownSeconds: 0)

        router.route(.setDynamicBinSelection(0.77))
        router.route(.setCutCadence(0.63))
        router.route(.setCompositorBlend(0.28))
        router.route(.setStaticVisualOverrideHold(true))
        router.route(.setStaticSampleMorph(0.31))
        router.route(.setStaticArticulation(0.52))
        router.route(.setStaticTimbre(0.64))
        router.route(.setStaticTextureSend(0.73))
        router.route(.setChoirFieldSpread(0.27))
        router.route(.setChoirFieldDepth(0.44))
        router.route(.setChoirFieldDetune(0.58))
        router.route(.setTextProbability(0.49))
        router.route(.setStrictLooseBlend(0.91))
        router.route(.setVisualVariance(0.22))

        XCTAssertEqual(delegate.dynamicBinSelection, 0.77)
        XCTAssertEqual(delegate.cutCadence, 0.63)
        XCTAssertEqual(delegate.compositorBlend, 0.28)
        XCTAssertEqual(delegate.staticVisualOverrideHeld, true)
        XCTAssertEqual(delegate.staticSampleMorph, 0.31)
        XCTAssertEqual(delegate.staticArticulation, 0.52)
        XCTAssertEqual(delegate.staticTimbre, 0.64)
        XCTAssertEqual(delegate.staticTextureSend, 0.73)
        XCTAssertEqual(delegate.choirSpread, 0.27)
        XCTAssertEqual(delegate.choirDepth, 0.44)
        XCTAssertEqual(delegate.choirDetune, 0.58)
        XCTAssertEqual(delegate.textProbability, 0.49)
        XCTAssertEqual(delegate.strictLooseBlend, 0.91)
        XCTAssertEqual(delegate.visualVariance, 0.22)
    }

    func testProposalAcceptRoutingUsesDelegateDecision() {
        let delegate = RouterDelegateMock()
        let router = ControlActionRouter(delegate: delegate, commitCooldownSeconds: 0)

        delegate.proposalDecision = .accepted
        let accepted = router.route(.acceptActiveProposal)
        XCTAssertEqual(accepted, .applied)

        delegate.proposalDecision = .blocked
        let blocked = router.route(.acceptActiveProposal)
        XCTAssertEqual(blocked, .blocked(reason: "no active proposal"))
    }
}

@MainActor
private final class RouterDelegateMock: ControlActionRouting {
    struct EffectsUpdate {
        let chain: EffectsChainID
        let active: Bool
        let intensity: Double
    }

    var isLatchArmedStorage = false
    var phoneAudioGateArmedStorage = false
    var hotasPhoneChoirContextActiveStorage = false
    var canTakeArmedTimeline = false
    var timelineTakeCount = 0
    var outputGoCount = 0
    var phoneGateGoCount = 0
    var startEngineCount = 0
    var stopEngineCount = 0
    var masterArmState = false
    var sampleBank = 1
    var sampleBankDomain: SampleBankDomain = .main
    var effectsUpdates: [EffectsUpdate] = []
    var dynamicBinSelection: Double = 0
    var cutCadence: Double = 0
    var compositorBlend: Double = 0
    var staticVisualOverrideHeld = false
    var staticSampleMorph: Double = 0
    var staticArticulation: Double = 0
    var staticTimbre: Double = 0
    var staticTextureSend: Double = 0
    var choirSpread: Double = 0
    var choirDepth: Double = 0
    var choirDetune: Double = 0
    var textProbability: Double = 0
    var strictLooseBlend: Double = 0
    var visualVariance: Double = 0
    var proposalDecision: MLProposalDecision = .blocked

    var isLatchArmed: Bool { isLatchArmedStorage }
    var phoneAudioGateArmed: Bool { phoneAudioGateArmedStorage }
    var hotasPhoneChoirContextActive: Bool { hotasPhoneChoirContextActiveStorage }

    @discardableResult
    func acceptActiveProposalFromControl() -> MLProposalDecision { proposalDecision }
    func startEngineFromControl() { startEngineCount += 1 }
    func stopEngineFromControl() { stopEngineCount += 1 }
    func canTakeArmedTimelineStep() -> Bool { canTakeArmedTimeline }
    func takeArmedTimelineStep() { timelineTakeCount += 1 }
    func fireOutputGO() { outputGoCount += 1 }
    func goPhoneAudioGate() { phoneGateGoCount += 1 }
    func patchVector(_ patch: ParamVectorPatch) { _ = patch }
    func armOutputMode(_ mode: FlightOutputMode) { _ = mode }
    func armTransportLane(_ laneId: String) { _ = laneId }
    func queueTimelineStepFromControl(_ laneId: String) { _ = laneId }
    func setDynamicBinSelectionFromControl(_ value: Double) { dynamicBinSelection = value }
    func setCutCadenceFromControl(_ value: Double) { cutCadence = value }
    func setCompositorBlendFromControl(_ value: Double) { compositorBlend = value }
    func setStaticVisualOverrideHoldFromControl(_ isHeld: Bool) { staticVisualOverrideHeld = isHeld }
    func setStaticSampleMorphFromControl(_ value: Double) { staticSampleMorph = value }
    func setStaticArticulationFromControl(_ value: Double) { staticArticulation = value }
    func setStaticTimbreFromControl(_ value: Double) { staticTimbre = value }
    func setStaticTextureSendFromControl(_ value: Double) { staticTextureSend = value }
    func setChoirFieldSpreadFromControl(_ value: Double) { choirSpread = value }
    func setChoirFieldDepthFromControl(_ value: Double) { choirDepth = value }
    func setChoirFieldDetuneFromControl(_ value: Double) { choirDetune = value }
    func setTextProbabilityFromControl(_ value: Double) { textProbability = value }
    func setStrictLooseBlendFromControl(_ value: Double) { strictLooseBlend = value }
    func setVisualVarianceFromControl(_ value: Double) { visualVariance = value }
    func setMasterArmFromControl(_ isArmed: Bool) { masterArmState = isArmed }
    func takePhoneAudioGate() {}
    func safePhoneAudioGate() {}
    func togglePreviewPlayback() {}
    func setActiveSampleBankFromControl(_ bank: Int, domain: SampleBankDomain) {
        sampleBank = bank
        sampleBankDomain = domain
    }
    func triggerPhoneChoirNoteOn() {}
    func triggerPhoneChoirNoteOff() {}
    func stopAllPhoneAudio() {}
    func setPhoneChoirContextActiveFromControl(_ active: Bool) { hotasPhoneChoirContextActiveStorage = active }
    func setEffectsChainFromControl(chain: EffectsChainID, active: Bool, intensity: Double) {
        effectsUpdates.append(EffectsUpdate(chain: chain, active: active, intensity: intensity))
    }
}
