import Foundation

public struct ControlRuntimeContext: Equatable, Sendable {
    public var activeOutputMode: FlightOutputModeID
    public var phoneChoirModeActive: Bool
    public var allowStaticVideoOverride: Bool
    public var staticVisualClutchActive: Bool

    public static let neutral = ControlRuntimeContext(
        activeOutputMode: .off,
        phoneChoirModeActive: false,
        allowStaticVideoOverride: true,
        staticVisualClutchActive: false
    )

    public init(
        activeOutputMode: FlightOutputModeID,
        phoneChoirModeActive: Bool,
        allowStaticVideoOverride: Bool,
        staticVisualClutchActive: Bool
    ) {
        self.activeOutputMode = activeOutputMode
        self.phoneChoirModeActive = phoneChoirModeActive
        self.allowStaticVideoOverride = allowStaticVideoOverride
        self.staticVisualClutchActive = staticVisualClutchActive
    }
}

public final class ControlProfileMapper {
    public var profile: ControlProfile {
        didSet {
            resetState()
        }
    }

    private var effectsActive: [ControlRole: Bool] = [:]
    private var effectsIntensity: [ControlRole: Double] = [:]
    private var latchedOutputMode: FlightOutputModeID?
    private var latchedMainSampleBank: Int = 1
    private var latchedChoirSampleBank: Int = 1
    private var toggle1Direction: Int = 0
    private var strictLooseBlendSetting: Double = 0.5

    public init(profile: ControlProfile) {
        self.profile = profile
    }

    public func resetState() {
        effectsActive.removeAll()
        effectsIntensity.removeAll()
        latchedOutputMode = nil
        latchedMainSampleBank = 1
        latchedChoirSampleBank = 1
        toggle1Direction = 0
        strictLooseBlendSetting = 0.5
    }

    public func map(
        signal: ControlSignal,
        laneIDs: [String],
        context: ControlRuntimeContext = .neutral
    ) -> [ControlAction] {
        let bindings = profile.bindings(for: signal)
        guard !bindings.isEmpty else { return [] }

        var actions: [ControlAction] = []
        for binding in bindings {
            actions.append(contentsOf: map(binding: binding, signal: signal, laneIDs: laneIDs, context: context))
        }
        return actions
    }

