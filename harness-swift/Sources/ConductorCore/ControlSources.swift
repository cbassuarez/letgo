import Foundation

#if canImport(CoreMIDI)
import CoreMIDI
#endif

#if canImport(IOKit.hid)
import IOKit.hid
#endif

public struct HOTASDeviceDescriptor: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class CoreMIDIControlSignalSource: ControlSignalSource {
    public let sourceKind: ControlSourceKind = .midi
    public let sourceName: String = "CoreMIDI"

    private let preferredSourceID: String?
    private var source: CoreMIDIEventSource?

    public init(sourceID: String?) {
        preferredSourceID = sourceID
    }

    public func start(onEvent: @escaping (ControlSignal) -> Void) {
        stop()
        let resolvedSourceID = preferredSourceID ?? CoreMIDIEventSource.availableInputs().first?.id
        guard let resolvedSourceID else { return }

        let source = CoreMIDIEventSource(sourceID: resolvedSourceID)
        self.source = source
        source.start { event in
            let timestamp = Date().timeIntervalSince1970 * 1000
            let normalized = min(1.0, max(0.0, Double(event.value) / 127.0))

            switch event.kind {
            case .controlChange:
                onEvent(ControlSignal(
                    controlID: "midi:cc:\(event.controller)",
                    kind: .axis,
                    phase: .changed,
                    normalizedValue: normalized,
                    rawValue: event.value,
                    timestamp: timestamp,
                    sourceDeviceID: resolvedSourceID,
                    sourceKind: .midi
                ))
            case .noteOn:
                onEvent(ControlSignal(
                    controlID: "midi:note:\(event.note)",
                    kind: .note,
                    phase: .began,
                    normalizedValue: normalized,
                    rawValue: event.value,
                    timestamp: timestamp,
                    sourceDeviceID: resolvedSourceID,
                    sourceKind: .midi
                ))
            case .noteOff:
                onEvent(ControlSignal(
                    controlID: "midi:note:\(event.note)",
                    kind: .note,
                    phase: .ended,
                    normalizedValue: 0,
                    rawValue: 0,
                    timestamp: timestamp,
                    sourceDeviceID: resolvedSourceID,
                    sourceKind: .midi
                ))
            }
        }
    }

    public func stop() {
        source?.stop()
        source = nil
    }
}

#if canImport(IOKit.hid)

public final class IOHIDHOTASControlSignalSource: ControlSignalSource {
    public let sourceKind: ControlSourceKind = .hotas
    public let sourceName: String = "IOHID HOTAS"

    private var manager: IOHIDManager?
    private var onEvent: ((ControlSignal) -> Void)?
    private var lastDiscreteValues: [String: Int] = [:]
    private var hatDirections: [String: Set<String>] = [:]

    public init() {}

