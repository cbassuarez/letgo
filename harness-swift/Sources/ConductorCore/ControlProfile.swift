import Foundation

public enum HOTASLogicalDevice: String, Codable, CaseIterable, Sendable {
    case x56Stick
    case x56Throttle
    case unspecified
}

public enum ControlRoleGroup: String, Codable, CaseIterable, Sendable {
    case criticalSafety
    case transport
    case videoAudioMacro
    case effects
    case choir
}

public enum ControlRole: String, Codable, CaseIterable, Sendable {
    case rightAcceptButton
    case rightStickX
    case rightStickY
    case rightStickTwist
    case rightThumbX
    case rightThumbY
    case rightTopSlider

    case rightTakeButton
    case engineStartHold
    case engineStopHold
    case rightTrigger1
    case rightTrigger2

    case leftMainThrottle
    case leftAuxThrottle
    case leftSecondThrottle
    case leftHatUp
    case leftHatRight
    case leftHatDown
    case leftPlaybackButton
    case leftModeRotary
    case leftRotary1Decrease
    case leftRotary1Increase
    case leftRotary2Axis
    case leftBottomToggle1
    case leftBottomToggle2
    case leftBottomToggle3
    case leftBottomToggle4
    case leftBottomToggle5
    case leftBottomToggle6

    case leftArmToggleUp
    case leftArmToggleDown

    case leftCueToggleUp
    case leftCueToggleDown
    case leftCueToggleCenter

    case leftToggle1Up
    case leftToggle1Down
    case leftToggle1Directional
    case leftStaticVisualClutch

    public static let requiredWizardRoles: [ControlRole] = [
        .rightAcceptButton,
        .rightStickX,
        .rightStickY,
        .rightStickTwist,
        .rightTakeButton,
        .leftMainThrottle,
        .leftSecondThrottle,
        .leftModeRotary,
        .leftRotary1Decrease,
        .leftRotary2Axis,
        .leftBottomToggle1,
        .leftBottomToggle2,
        .leftBottomToggle3,
        .leftBottomToggle4,
        .leftBottomToggle5,
        .leftBottomToggle6,
        .leftArmToggleUp,
        .leftArmToggleDown,
        .leftStaticVisualClutch
    ]

    public static let optionalWizardRoles: [ControlRole] = [
        .rightThumbX,
        .rightThumbY,
        .rightTopSlider,
        .rightTrigger1,
        .rightTrigger2,
        .engineStartHold,
        .engineStopHold,
        .leftPlaybackButton,
        .leftHatUp,
        .leftHatRight,
        .leftHatDown,
        .leftAuxThrottle,
        .leftToggle1Up,
        .leftToggle1Down
    ]

    public static let mapperRoles: [ControlRole] = {
        var ordered: [ControlRole] = []
        for role in requiredWizardRoles + optionalWizardRoles {
            if !ordered.contains(role) {
                ordered.append(role)
            }
        }
        return ordered
    }()

    public var isRequiredByDefault: Bool {
        Self.requiredWizardRoles.contains(self)
    }

    public var group: ControlRoleGroup {
        switch self {
        case .rightTakeButton,
             .engineStartHold,
             .engineStopHold,
             .rightAcceptButton,
             .leftArmToggleUp,
             .leftArmToggleDown,
             .leftCueToggleUp,
             .leftCueToggleDown,
             .leftCueToggleCenter,
             .leftStaticVisualClutch:
            return .criticalSafety
        case .leftHatUp,
             .leftHatRight,
             .leftHatDown,
             .leftPlaybackButton,
             .leftModeRotary,
             .leftBottomToggle1,
             .leftBottomToggle2,
             .leftBottomToggle3,
             .leftBottomToggle4,
             .leftBottomToggle5,
             .leftBottomToggle6:
            return .transport
        case .rightTrigger1, .rightTrigger2:
            return .effects
        case .leftToggle1Up,
             .leftToggle1Down,
             .leftToggle1Directional:
            return .choir
        default:
            return .videoAudioMacro
        }
    }