    private func map(
        binding: ControlBinding,
        signal: ControlSignal,
        laneIDs: [String],
        context: ControlRuntimeContext
    ) -> [ControlAction] {
        _ = laneIDs
        let normalized = binding.calibration.applyNormalized(signal.normalizedValue)
        let centered = binding.calibration.applyCentered(signal.normalizedValue)

        switch binding.role {
        case .rightAcceptButton:
            return signal.phase == .began ? [.acceptActiveProposal] : []

        case .rightStickX:
            if context.phoneChoirModeActive {
                return scalarAction(signal: signal, action: .setChoirFieldSpread(normalized))
            }
            if context.activeOutputMode == .dynamic {
                return scalarAction(signal: signal, action: .setDynamicBinSelection(normalized))
            }
            if context.activeOutputMode == .static {
                if shouldRouteStaticVisualOverride(in: context) {
                    return vectorPatch(signal: signal, patch: ParamVectorPatch(spatialX: normalized))
                }
                return scalarAction(signal: signal, action: .setStaticSampleMorph(normalized))
            }
            guard shouldEmitVectorPatch(in: context) else { return [] }
            return vectorPatch(signal: signal, patch: ParamVectorPatch(spatialX: normalized))
        case .rightStickY:
            if context.phoneChoirModeActive {
                return scalarAction(signal: signal, action: .setChoirFieldDepth(normalized))
            }
            if context.activeOutputMode == .dynamic {
                return scalarAction(signal: signal, action: .setCutCadence(normalized))
            }
            if context.activeOutputMode == .static {
                if shouldRouteStaticVisualOverride(in: context) {
                    return vectorPatch(signal: signal, patch: ParamVectorPatch(audioGain: normalized))
                }
                return scalarAction(signal: signal, action: .setStaticArticulation(normalized))
            }
            guard shouldEmitVectorPatch(in: context) else { return [] }
            return vectorPatch(signal: signal, patch: ParamVectorPatch(audioGain: normalized))
        case .rightStickTwist:
            if context.phoneChoirModeActive {
                return scalarAction(signal: signal, action: .setChoirFieldDetune(normalized))
            }
            if context.activeOutputMode == .dynamic {
                return scalarAction(signal: signal, action: .setCompositorBlend(normalized))
            }
            if context.activeOutputMode == .static {
                if shouldRouteStaticVisualOverride(in: context) {
                    return vectorPatch(signal: signal, patch: ParamVectorPatch(compositeBias: normalized))
                }
                return scalarAction(signal: signal, action: .setStaticTimbre(normalized))
            }
            guard shouldEmitVectorPatch(in: context) else { return [] }
            return vectorPatch(signal: signal, patch: ParamVectorPatch(compositeBias: normalized))
        case .rightThumbX:
            guard shouldEmitVectorPatch(in: context) else { return [] }
            return vectorPatch(signal: signal, patch: ParamVectorPatch(spatialY: normalized))
        case .rightThumbY:
            guard shouldEmitVectorPatch(in: context) else { return [] }
            return vectorPatch(signal: signal, patch: ParamVectorPatch(spatialZ: normalized))
        case .rightTopSlider:
            if context.activeOutputMode == .static, !context.phoneChoirModeActive {
                return scalarAction(signal: signal, action: .setStaticTextureSend(normalized))
            }
            guard shouldEmitVectorPatch(in: context) else { return [] }
            return vectorPatch(signal: signal, patch: ParamVectorPatch(textAmount: normalized))

        case .rightTakeButton:
            return signal.phase == .began ? [.contextualTake] : []

        case .rightTrigger1:
            return effectsActions(
                role: binding.role,
                chain: .a,
                signal: signal,
                intensity: normalized
            )

        case .rightTrigger2:
            return effectsActions(
                role: binding.role,
                chain: .b,
                signal: signal,
                intensity: normalized
            )

        case .leftMainThrottle:
            guard signal.kind == .axis else { return [] }
            let mode = resolveOutputMode(for: normalized, thresholds: profile.outputModeThresholds)
            guard mode != latchedOutputMode else { return [] }
            latchedOutputMode = mode
            return [.armOutputMode(mode)]

        case .leftAuxThrottle:
            return scalarAction(signal: signal, action: .setTextProbability(normalized))

        case .leftSecondThrottle:
            return scalarAction(signal: signal, action: .setTextProbability(normalized))

        case .leftHatUp:
            return signal.phase == .began ? [.queueTimelineStep("preshow")] : []
        case .leftHatRight:
            return signal.phase == .began ? [.queueTimelineStep("introduction")] : []
        case .leftHatDown:
            return signal.phase == .began ? [.queueTimelineStep("ending")] : []

        case .leftPlaybackButton:
            return signal.phase == .began ? [.togglePreviewPlayback] : []

        case .leftModeRotary:
            let bank = resolvedBank(from: normalized)
            let domain: SampleBankDomain = context.phoneChoirModeActive ? .choir : .main
            switch domain {
            case .main:
                guard bank != latchedMainSampleBank else { return [] }
                latchedMainSampleBank = bank
            case .choir:
                guard bank != latchedChoirSampleBank else { return [] }
                latchedChoirSampleBank = bank
            }
            return [.setSampleBank(bank, domain: domain)]

        case .leftRotary1Decrease:
            return blendStepActions(signal: signal, delta: -0.08)

        case .leftRotary1Increase:
            return blendStepActions(signal: signal, delta: 0.08)

        case .leftRotary2Axis:
            return scalarAction(signal: signal, action: .setVisualVariance(normalized))

        case .leftBottomToggle1, .leftBottomToggle2:
            return signal.phase == .began ? [.queueTimelineStep("preshow")] : []
        case .leftBottomToggle3, .leftBottomToggle4:
            return signal.phase == .began ? [.queueTimelineStep("introduction")] : []
        case .leftBottomToggle5, .leftBottomToggle6:
            return signal.phase == .began ? [.queueTimelineStep("ending")] : []

        case .leftArmToggleUp:
            return signal.phase == .began ? [.setMasterArm(isArmed: true)] : []

        case .leftArmToggleDown:
            return signal.phase == .began ? [.setMasterArm(isArmed: false)] : []

        case .leftCueToggleUp:
            return signal.phase == .began ? [.phoneGateTake] : []

        case .leftCueToggleDown:
            return signal.phase == .began ? [.phoneGateGo] : []

        case .leftCueToggleCenter:
            return signal.phase == .began ? [.phoneGateSafe] : []

        case .leftToggle1Directional:
            return toggleDirectionalActions(centered: centered)

        case .leftStaticVisualClutch:
            return clutchActions(signal: signal)
        }
    }

    private func vectorPatch(signal: ControlSignal, patch: ParamVectorPatch) -> [ControlAction] {
        switch signal.phase {
        case .began, .changed:
            return [.patchVector(patch)]
        case .ended:
            return []
        }
    }

