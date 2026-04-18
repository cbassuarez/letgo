import Foundation

public struct ControlRuntimeContext: Equatable, Sendable {
    public var activeOutputMode: FlightOutputModeID
    public var phoneChoirModeActive: Bool
    public var allowStaticVideoOverride: Bool
    public var rightStickRouteMode: RightStickRouteModeID

    public static let neutral = ControlRuntimeContext(
        activeOutputMode: .off,
        phoneChoirModeActive: false,
        allowStaticVideoOverride: true,
        rightStickRouteMode: .base
    )

    public init(
        activeOutputMode: FlightOutputModeID,
        phoneChoirModeActive: Bool,
        allowStaticVideoOverride: Bool,
        rightStickRouteMode: RightStickRouteModeID
    ) {
        self.activeOutputMode = activeOutputMode
        self.phoneChoirModeActive = phoneChoirModeActive
        self.allowStaticVideoOverride = allowStaticVideoOverride
        self.rightStickRouteMode = rightStickRouteMode
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
    private var ultrachunkOverlayEnabled = false
    private var roleAxisThresholdLatched: [String: Bool] = [:]
    private var holdCaptureStartedAt: [ControlRole: TimeInterval] = [:]
    private var clutchLastTapAt: TimeInterval?
    private var clutchLastEmitAt: TimeInterval?

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
        ultrachunkOverlayEnabled = false
        roleAxisThresholdLatched.removeAll()
        holdCaptureStartedAt.removeAll()
        clutchLastTapAt = nil
        clutchLastEmitAt = nil
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
                return rightStickRouteActions(
                    signal: signal,
                    context: context,
                    baseAction: .setDynamicBinSelection(normalized),
                    audioAction: .setDynamicAudioSurfX(normalized)
                )
            }
            return rightStickRouteActions(
                signal: signal,
                context: context,
                baseAction: .setStaticSampleMorph(normalized),
                audioAction: .setDynamicAudioSurfX(normalized)
            )
        case .rightStickY:
            if context.phoneChoirModeActive {
                return scalarAction(signal: signal, action: .setChoirFieldDepth(normalized))
            }
            if context.activeOutputMode == .dynamic {
                return rightStickRouteActions(
                    signal: signal,
                    context: context,
                    baseAction: .setCutCadence(normalized),
                    audioAction: .setDynamicAudioSurfY(normalized)
                )
            }
            return rightStickRouteActions(
                signal: signal,
                context: context,
                baseAction: .setStaticArticulation(normalized),
                audioAction: .setDynamicAudioSurfY(normalized)
            )
        case .rightStickTwist:
            if context.phoneChoirModeActive {
                return scalarAction(signal: signal, action: .setChoirFieldDetune(normalized))
            }
            if context.activeOutputMode == .dynamic {
                return rightStickRouteActions(
                    signal: signal,
                    context: context,
                    baseAction: .setCompositorBlend(normalized),
                    audioAction: .setDynamicAudioSurfZ(normalized)
                )
            }
            return rightStickRouteActions(
                signal: signal,
                context: context,
                baseAction: .setStaticTimbre(normalized),
                audioAction: .setDynamicAudioSurfZ(normalized)
            )
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

        case .engineStartHold:
            return holdAction(
                signal: signal,
                role: .engineStartHold,
                minimumDurationSeconds: 5.0,
                action: .startEngine
            )

        case .engineStopHold:
            return holdAction(
                signal: signal,
                role: .engineStopHold,
                minimumDurationSeconds: 5.0,
                action: .stopEngine
            )

        case .rightTrigger1:
            if context.activeOutputMode == .dynamic {
                if signal.kind == .button {
                    switch signal.phase {
                    case .began:
                        return [.setDynamicTextSurf(1)]
                    case .ended:
                        return [.setDynamicTextSurf(0)]
                    case .changed:
                        return []
                    }
                }
                return scalarAction(signal: signal, action: .setDynamicTextSurf(normalized))
            }
            return effectsActions(
                role: binding.role,
                chain: .a,
                signal: signal,
                intensity: normalized
            )

        case .rightTrigger2:
            if context.activeOutputMode == .dynamic {
                return signal.phase == .began ? [.triggerDynamicTextBurst] : []
            }
            return effectsActions(
                role: binding.role,
                chain: .b,
                signal: signal,
                intensity: normalized
            )

        case .ultrachunkOverlayToggle:
            guard signal.phase == .began else { return [] }
            ultrachunkOverlayEnabled.toggle()
            return [.toggleUltrachunkOverlay]