    public var title: String {
        switch self {
        case .rightAcceptButton: return "Proposal Accept"
        case .rightStickX: return "Right Stick X"
        case .rightStickY: return "Right Stick Y"
        case .rightStickTwist: return "Right Stick Twist"
        case .rightThumbX: return "Right Thumb X"
        case .rightThumbY: return "Right Thumb Y"
        case .rightTopSlider: return "Right Top Slider"
        case .rightTakeButton: return "Take Button"
        case .engineStartHold: return "Engine Start (Hold 5s)"
        case .engineStopHold: return "Engine Stop (Hold 5s)"
        case .rightTrigger1: return "Trigger A (Rhythm)"
        case .rightTrigger2: return "Trigger B (Space)"
        case .leftMainThrottle: return "Left Main Throttle"
        case .leftAuxThrottle: return "Left Aux Throttle"
        case .leftSecondThrottle: return "Left Second Throttle"
        case .leftHatUp: return "Throttle Hat Up"
        case .leftHatRight: return "Throttle Hat Right"
        case .leftHatDown: return "Throttle Hat Down"
        case .leftPlaybackButton: return "Playback Button"
        case .leftModeRotary: return "Mode Rotary"
        case .leftRotary1Decrease: return "Rotary 1 Axis"
        case .leftRotary1Increase: return "Rotary 1 Increase"
        case .leftRotary2Axis: return "Rotary 2 Axis"
        case .leftBottomToggle1: return "Bottom Toggle 1"
        case .leftBottomToggle2: return "Bottom Toggle 2"
        case .leftBottomToggle3: return "Bottom Toggle 3"
        case .leftBottomToggle4: return "Bottom Toggle 4"
        case .leftBottomToggle5: return "Bottom Toggle 5"
        case .leftBottomToggle6: return "Bottom Toggle 6"
        case .leftArmToggleUp: return "Arm Toggle Up"
        case .leftArmToggleDown: return "Arm Toggle Down"
        case .leftCueToggleUp: return "Cue Toggle Up"
        case .leftCueToggleDown: return "Cue Toggle Down"
        case .leftCueToggleCenter: return "Cue Toggle Center"
        case .leftToggle1Up: return "Toggle 1 Up (Choir On)"
        case .leftToggle1Down: return "Toggle 1 Down (Choir Off)"
        case .leftToggle1Directional: return "Toggle 1 Directional"
        case .leftStaticVisualClutch: return "Static Visual Clutch"
        }
    }

    public var shortLabel: String {
        switch self {
        case .rightStickX: return "R STK X"
        case .rightStickY: return "R STK Y"
        case .rightStickTwist: return "R TWIST"
        case .rightThumbX: return "R THUMB X"
        case .rightThumbY: return "R THUMB Y"
        case .rightTakeButton: return "TAKE"
        case .engineStartHold: return "ENG START"
        case .engineStopHold: return "ENG STOP"
        case .rightAcceptButton: return "ACCEPT"
        case .rightTrigger1: return "TRIG A"
        case .rightTrigger2: return "TRIG B"
        case .leftMainThrottle: return "MAIN THR"
        case .leftAuxThrottle: return "AUX THR"
        case .leftSecondThrottle: return "2ND THR"
        case .leftModeRotary: return "MODE ROT"
        case .leftRotary1Decrease: return "ROTARY 1"
        case .leftToggle1Up: return "CHOIR ON"
        case .leftToggle1Down: return "CHOIR OFF"
        case .leftStaticVisualClutch: return "CLUTCH"
        default: return title.uppercased()
        }
    }

    public var hint: String {
        switch group {
        case .criticalSafety:
            return "Critical safety/commit control. Keep unambiguous and easy to reach."
        case .transport:
            return "Timeline, transport, and sample bank navigation."
        case .videoAudioMacro:
            return "Continuous macro/vector shaping control."
        case .effects:
            return "Hold or pressure-driven effects chain trigger."
        case .choir:
            return "Phone choir directional or contextual control."
        }
    }