    private func effectsActions(
        role: ControlRole,
        chain: EffectsChainID,
        signal: ControlSignal,
        intensity: Double
    ) -> [ControlAction] {
        let activeNow: Bool
        switch signal.phase {
        case .ended:
            activeNow = false
        case .began, .changed:
            activeNow = intensity > 0.05
        }

        let clamped = min(1.0, max(0.0, intensity))
        let previousActive = effectsActive[role] ?? false
        let previousIntensity = effectsIntensity[role] ?? 0

        effectsActive[role] = activeNow
        effectsIntensity[role] = clamped

        if activeNow != previousActive {
            return [.setEffectsChain(chain: chain, active: activeNow, intensity: clamped)]
        }

        if activeNow, abs(previousIntensity - clamped) > 0.05 {
            return [.setEffectsChain(chain: chain, active: true, intensity: clamped)]
        }

        return []
    }

    private func scalarAction(signal: ControlSignal, action: ControlAction) -> [ControlAction] {
        switch signal.phase {
        case .began, .changed:
            return [action]
        case .ended:
            return []
        }
    }

    private func resolveOutputMode(for value: Double, thresholds: OutputModeThresholds) -> FlightOutputModeID {
        let h = thresholds.hysteresis

        func directMode(_ sample: Double) -> FlightOutputModeID {
            if sample <= thresholds.offMaximum { return .off }
            if sample >= thresholds.staticMinimum { return .static }
            if sample >= thresholds.dynamicMinimum, sample <= thresholds.dynamicMaximum { return .dynamic }
            if sample > thresholds.dynamicMaximum, sample < thresholds.staticMinimum { return .dynamic }
            return .off
        }

        guard let current = latchedOutputMode else {
            return directMode(value)
        }

        switch current {
        case .off:
            if value > thresholds.offMaximum + h {
                return directMode(value)
            }
            return .off
        case .dynamic:
            if value < thresholds.dynamicMinimum - h || value > thresholds.dynamicMaximum + h {
                return directMode(value)
            }
            return .dynamic
        case .static:
            if value < thresholds.staticMinimum - h {
                return directMode(value)
            }
            return .static
        }
    }

    private func resolvedBank(from value: Double) -> Int {
        if value < 0.34 { return 1 }
        if value < 0.67 { return 2 }
        return 3
    }

    private func blendStepActions(signal: ControlSignal, delta: Double) -> [ControlAction] {
        guard signal.phase == .began else { return [] }
        strictLooseBlendSetting = min(1, max(0, strictLooseBlendSetting + delta))
        return [.setStrictLooseBlend(strictLooseBlendSetting)]
    }

    private func toggleDirectionalActions(centered: Double) -> [ControlAction] {
        let upThreshold = 0.45
        let downThreshold = -0.45
        let neutralBand = 0.2

        if centered >= upThreshold {
            if toggle1Direction != 1 {
                toggle1Direction = 1
                return [
                    .setPhoneChoirContextActive(true),
                    .triggerPhoneChoirNoteOn
                ]
            }
            return []
        }

        if centered <= downThreshold {
            if toggle1Direction != -1 {
                toggle1Direction = -1
                return [
                    .setPhoneChoirContextActive(false),
                    .triggerPhoneChoirNoteOff,
                    .stopAllPhoneAudio
                ]
            }
            return []
        }

        if abs(centered) <= neutralBand {
            if toggle1Direction == 1 {
                toggle1Direction = 0
                return [
                    .triggerPhoneChoirNoteOff,
                    .setPhoneChoirContextActive(false)
                ]
            }
            toggle1Direction = 0
        }

        return []
    }

    private func shouldEmitVectorPatch(in context: ControlRuntimeContext) -> Bool {
        !(context.activeOutputMode == .static && !context.allowStaticVideoOverride)
    }

    private func shouldRouteStaticVisualOverride(in context: ControlRuntimeContext) -> Bool {
        context.activeOutputMode == .static
            && context.allowStaticVideoOverride
            && context.staticVisualClutchActive
    }

    private func clutchActions(signal: ControlSignal) -> [ControlAction] {
        switch signal.phase {
        case .began:
            return [.setStaticVisualOverrideHold(true)]
        case .ended:
            return [.setStaticVisualOverrideHold(false)]
        case .changed:
            if signal.kind == .axis || signal.kind == .hat {
                return [.setStaticVisualOverrideHold(signal.normalizedValue > 0.5)]
            }
            return []
        }
    }
}