        case .leftMainThrottle:
            guard signal.kind == .axis else { return [] }
            let mode = resolveOutputMode(for: normalized, thresholds: profile.outputModeThresholds)
            guard mode != latchedOutputMode else { return [] }
            latchedOutputMode = mode
            return [.armOutputMode(mode)]

        case .leftAuxThrottle:
            if context.activeOutputMode == .dynamic {
                return scalarAction(signal: signal, action: .setDynamicAudioDensity(normalized))
            }
            return scalarAction(signal: signal, action: .setTextProbability(normalized))

        case .leftSecondThrottle:
            if context.activeOutputMode == .dynamic {
                return scalarAction(signal: signal, action: .setDynamicEchoMacro(normalized))
            }
            return scalarAction(signal: signal, action: .setTextProbability(normalized))

        case .leftHatUp:
            return signal.phase == .began ? [.queueTimelineStep("preshow")] : []
        case .leftHatRight:
            return signal.phase == .began ? [.queueTimelineStep("introduction")] : []
        case .leftHatDown:
            return signal.phase == .began ? [.queueTimelineStep("ending")] : []

        case .leftPlaybackButton:
            if context.activeOutputMode == .dynamic {
                return signal.phase == .began ? [.toggleDynamicTextMute] : []
            }
            return signal.phase == .began ? [.togglePreviewPlayback] : []

        case .leftModeRotary:
            let bank: Int
            if signal.kind == .button || binding.kind == .button {
                guard signal.phase == .began,
                      let resolved = resolvedDiscreteModeRotaryBank(signal: signal) else {
                    return []
                }
                bank = resolved
            } else {
                bank = resolvedBank(from: normalized)
            }
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
            if context.activeOutputMode == .dynamic {
                return effectsActions(
                    role: binding.role,
                    chain: .a,
                    signal: signal,
                    intensity: normalized
                )
            }
            if signal.kind == .axis || binding.kind == .axis {
                return scalarAction(signal: signal, action: .setStrictLooseBlend(normalized))
            }
            // Legacy button-step fallback for older profiles.
            return blendStepActions(signal: signal, delta: -0.08)

        case .leftRotary1Increase:
            // Legacy fallback role for older button-based profiles.
            if signal.kind == .axis || binding.kind == .axis {
                return scalarAction(signal: signal, action: .setStrictLooseBlend(normalized))
            }
            return blendStepActions(signal: signal, delta: 0.08)

        case .leftRotary2Axis:
            if context.activeOutputMode == .dynamic {
                return effectsActions(
                    role: binding.role,
                    chain: .b,
                    signal: signal,
                    intensity: normalized
                )
            }
            return scalarAction(signal: signal, action: .setVisualVariance(normalized))

        case .leftBottomToggle1:
            return signal.phase == .began ? [.armMainStaticScene(1)] : []
        case .leftBottomToggle2:
            return signal.phase == .began ? [.armMainStaticScene(2)] : []
        case .leftBottomToggle3:
            return signal.phase == .began ? [.armMainStaticScene(3)] : []
        case .leftBottomToggle4:
            return signal.phase == .began ? [.armMainStaticScene(4)] : []
        case .leftBottomToggle5, .leftBottomToggle6:
            return signal.phase == .began ? [.armMainDynamicMode] : []

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

        case .leftToggle1Up:
            return toggleDirectionalDiscreteUpActions(signal: signal, normalized: normalized)

        case .leftToggle1Down:
            return toggleDirectionalDiscreteDownActions(signal: signal, normalized: normalized)

        case .leftToggle1Directional:
            return toggleDirectionalActions(centered: centered)

        case .leftStaticVisualClutch:
            return clutchTapActions(signal: signal)
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