    public static func availableDevices() -> [HOTASDeviceDescriptor] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_Joystick)
            ],
            [
                kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_GamePad)
            ],
            [
                kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_MultiAxisController)
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return []
        }

        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return devices
            .map { device in
                HOTASDeviceDescriptor(
                    id: deviceID(for: device),
                    name: deviceName(for: device)
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    public func start(onEvent: @escaping (ControlSignal) -> Void) {
        stop()
        self.onEvent = onEvent

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_Joystick)
            ],
            [
                kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_GamePad)
            ],
            [
                kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_MultiAxisController)
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if status != kIOReturnSuccess {
            stop()
        }
    }

    public func stop() {
        guard let manager else {
            onEvent = nil
            return
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        onEvent = nil
        lastDiscreteValues.removeAll()
        hatDirections.removeAll()
    }

    private func handle(value: IOHIDValue) {
        guard let onEvent else { return }
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let rawValue = IOHIDValueGetIntegerValue(value)
        let minimum = IOHIDElementGetLogicalMin(element)
        let maximum = IOHIDElementGetLogicalMax(element)
        let normalized = Self.normalize(raw: rawValue, min: minimum, max: maximum)
        let timestamp = Date().timeIntervalSince1970 * 1000
        let kind = signalKind(page: page, usage: usage)
        let device = IOHIDElementGetDevice(element)
        let deviceID = Self.deviceID(for: device)

        if page == Int(kHIDPage_GenericDesktop), usage == Int(kHIDUsage_GD_Hatswitch) {
            emitHatDirections(
                rawValue: rawValue,
                timestamp: timestamp,
                deviceID: deviceID,
                onEvent: onEvent
            )
            onEvent(ControlSignal(
                controlID: "gd:hat",
                kind: .hat,
                phase: .changed,
                normalizedValue: normalized,
                rawValue: rawValue,
                timestamp: timestamp,
                sourceDeviceID: deviceID,
                sourceKind: .hotas
            ))
            return
        }

        let controlID = controlIdentifier(page: page, usage: usage)
        let phase = resolvePhase(
            controlID: "\(deviceID):\(controlID)",
            kind: kind,
            rawValue: rawValue
        )
        onEvent(ControlSignal(
            controlID: controlID,
            kind: kind,
            phase: phase,
            normalizedValue: normalized,
            rawValue: rawValue,
            timestamp: timestamp,
            sourceDeviceID: deviceID,
            sourceKind: .hotas
        ))
    }

    private func emitHatDirections(
        rawValue: Int,
        timestamp: TimeInterval,
        deviceID: String,
        onEvent: (ControlSignal) -> Void
    ) {
        let current = Self.hatDirectionSet(rawValue: rawValue)
        let key = "\(deviceID):hat"
        let previous = hatDirections[key] ?? []
        let added = current.subtracting(previous)
        let removed = previous.subtracting(current)
        hatDirections[key] = current

        for direction in added {
            onEvent(ControlSignal(
                controlID: "gd:hat:\(direction)",
                kind: .hat,
                phase: .began,
                normalizedValue: 1,
                rawValue: 1,
                timestamp: timestamp,
                sourceDeviceID: deviceID,
                sourceKind: .hotas
            ))
        }

        for direction in removed {
            onEvent(ControlSignal(
                controlID: "gd:hat:\(direction)",
                kind: .hat,
                phase: .ended,
                normalizedValue: 0,
                rawValue: 0,
                timestamp: timestamp,
                sourceDeviceID: deviceID,
                sourceKind: .hotas
            ))
        }
    }

    private func resolvePhase(controlID: String, kind: ControlSignalKind, rawValue: Int) -> ControlSignalPhase {
        guard kind == .button || kind == .hat else {
            return .changed
        }
        let previous = lastDiscreteValues[controlID] ?? 0
        lastDiscreteValues[controlID] = rawValue
        if rawValue > 0, previous == 0 {
            return .began
        }
        if rawValue == 0, previous > 0 {
            return .ended
        }
        return .changed
    }

    private func controlIdentifier(page: Int, usage: Int) -> String {
        if page == Int(kHIDPage_Button) {
            return "btn:\(usage)"
        }

        if page == Int(kHIDPage_GenericDesktop) {
            switch usage {
            case Int(kHIDUsage_GD_X):
                return "gd:x"
            case Int(kHIDUsage_GD_Y):
                return "gd:y"
            case Int(kHIDUsage_GD_Z):
                return "gd:z"
            case Int(kHIDUsage_GD_Rx):
                return "gd:rx"
            case Int(kHIDUsage_GD_Ry):
                return "gd:ry"
            case Int(kHIDUsage_GD_Rz):
                return "gd:rz"
            case Int(kHIDUsage_GD_Slider):
                return "gd:slider"
            case Int(kHIDUsage_GD_Dial):
                return "gd:dial"
            case Int(kHIDUsage_GD_Wheel):
                return "gd:wheel"
            default:
                return "gd:\(usage)"
            }
        }

        return "hid:\(page):\(usage)"
    }

    private func signalKind(page: Int, usage: Int) -> ControlSignalKind {
        if page == Int(kHIDPage_Button) {
            return .button
        }
        if page == Int(kHIDPage_GenericDesktop), usage == Int(kHIDUsage_GD_Hatswitch) {
            return .hat
        }
        if page == Int(kHIDPage_GenericDesktop) {
            return .axis
        }
        return .unknown
    }

    private static func normalize(raw: Int, min minValue: Int, max maxValue: Int) -> Double {
        if maxValue <= minValue {
            return raw > 0 ? 1 : 0
        }
        let normalized = Double(raw - minValue) / Double(maxValue - minValue)
        return Swift.min(1.0, Swift.max(0.0, normalized))
    }

    private static func hatDirectionSet(rawValue: Int) -> Set<String> {
        switch rawValue {
        case 0:
            return ["up"]
        case 1:
            return ["up", "right"]
        case 2:
            return ["right"]
        case 3:
            return ["down", "right"]
        case 4:
            return ["down"]
        case 5:
            return ["down", "left"]
        case 6:
            return ["left"]
        case 7:
            return ["up", "left"]
        default:
            return []
        }
    }

    private static let inputCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let source = Unmanaged<IOHIDHOTASControlSignalSource>.fromOpaque(context).takeUnretainedValue()
        source.handle(value: value)
    }

    private static func deviceID(for device: IOHIDDevice?) -> String {
        guard let device else { return "hotas:unknown" }
        let vendor = propertyInt(kIOHIDVendorIDKey, device: device)
        let product = propertyInt(kIOHIDProductIDKey, device: device)
        let location = propertyInt(kIOHIDLocationIDKey, device: device)
        return "hotas:\(vendor):\(product):\(location)"
    }

    private static func deviceName(for device: IOHIDDevice) -> String {
        if let product = propertyString(kIOHIDProductKey, device: device), !product.isEmpty {
            return product
        }
        let vendor = propertyInt(kIOHIDVendorIDKey, device: device)
        let product = propertyInt(kIOHIDProductIDKey, device: device)
        return "HID \(vendor):\(product)"
    }

    private static func propertyInt(_ key: String, device: IOHIDDevice) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return 0 }
        if CFGetTypeID(value) == CFNumberGetTypeID() {
            return (value as? NSNumber)?.intValue ?? 0
        }
        return 0
    }

    private static func propertyString(_ key: String, device: IOHIDDevice) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        if CFGetTypeID(value) == CFStringGetTypeID() {
            return value as? String
        }
        return nil
    }
}