    public var operationalDescription: String {
        switch self {
        case .rightThumbX:
            return "Secondary lateral macro lane. Default: vector spatial Y."
        case .rightThumbY:
            return "Secondary depth macro lane. Default: vector spatial Z."
        case .rightTopSlider:
            return "Continuous top slider macro. Default: text/texture amount."
        case .leftAuxThrottle:
            return "Aux continuous throttle lane. Default: text appearance probability."
        case .leftArmToggleUp:
            return "Master arm ON. Enables commit path when all other guards are valid."
        case .leftArmToggleDown:
            return "Master arm SAFE. Immediately disarms commit path."
        case .leftCueToggleUp:
            return "Phone gate TAKE (arm/prep)."
        case .leftCueToggleDown:
            return "Phone gate GO (commit) subject to safety guards."
        case .leftCueToggleCenter:
            return "Phone gate SAFE (clear/hold safe)."
        case .leftToggle1Up:
            return "Choir latched ON trigger (up position)."
        case .leftToggle1Down:
            return "Choir latched OFF trigger (down position)."
        case .leftToggle1Directional:
            return "Legacy choir directional axis. Prefer explicit Up/Down binds."
        case .leftRotary1Decrease:
            return "Continuous strict/loose blend axis (Rotary 1)."
        case .leftStaticVisualClutch:
            return "Hold to temporarily repurpose right stick for static visual override."
        case .engineStartHold:
            return "Hold for 5 seconds to start engine."
        case .engineStopHold:
            return "Hold for 5 seconds to stop engine."
        default:
            return hint
        }
    }

    public var preferredHOTASLogicalDevice: HOTASLogicalDevice? {
        switch self {
        case .rightAcceptButton,
             .rightStickX,
             .rightStickY,
             .rightStickTwist,
             .rightThumbX,
             .rightThumbY,
             .rightTopSlider,
             .rightTakeButton,
             .engineStartHold,
             .engineStopHold,
             .rightTrigger1,
             .rightTrigger2:
            return .x56Stick
        case .leftMainThrottle,
             .leftAuxThrottle,
             .leftSecondThrottle,
             .leftHatUp,
             .leftHatRight,
             .leftHatDown,
             .leftPlaybackButton,
             .leftModeRotary,
             .leftRotary1Decrease,
             .leftRotary1Increase,
             .leftRotary2Axis,
             .leftBottomToggle1,
             .leftBottomToggle2,
             .leftBottomToggle3,
             .leftBottomToggle4,
             .leftBottomToggle5,
             .leftBottomToggle6,
             .leftArmToggleUp,
             .leftArmToggleDown,
             .leftCueToggleUp,
             .leftCueToggleDown,
             .leftCueToggleCenter,
             .leftToggle1Up,
             .leftToggle1Down,
             .leftToggle1Directional,
             .leftStaticVisualClutch:
            return .x56Throttle
        }
    }

    public var captureKinds: Set<ControlSignalKind> {
        switch self {
        case .rightStickX,
             .rightStickY,
             .rightStickTwist,
             .rightThumbX,
             .rightThumbY,
             .rightTopSlider,
             .leftMainThrottle,
             .leftAuxThrottle,
             .leftSecondThrottle,
             .leftRotary1Decrease,
             .leftRotary2Axis,
             .leftToggle1Directional:
            return [.axis]
        case .leftModeRotary:
            // Some X56 profiles expose this as analog dial, others as 3 discrete buttons.
            return [.axis, .button]
        case .leftToggle1Up,
             .leftToggle1Down:
            return [.button, .hat, .axis]
        case .leftHatUp,
             .leftHatRight,
             .leftHatDown:
            return [.hat]
        default:
            return [.button]
        }
    }

