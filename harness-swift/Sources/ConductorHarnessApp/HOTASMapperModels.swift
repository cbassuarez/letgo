import ConductorCore
import Foundation

struct HOTASFunctionDescriptor: Identifiable, Equatable {
    let role: ControlRole
    let priority: Int

    var id: String { role.rawValue }
    var title: String { role.title }
    var shortLabel: String { role.shortLabel }
    var group: ControlRoleGroup { role.group }
    var hint: String { role.hint }
    var required: Bool { role.isRequiredByDefault }

    static var ordered: [HOTASFunctionDescriptor] {
        let priorityByRole: [ControlRole: Int] = {
            var map: [ControlRole: Int] = [:]
            for (index, role) in ControlRole.mapperRoles.enumerated() {
                map[role] = index
            }
            return map
        }()

        return ControlRole.mapperRoles
            .map { role in
                HOTASFunctionDescriptor(role: role, priority: priorityByRole[role] ?? 10_000)
            }
            .sorted { lhs, rhs in
                if lhs.group != rhs.group {
                    return lhs.group.rawValue < rhs.group.rawValue
                }
                if lhs.priority != rhs.priority {
                    return lhs.priority < rhs.priority
                }
                return lhs.role.rawValue < rhs.role.rawValue
            }
    }
}

struct HOTASHotspotDescriptor: Identifiable, Equatable {
    let role: ControlRole
    let title: String
    let logicalDevice: HOTASLogicalDevice
    let preferredKind: ControlSignalKind
    let supportedKinds: Set<ControlSignalKind>
    let x: Double
    let y: Double

    var id: ControlRole { role }

    static let all: [HOTASHotspotDescriptor] = {
        let layout = layoutByRole
        let missing = ControlRole.mapperRoles.filter { layout[$0] == nil }
        assert(missing.isEmpty, "HOTAS hotspot layout missing roles: \(missing.map(\.rawValue).joined(separator: ", "))")

        return ControlRole.mapperRoles.map { role in
            let item = layout[role] ?? fallbackLayout(for: role)
            return HOTASHotspotDescriptor(
                role: role,
                title: item.title,
                logicalDevice: item.logicalDevice,
                preferredKind: item.preferredKind,
                supportedKinds: role.captureKinds,
                x: item.x,
                y: item.y
            )
        }
    }()