    private func holdAction(
        signal: ControlSignal,
        role: ControlRole,
        minimumDurationSeconds: TimeInterval,
        action: ControlAction
    ) -> [ControlAction] {
        switch signal.phase {
        case .began:
            holdCaptureStartedAt[role] = signal.timestamp
            return []
        case .changed:
            return []
        case .ended:
            guard let startedAt = holdCaptureStartedAt.removeValue(forKey: role) else {
                return []
            }
            let rawDelta = max(0, signal.timestamp - startedAt)
            let durationSeconds = rawDelta > 120 ? (rawDelta / 1_000.0) : rawDelta
            guard durationSeconds >= minimumDurationSeconds else {
                return []
            }
            return [action]
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

    private func blendStepAxisActions(
        signal: ControlSignal,
        role: ControlRole,
        normalized: Double,
        engageThreshold: Double,
        delta: Double
    ) -> [ControlAction] {
        let key = "\(role.rawValue):\(signal.sourceDeviceID):\(HOTASLogicalDeviceMatcher.normalizedControlID(signal.controlID))"
        let shouldEngage = delta < 0 ? normalized <= engageThreshold : normalized >= engageThreshold
        let wasEngaged = roleAxisThresholdLatched[key] ?? false
        roleAxisThresholdLatched[key] = shouldEngage
        guard shouldEngage, !wasEngaged else { return [] }
        strictLooseBlendSetting = min(1, max(0, strictLooseBlendSetting + delta))
        return [.setStrictLooseBlend(strictLooseBlendSetting)]
    }

    private func toggleDirectionalDiscreteUpActions(signal: ControlSignal, normalized: Double) -> [ControlAction] {
        let isAxisActive = signal.kind == .axis && (normalized >= 0.8 || normalized <= 0.2)
        let isActuated = signal.phase == .began
            || (signal.phase == .changed && (signal.rawValue > 0 || isAxisActive))
            || isAxisActive
        guard isActuated else { return [] }
        guard toggle1Direction != 1 else { return [] }
        toggle1Direction = 1
        return [
            .setPhoneChoirContextActive(true),
            .triggerPhoneChoirNoteOn
        ]
    }

    private func toggleDirectionalDiscreteDownActions(signal: ControlSignal, normalized: Double) -> [ControlAction] {
        let isAxisActive = signal.kind == .axis && (normalized >= 0.8 || normalized <= 0.2)
        let isActuated = signal.phase == .began
            || (signal.phase == .changed && (signal.rawValue > 0 || isAxisActive))
            || isAxisActive
        guard isActuated else { return [] }
        guard toggle1Direction != -1 else { return [] }
        toggle1Direction = -1
        return [
            .setPhoneChoirContextActive(false),
            .triggerPhoneChoirNoteOff,
            .stopAllPhoneAudio
        ]
    }

    private func resolvedDiscreteModeRotaryBank(signal: ControlSignal) -> Int? {
        let normalizedControlID = HOTASLogicalDeviceMatcher.normalizedControlID(signal.controlID)
        if let direct = explicitModeRotaryBank(for: normalizedControlID) {
            return direct
        }

        let orderedButtons = Set(profile.bindings
            .filter { $0.role == .leftModeRotary && $0.sourceKind == signal.sourceKind }
            .compactMap { modeRotaryButtonNumber(from: HOTASLogicalDeviceMatcher.normalizedControlID($0.controlID)) }
        )
            .sorted()

        guard let signalButton = modeRotaryButtonNumber(from: normalizedControlID),
              let index = orderedButtons.firstIndex(of: signalButton) else {
            return nil
        }
        return min(3, max(1, index + 1))
    }

    private func explicitModeRotaryBank(for normalizedControlID: String) -> Int? {
        guard let button = modeRotaryButtonNumber(from: normalizedControlID) else {
            return nil
        }
        switch button {
        case 34:
            return 1
        case 35:
            return 2
        case 36:
            return 3
        default:
            return nil
        }
    }

    private func modeRotaryButtonNumber(from normalizedControlID: String) -> Int? {
        guard normalizedControlID.hasPrefix("btn:") else { return nil }
        return Int(normalizedControlID.dropFirst(4))
    }

    private func toggleDirectionalActions(centered: Double) -> [ControlAction] {
        let upThreshold = 0.45
        let downThreshold = -0.45

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

        return []
    }

    private func shouldEmitVectorPatch(in context: ControlRuntimeContext) -> Bool {
        !(context.activeOutputMode == .static && !context.allowStaticVideoOverride)
    }

    private func rightStickRouteActions(
        signal: ControlSignal,
        context: ControlRuntimeContext,
        baseAction: ControlAction,
        audioAction: ControlAction
    ) -> [ControlAction] {
        guard signal.phase == .began || signal.phase == .changed else { return [] }
        switch context.rightStickRouteMode {
        case .base:
            return [baseAction]
        case .audioOnly:
            return [audioAction]
        case .dualWrite:
            return [baseAction, audioAction]
        }
    }

    private func clutchTapActions(signal: ControlSignal) -> [ControlAction] {
        guard signal.phase == .began else { return [] }
        let now = signal.timestamp
        let debounceWindow: TimeInterval = 0.05
        let doubleClickWindow: TimeInterval = 0.28

        if let lastEmitAt = clutchLastEmitAt, now - lastEmitAt < debounceWindow {
            return []
        }
        clutchLastEmitAt = now

        if let lastTapAt = clutchLastTapAt, now - lastTapAt <= doubleClickWindow {
            clutchLastTapAt = nil
            return [.setRightStickRouteMode(.dualWrite)]
        }
        clutchLastTapAt = now
        return [.cycleRightStickRouteMode]
    }
}