    public var allowsMultipleBindings: Bool {
        switch self {
        case .leftModeRotary:
            return true
        default:
            return false
        }
    }
}

public struct CalibrationSpec: Codable, Equatable, Sendable {
    public var minimum: Double
    public var maximum: Double
    public var center: Double
    public var deadzone: Double
    public var hysteresis: Double
    public var inverted: Bool

    public static let `default` = CalibrationSpec(
        minimum: 0,
        maximum: 1,
        center: 0.5,
        deadzone: 0.03,
        hysteresis: 0.05,
        inverted: false
    )

    public init(
        minimum: Double,
        maximum: Double,
        center: Double,
        deadzone: Double,
        hysteresis: Double,
        inverted: Bool
    ) {
        self.minimum = minimum
        self.maximum = maximum
        self.center = center
        self.deadzone = max(0, deadzone)
        self.hysteresis = max(0, hysteresis)
        self.inverted = inverted
    }

    public func applyNormalized(_ rawNormalized: Double) -> Double {
        let range = max(0.0001, maximum - minimum)
        var normalized = (rawNormalized - minimum) / range
        normalized = min(1.0, max(0.0, normalized))
        if inverted {
            normalized = 1.0 - normalized
        }
        if abs(normalized - center) <= deadzone {
            return center
        }
        return normalized
    }

    public func applyCentered(_ rawNormalized: Double) -> Double {
        let normalized = applyNormalized(rawNormalized)
        let centered = (normalized - center) / max(0.0001, 1.0 - abs(center - 0.5) * 2.0)
        if abs(centered) <= deadzone {
            return 0
        }
        return min(1.0, max(-1.0, centered))
    }
}

public struct ControlBinding: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        "\(role.rawValue)-\(sourceKind?.rawValue ?? "any")-\(sourceDeviceID ?? "any-device")-\(logicalDevice?.rawValue ?? "any-logical")-\(controlID)-\(kind.rawValue)"
    }

    public var role: ControlRole
    public var controlID: String
    public var sourceKind: ControlSourceKind?
    public var sourceDeviceID: String?
    public var logicalDevice: HOTASLogicalDevice?
    public var kind: ControlSignalKind
    public var calibration: CalibrationSpec
    public var required: Bool

    public init(
        role: ControlRole,
        controlID: String,
        sourceKind: ControlSourceKind?,
        sourceDeviceID: String? = nil,
        logicalDevice: HOTASLogicalDevice? = nil,
        kind: ControlSignalKind,
        calibration: CalibrationSpec = .default,
        required: Bool? = nil
    ) {
        self.role = role
        self.controlID = controlID
        self.sourceKind = sourceKind
        self.sourceDeviceID = sourceDeviceID
        if sourceKind == .hotas {
            if let logicalDevice {
                self.logicalDevice = logicalDevice
            } else if sourceDeviceID == nil {
                self.logicalDevice = role.preferredHOTASLogicalDevice
            } else {
                self.logicalDevice = nil
            }
        } else {
            self.logicalDevice = logicalDevice
        }
        self.kind = kind
        self.calibration = calibration
        self.required = required ?? role.isRequiredByDefault
    }
}

public struct OutputModeThresholds: Codable, Equatable, Sendable {
    public var offMaximum: Double
    public var dynamicMinimum: Double
    public var dynamicMaximum: Double
    public var staticMinimum: Double
    public var hysteresis: Double

    public static let strictDefault = OutputModeThresholds(
        offMaximum: 0.25,
        dynamicMinimum: 0.35,
        dynamicMaximum: 0.65,
        staticMinimum: 0.75,
        hysteresis: 0.05
    )

    public init(
        offMaximum: Double,
        dynamicMinimum: Double,
        dynamicMaximum: Double,
        staticMinimum: Double,
        hysteresis: Double
    ) {
        self.offMaximum = offMaximum
        self.dynamicMinimum = dynamicMinimum
        self.dynamicMaximum = dynamicMaximum
        self.staticMinimum = staticMinimum
        self.hysteresis = max(0, hysteresis)
    }
}