    static let byRole: [ControlRole: HOTASHotspotDescriptor] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.role, $0) })
    }()

    private static let layoutByRole: [ControlRole: (
        title: String,
        logicalDevice: HOTASLogicalDevice,
        preferredKind: ControlSignalKind,
        x: Double,
        y: Double
    )] = [
        .rightAcceptButton: ("Accept", .x56Stick, .button, 0.74, 0.22),
        .rightTakeButton: ("Take", .x56Stick, .button, 0.84, 0.30),
        .engineStartHold: ("Engine Start", .x56Stick, .button, 0.70, 0.14),
        .engineStopHold: ("Engine Stop", .x56Stick, .button, 0.78, 0.14),
        .rightTrigger1: ("Trigger A", .x56Stick, .button, 0.14, 0.09),
        .rightTrigger2: ("Trigger B", .x56Stick, .button, 0.28, 0.09),
        .ultrachunkOverlayToggle: ("Ultrachunk FX", .x56Stick, .button, 0.62, 0.14),
        .rightStickX: ("Stick X", .x56Stick, .axis, 0.39, 0.60),
        .rightStickY: ("Stick Y", .x56Stick, .axis, 0.49, 0.60),
        .rightStickTwist: ("Twist", .x56Stick, .axis, 0.44, 0.70),
        .rightThumbX: ("Thumb X", .x56Stick, .axis, 0.67, 0.65),
        .rightThumbY: ("Thumb Y", .x56Stick, .axis, 0.76, 0.65),
        .rightTopSlider: ("Top Slider", .x56Stick, .axis, 0.87, 0.08),

        .leftMainThrottle: ("Main Throttle", .x56Throttle, .axis, 0.23, 0.56),
        .leftAuxThrottle: ("Aux Throttle", .x56Throttle, .axis, 0.51, 0.48),
        .leftSecondThrottle: ("2nd Throttle", .x56Throttle, .axis, 0.79, 0.41),
        .leftHatUp: ("Hat Up", .x56Throttle, .hat, 0.54, 0.19),
        .leftHatRight: ("Hat Right", .x56Throttle, .hat, 0.60, 0.25),
        .leftHatDown: ("Hat Down", .x56Throttle, .hat, 0.54, 0.31),
        .leftPlaybackButton: ("Playback", .x56Throttle, .button, 0.38, 0.22),
        .leftModeRotary: ("Mode Rotary", .x56Throttle, .button, 0.72, 0.16),
        .leftRotary1Decrease: ("Rotary 1", .x56Throttle, .axis, 0.68, 0.25),
        .leftRotary2Axis: ("Rotary 2", .x56Throttle, .axis, 0.76, 0.26),

        .leftBottomToggle1: ("Toggle 1", .x56Throttle, .button, 0.16, 0.80),
        .leftBottomToggle2: ("Toggle 2", .x56Throttle, .button, 0.27, 0.80),
        .leftBottomToggle3: ("Toggle 3", .x56Throttle, .button, 0.38, 0.80),
        .leftBottomToggle4: ("Toggle 4", .x56Throttle, .button, 0.49, 0.80),
        .leftBottomToggle5: ("Toggle 5", .x56Throttle, .button, 0.60, 0.80),
        .leftBottomToggle6: ("Toggle 6", .x56Throttle, .button, 0.71, 0.80),

        .leftArmToggleUp: ("Arm Up", .x56Throttle, .button, 0.13, 0.16),
        .leftArmToggleDown: ("Arm Down", .x56Throttle, .button, 0.20, 0.16),
        .leftCueToggleUp: ("Cue Up", .x56Throttle, .button, 0.27, 0.16),
        .leftCueToggleDown: ("Cue Down", .x56Throttle, .button, 0.34, 0.16),
        .leftCueToggleCenter: ("Cue Center", .x56Throttle, .button, 0.41, 0.16),

        .leftToggle1Up: ("Toggle1 Up", .x56Throttle, .button, 0.82, 0.65),
        .leftToggle1Down: ("Toggle1 Down", .x56Throttle, .button, 0.87, 0.73),
        .leftStaticVisualClutch: ("Clutch", .x56Throttle, .button, 0.83, 0.20)
    ]

    private static func fallbackLayout(for role: ControlRole) -> (
        title: String,
        logicalDevice: HOTASLogicalDevice,
        preferredKind: ControlSignalKind,
        x: Double,
        y: Double
    ) {
        (
            role.title,
            role.preferredHOTASLogicalDevice ?? .unspecified,
            role.captureKinds.contains(.axis) ? .axis : (role.captureKinds.contains(.hat) ? .hat : .button),
            0.5,
            0.5
        )
    }
}

@MainActor
final class HOTASMapperWindowState: ObservableObject {
    enum BindingMode: String, CaseIterable {
        case functionFirst
        case controlFirst
    }

    struct CalibrationSweep: Equatable {
        var role: ControlRole
        var min: Double
        var max: Double
        var current: Double
    }

    @Published var bindingMode: BindingMode = .functionFirst
    @Published var selectedRole: ControlRole?
    @Published var selectedHotspotID: ControlRole?
    @Published var controlFirstRole: ControlRole = .rightStickX
    @Published var calibrationSweep: CalibrationSweep?

    func beginSweep(for role: ControlRole, current: Double) {
        calibrationSweep = CalibrationSweep(role: role, min: current, max: current, current: current)
    }

    func updateSweep(current: Double) {
        guard var sweep = calibrationSweep else { return }
        sweep.current = current
        sweep.min = min(sweep.min, current)
        sweep.max = max(sweep.max, current)
        calibrationSweep = sweep
    }

    func cancelSweep() {
        calibrationSweep = nil
    }
}