#else

public final class IOHIDHOTASControlSignalSource: ControlSignalSource {
    public let sourceKind: ControlSourceKind = .hotas
    public let sourceName: String = "IOHID HOTAS (Unavailable)"

    public init() {}

    public static func availableDevices() -> [HOTASDeviceDescriptor] {
        []
    }

    public func start(onEvent: @escaping (ControlSignal) -> Void) {
        _ = onEvent
    }

    public func stop() {}
}

#endif

public final class InputMultiplexer {
    private let sources: [ControlSignalSource]
    private let sourcePriority: [ControlSourceKind: Int]
    private let holdoffSeconds: TimeInterval

    private var onEvent: ((ControlSignal) -> Void)?
    private var controlOwners: [String: (kind: ControlSourceKind, lastAt: TimeInterval)] = [:]

    public init(
        sources: [ControlSignalSource],
        sourcePriority: [ControlSourceKind: Int] = [.hotas: 0, .midi: 1],
        holdoffSeconds: TimeInterval = 0.35
    ) {
        self.sources = sources
        self.sourcePriority = sourcePriority
        self.holdoffSeconds = holdoffSeconds
    }

    public func start(onEvent: @escaping (ControlSignal) -> Void) {
        stop()
        self.onEvent = onEvent
        for source in sources {
            source.start { [weak self] signal in
                self?.accept(signal)
            }
        }
    }

    public func stop() {
        for source in sources {
            source.stop()
        }
        onEvent = nil
        controlOwners.removeAll()
    }

    private func accept(_ signal: ControlSignal) {
        let now = Date().timeIntervalSince1970
        let incomingPriority = sourcePriority[signal.sourceKind] ?? Int.max
        let ownerKey = "\(signal.sourceDeviceID):\(signal.controlID)"

        if let owner = controlOwners[ownerKey] {
            let ownerPriority = sourcePriority[owner.kind] ?? Int.max
            let ownerStillActive = (now - owner.lastAt) < holdoffSeconds
            if ownerStillActive, ownerPriority < incomingPriority {
                return
            }
        }

        controlOwners[ownerKey] = (kind: signal.sourceKind, lastAt: now)
        onEvent?(signal)
    }
}