public struct SampleBankProfile: Codable, Equatable, Sendable {
    public var bank1: [String]
    public var bank2: [String]
    public var bank3: [String]
    public var choirBank1: [String]?
    public var choirBank2: [String]?
    public var choirBank3: [String]?

    public static let empty = SampleBankProfile(bank1: [], bank2: [], bank3: [])

    public init(
        bank1: [String],
        bank2: [String],
        bank3: [String],
        choirBank1: [String]? = nil,
        choirBank2: [String]? = nil,
        choirBank3: [String]? = nil
    ) {
        self.bank1 = bank1
        self.bank2 = bank2
        self.bank3 = bank3
        self.choirBank1 = choirBank1
        self.choirBank2 = choirBank2
        self.choirBank3 = choirBank3
    }

    public func sampleIDs(for bank: Int, domain: SampleBankDomain = .main) -> [String] {
        switch domain {
        case .main:
            return mainSampleIDs(for: bank)
        case .choir:
            let choirSamples: [String]
            switch bank {
            case 1:
                choirSamples = choirBank1 ?? []
            case 2:
                choirSamples = choirBank2 ?? []
            case 3:
                choirSamples = choirBank3 ?? []
            default:
                choirSamples = []
            }
            return choirSamples.isEmpty ? mainSampleIDs(for: bank) : choirSamples
        }
    }

    private func mainSampleIDs(for bank: Int) -> [String] {
        switch bank {
        case 1:
            return bank1
        case 2:
            return bank2
        case 3:
            return bank3
        default:
            return []
        }
    }
}

public struct ControlProfile: Codable, Equatable, Sendable {
    public var version: Int
    public var name: String
    public var inputMode: ControlInputMode
    public var enabled: Bool
    public var outputModeThresholds: OutputModeThresholds
    public var staticLaneOrder: [String]
    public var sampleBanks: SampleBankProfile
    public var bindings: [ControlBinding]

    public init(
        version: Int,
        name: String,
        inputMode: ControlInputMode,
        enabled: Bool,
        outputModeThresholds: OutputModeThresholds,
        staticLaneOrder: [String],
        sampleBanks: SampleBankProfile,
        bindings: [ControlBinding]
    ) {
        self.version = version
        self.name = name
        self.inputMode = inputMode
        self.enabled = enabled
        self.outputModeThresholds = outputModeThresholds
        self.staticLaneOrder = staticLaneOrder
        self.sampleBanks = sampleBanks
        self.bindings = bindings
    }

    public func missingRequiredRoles() -> [ControlRole] {
        let present = Set(bindings.filter(\.required).map(\.role))
        return ControlRole.requiredWizardRoles.filter { !present.contains($0) }
    }

    public var isValid: Bool {
        missingRequiredRoles().isEmpty
    }

