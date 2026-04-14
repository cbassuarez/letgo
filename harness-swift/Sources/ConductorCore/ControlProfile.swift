import Foundation

public enum ControlRole: String, Codable, CaseIterable, Sendable {
    case rightAcceptButton
    case rightStickX
    case rightStickY
    case rightStickTwist
    case rightThumbX
    case rightThumbY
    case rightTopSlider

    case rightTakeButton
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
        .leftToggle1Directional,
        .leftStaticVisualClutch
    ]

    public static let optionalWizardRoles: [ControlRole] = [
        .rightThumbX,
        .rightThumbY,
        .rightTopSlider,
        .rightTrigger1,
        .rightTrigger2,
        .leftPlaybackButton,
        .leftHatUp,
        .leftHatRight,
        .leftHatDown,
        .leftAuxThrottle
    ]

    public var isRequiredByDefault: Bool {
        Self.requiredWizardRoles.contains(self)
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
        "\(role.rawValue)-\(sourceKind?.rawValue ?? "any")-\(sourceDeviceID ?? "any-device")"
    }

    public var role: ControlRole
    public var controlID: String
    public var sourceKind: ControlSourceKind?
    public var sourceDeviceID: String?
    public var kind: ControlSignalKind
    public var calibration: CalibrationSpec
    public var required: Bool

    public init(
        role: ControlRole,
        controlID: String,
        sourceKind: ControlSourceKind?,
        sourceDeviceID: String? = nil,
        kind: ControlSignalKind,
        calibration: CalibrationSpec = .default,
        required: Bool? = nil
    ) {
        self.role = role
        self.controlID = controlID
        self.sourceKind = sourceKind
        self.sourceDeviceID = sourceDeviceID
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
        bindings
            .filter { binding in
                binding.controlID == signal.controlID
                    && (binding.sourceKind == nil || binding.sourceKind == signal.sourceKind)
                    && (binding.sourceDeviceID == nil || binding.sourceDeviceID == signal.sourceDeviceID)
            }
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
                    return lhs.sourceKind != nil
                }

                return lhs.sourceKind == nil && lhs.sourceDeviceID == nil
            }
    }

    public func firstBinding(for role: ControlRole) -> ControlBinding? {
        bindings.first(where: { $0.role == role })
    }

    public mutating func setBinding(_ binding: ControlBinding) {
        if let index = bindings.firstIndex(where: {
            $0.role == binding.role && $0.sourceKind == binding.sourceKind
        }) {
            bindings[index] = binding
        } else {
            bindings.append(binding)
        }
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
            ControlBinding(role: .leftModeRotary, controlID: "gd:dial", sourceKind: .hotas, kind: .axis),
            ControlBinding(role: .leftRotary1Decrease, controlID: "btn:14", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftRotary1Increase, controlID: "btn:15", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftRotary2Axis, controlID: "gd:43", sourceKind: .hotas, kind: .axis),
            ControlBinding(role: .leftBottomToggle1, controlID: "btn:20", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle2, controlID: "btn:21", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle3, controlID: "btn:22", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle4, controlID: "btn:23", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle5, controlID: "btn:24", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle6, controlID: "btn:25", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftArmToggleUp, controlID: "btn:5", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftArmToggleDown, controlID: "btn:6", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftCueToggleUp, controlID: "btn:7", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftCueToggleDown, controlID: "btn:8", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftCueToggleCenter, controlID: "btn:9", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftToggle1Directional, controlID: "gd:slider2", sourceKind: .hotas, kind: .axis),
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