    public func bindings(for signal: ControlSignal) -> [ControlBinding] {
        let signalLogicalDevice = HOTASLogicalDeviceMatcher.classify(
            sourceDeviceID: signal.sourceDeviceID,
            controlID: signal.controlID
        )
        let signalControlIDs = HOTASLogicalDeviceMatcher.canonicalControlIDVariants(signal.controlID)
        func controlIDMatches(_ bindingControlID: String) -> Bool {
            let bindingVariants = HOTASLogicalDeviceMatcher.canonicalControlIDVariants(bindingControlID)
            return !signalControlIDs.isDisjoint(with: bindingVariants)
        }
        let baseMatches = bindings.filter { binding in
            controlIDMatches(binding.controlID)
                && (binding.sourceKind == nil || binding.sourceKind == signal.sourceKind)
                && (binding.sourceDeviceID == nil || binding.sourceDeviceID == signal.sourceDeviceID)
        }

        // Replug-safe fallback for HOTAS:
        // if no exact sourceDevice match was found, allow bindings pinned to old
        // source IDs to match by logical device affinity (stick/throttle).
        let replugMatches: [ControlBinding] = {
            guard baseMatches.isEmpty, signal.sourceKind == .hotas else { return [] }
            return bindings.filter { binding in
                guard controlIDMatches(binding.controlID) else { return false }
                guard binding.sourceKind == nil || binding.sourceKind == signal.sourceKind else { return false }
                guard binding.sourceDeviceID != nil else { return false }

                let bindingLogical = binding.logicalDevice
                    ?? HOTASLogicalDeviceMatcher.classify(
                        sourceDeviceID: binding.sourceDeviceID ?? "",
                        controlID: binding.controlID
                    )
                guard bindingLogical != .unspecified else { return false }
                guard signalLogicalDevice != .unspecified else { return false }
                return bindingLogical == signalLogicalDevice
            }
        }()

        let candidateMatches = baseMatches.isEmpty ? replugMatches : baseMatches
        let strictMatches = candidateMatches.filter { binding in
            binding.logicalDevice == nil
                || binding.logicalDevice == .unspecified
                || binding.logicalDevice == signalLogicalDevice
        }

        let matches = strictMatches.isEmpty ? candidateMatches : strictMatches

        return matches
            .sorted { lhs, rhs in
                let lhsMatchesSourceKind = lhs.sourceKind == signal.sourceKind
                let rhsMatchesSourceKind = rhs.sourceKind == signal.sourceKind
                if lhsMatchesSourceKind != rhsMatchesSourceKind {
                    return lhsMatchesSourceKind
                }

                let lhsMatchesDevice = lhs.sourceDeviceID == signal.sourceDeviceID
                let rhsMatchesDevice = rhs.sourceDeviceID == signal.sourceDeviceID
                if lhsMatchesDevice != rhsMatchesDevice {
                    return lhsMatchesDevice
                }

                if lhs.sourceKind == rhs.sourceKind,
                   lhs.sourceDeviceID == rhs.sourceDeviceID {
                    return lhs.role.rawValue < rhs.role.rawValue
                }

                if lhs.sourceKind == rhs.sourceKind {
                    return lhs.sourceDeviceID != nil
                }

                if lhs.sourceDeviceID == rhs.sourceDeviceID {
                    let lhsMatchesLogical = lhs.logicalDevice == signalLogicalDevice
                    let rhsMatchesLogical = rhs.logicalDevice == signalLogicalDevice
                    if lhsMatchesLogical != rhsMatchesLogical {
                        return lhsMatchesLogical
                    }
                    return lhs.sourceKind != nil
                }

                return lhs.sourceKind == nil && lhs.sourceDeviceID == nil
            }
    }

    public func firstBinding(for role: ControlRole) -> ControlBinding? {
        bindings.first(where: { $0.role == role })
    }

    public mutating func setBinding(_ binding: ControlBinding) {
        if binding.role.allowsMultipleBindings {
            if let exactIndex = bindings.firstIndex(where: {
                $0.role == binding.role
                    && $0.sourceKind == binding.sourceKind
                    && $0.controlID == binding.controlID
                    && $0.logicalDevice == binding.logicalDevice
                    && $0.sourceDeviceID == binding.sourceDeviceID
            }) {
                bindings[exactIndex] = binding
                return
            }
            bindings.append(binding)
            return
        }

        if let index = bindings.firstIndex(where: {
            $0.role == binding.role && $0.sourceKind == binding.sourceKind
        }) {
            bindings[index] = binding
            return
        }
        bindings.append(binding)
    }

    public static let defaultX56StrictLive = ControlProfile(
        version: 1,
        name: "X56 Strict Live",
        inputMode: .hybrid,
        enabled: false,
        outputModeThresholds: .strictDefault,
        staticLaneOrder: ["preshow", "introduction", "ending"],
        sampleBanks: .empty,
        bindings: [
            ControlBinding(role: .rightStickX, controlID: "gd:x", sourceKind: .hotas, kind: .axis),
            ControlBinding(role: .rightStickY, controlID: "gd:y", sourceKind: .hotas, kind: .axis, calibration: CalibrationSpec(minimum: 0, maximum: 1, center: 0.5, deadzone: 0.03, hysteresis: 0.05, inverted: true)),
            ControlBinding(role: .rightStickTwist, controlID: "gd:rz", sourceKind: .hotas, kind: .axis),
            ControlBinding(role: .rightAcceptButton, controlID: "btn:1", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .rightThumbX, controlID: "gd:rx", sourceKind: .hotas, kind: .axis, required: false),
            ControlBinding(role: .rightThumbY, controlID: "gd:ry", sourceKind: .hotas, kind: .axis, required: false),
            ControlBinding(role: .rightTopSlider, controlID: "gd:slider", sourceKind: .hotas, kind: .axis, required: false),
            ControlBinding(role: .rightTakeButton, controlID: "btn:2", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .rightTrigger1, controlID: "btn:10", sourceKind: .hotas, kind: .button, required: false),
            ControlBinding(role: .rightTrigger2, controlID: "btn:11", sourceKind: .hotas, kind: .button, required: false),

            ControlBinding(role: .leftMainThrottle, controlID: "gd:z", sourceKind: .hotas, kind: .axis),
            ControlBinding(role: .leftSecondThrottle, controlID: "gd:wheel", sourceKind: .hotas, kind: .axis),
            ControlBinding(role: .leftAuxThrottle, controlID: "gd:42", sourceKind: .hotas, kind: .axis, required: false),
            ControlBinding(role: .leftHatUp, controlID: "gd:hat:up", sourceKind: .hotas, kind: .hat),
            ControlBinding(role: .leftHatRight, controlID: "gd:hat:right", sourceKind: .hotas, kind: .hat),
            ControlBinding(role: .leftHatDown, controlID: "gd:hat:down", sourceKind: .hotas, kind: .hat),
            ControlBinding(role: .leftPlaybackButton, controlID: "btn:4", sourceKind: .hotas, kind: .button, required: false),
            ControlBinding(role: .leftModeRotary, controlID: "btn:34", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftModeRotary, controlID: "btn:35", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftModeRotary, controlID: "btn:36", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftRotary1Decrease, controlID: "gd:dial", sourceKind: .hotas, kind: .axis),
            ControlBinding(role: .leftRotary2Axis, controlID: "gd:43", sourceKind: .hotas, kind: .axis),
            ControlBinding(role: .leftBottomToggle1, controlID: "btn:20", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle2, controlID: "btn:21", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle3, controlID: "btn:22", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle4, controlID: "btn:23", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle5, controlID: "btn:24", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle6, controlID: "btn:25", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftArmToggleUp, controlID: "btn:5", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftArmToggleDown, controlID: "btn:6", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftStaticVisualClutch, controlID: "btn:12", sourceKind: .hotas, kind: .button),

            // MIDI fallback mappings for dynamic vectors.
            ControlBinding(role: .rightTopSlider, controlID: "midi:cc:20", sourceKind: .midi, kind: .axis, required: false),
            ControlBinding(role: .rightStickTwist, controlID: "midi:cc:21", sourceKind: .midi, kind: .axis),
            ControlBinding(role: .rightStickY, controlID: "midi:cc:22", sourceKind: .midi, kind: .axis, calibration: CalibrationSpec(minimum: 0, maximum: 1, center: 0.5, deadzone: 0.02, hysteresis: 0.03, inverted: true)),
            ControlBinding(role: .rightStickX, controlID: "midi:cc:23", sourceKind: .midi, kind: .axis),
            ControlBinding(role: .rightThumbX, controlID: "midi:cc:24", sourceKind: .midi, kind: .axis, required: false),
            ControlBinding(role: .rightThumbY, controlID: "midi:cc:25", sourceKind: .midi, kind: .axis, required: false)
        ]
    )
}
