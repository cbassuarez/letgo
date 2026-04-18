import Foundation

#if canImport(CoreMIDI)
import CoreMIDI

public struct MIDIInputEndpointDescriptor: Identifiable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class CoreMIDIEventSource: MIDIEventSource {
    private let sourceID: String
    private var onEvent: ((MIDIEvent) -> Void)?
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSource = MIDIEndpointRef()
    private var isRunning = false

    public init(sourceID: String) {
        self.sourceID = sourceID
    }

    public static func availableInputs() -> [MIDIInputEndpointDescriptor] {
        let sourceCount = MIDIGetNumberOfSources()
        guard sourceCount > 0 else { return [] }

        var inputs: [MIDIInputEndpointDescriptor] = []
        for index in 0 ..< sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            guard let id = sourceUniqueID(source) else { continue }
            let name = sourceName(source) ?? "MIDI Source \(index + 1)"
            inputs.append(MIDIInputEndpointDescriptor(id: id, name: name))
        }
        return inputs.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func start(onEvent: @escaping (MIDIEvent) -> Void) {
        self.onEvent = onEvent
        guard !isRunning else { return }
        isRunning = true

        let clientStatus = MIDIClientCreateWithBlock("ConductorHarnessMIDIClient" as CFString, &client) { _ in }
        guard clientStatus == noErr else {
            stop()
            return
        }

        let portStatus = MIDIInputPortCreateWithBlock(client, "ConductorHarnessMIDIInput" as CFString, &inputPort) {
            [weak self] packetList, _ in
            self?.handle(packetList: packetList)
        }
        guard portStatus == noErr else {
            stop()
            return
        }

        guard let source = Self.source(for: sourceID) else {
            stop()
            return
        }

        connectedSource = source
        let connectStatus = MIDIPortConnectSource(inputPort, source, nil)
        guard connectStatus == noErr else {
            stop()
            return
        }
    }

    public func stop() {
        if connectedSource != 0, inputPort != 0 {
            MIDIPortDisconnectSource(inputPort, connectedSource)
        }
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
        connectedSource = 0
        onEvent = nil
        isRunning = false
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        guard let onEvent else { return }

        var packet = packetList.pointee.packet
        for _ in 0 ..< packetList.pointee.numPackets {
            let bytes = Self.packetBytes(packet)
            parseMessages(bytes: bytes, onEvent: onEvent)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func parseMessages(bytes: [UInt8], onEvent: (MIDIEvent) -> Void) {
        guard !bytes.isEmpty else { return }
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            if status < 0x80 {
                // Running-status streams are uncommon on modern controllers.
                // Skip orphaned data bytes instead of mis-parsing.
                index += 1
                continue
            }
            let statusType = status & 0xF0
            let channel = Int(status & 0x0F)
            let messageLength = Self.messageLength(forStatus: statusType)
            guard messageLength > 0, index + messageLength <= bytes.count else {
                break
            }

            if messageLength >= 3 {
                let data1 = Int(bytes[index + 1])
                let data2 = Int(bytes[index + 2])
                switch statusType {
                case 0x80:
                    onEvent(.noteOff(note: data1, velocity: data2, channel: channel))
                case 0x90:
                    if data2 == 0 {
                        onEvent(.noteOff(note: data1, velocity: data2, channel: channel))
                    } else {
                        onEvent(.noteOn(note: data1, velocity: data2, channel: channel))
                    }
                case 0xB0:
                    onEvent(MIDIEvent(controller: data1, value: data2, channel: channel))
                default:
                    break
                }
            }

            index += messageLength
        }
    }

    private static func messageLength(forStatus status: UInt8) -> Int {
        switch status {
        case 0x80 ... 0xBF, 0xE0 ... 0xEF:
            return 3
        case 0xC0 ... 0xDF:
            return 2
        default:
            return 1
        }
    }

    private static func packetBytes(_ packet: MIDIPacket) -> [UInt8] {
        let count = Int(packet.length)
        return withUnsafeBytes(of: packet.data) { rawBuffer in
            Array(rawBuffer.prefix(count))
        }
    }

    private static func source(for id: String) -> MIDIEndpointRef? {
        let sourceCount = MIDIGetNumberOfSources()
        guard sourceCount > 0 else { return nil }

        for index in 0 ..< sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            if sourceUniqueID(source) == id {
                return source
            }
        }
        return nil
    }

    private static func sourceUniqueID(_ source: MIDIEndpointRef) -> String? {
        var uniqueID: MIDIUniqueID = 0
        let status = MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID)
        guard status == noErr else { return nil }
        return String(uniqueID)
    }

    private static func sourceName(_ source: MIDIEndpointRef) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &unmanagedName) == noErr,
           let unmanagedName {
            return unmanagedName.takeRetainedValue() as String
        }

        var unmanagedFallback: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(source, kMIDIPropertyName, &unmanagedFallback) == noErr,
           let unmanagedFallback {
            return unmanagedFallback.takeRetainedValue() as String
        }
        return nil
    }
}

public struct MIDIOutputEndpointDescriptor: Identifiable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class CoreMIDIOutputEngine {
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var destination = MIDIEndpointRef()
    private(set) public var armedDestinationID: String?

    public init() {}

    deinit {
        disarm()
    }

    public static func availableDestinations() -> [MIDIOutputEndpointDescriptor] {
        let destinationCount = MIDIGetNumberOfDestinations()
        guard destinationCount > 0 else { return [] }

        var outputs: [MIDIOutputEndpointDescriptor] = []
        for index in 0 ..< destinationCount {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }
            guard let id = endpointUniqueID(endpoint) else { continue }
            let name = endpointName(endpoint) ?? "MIDI Destination \(index + 1)"
            outputs.append(MIDIOutputEndpointDescriptor(id: id, name: name))
        }
        return outputs.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func arm(destinationID: String) -> Bool {
        disarm()

        let clientStatus = MIDIClientCreateWithBlock("ConductorHarnessMIDIOutClient" as CFString, &client) { _ in }
        guard clientStatus == noErr else {
            disarm()
            return false
        }

        let portStatus = MIDIOutputPortCreate(client, "ConductorHarnessMIDIOutput" as CFString, &outputPort)
        guard portStatus == noErr else {
            disarm()
            return false
        }

        guard let endpoint = Self.destination(for: destinationID) else {
            disarm()
            return false
        }

        destination = endpoint
        armedDestinationID = destinationID
        return true
    }

    public func disarm() {
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
            outputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
        destination = 0
        armedDestinationID = nil
    }

    public func sendNoteOn(note: Int, velocity: Int, channel: Int) {
        sendShortMessage(statusBase: 0x90, data1: note, data2: velocity, channel: channel)
    }

    public func sendNoteOff(note: Int, velocity: Int = 0, channel: Int) {
        sendShortMessage(statusBase: 0x80, data1: note, data2: velocity, channel: channel)
    }

    public func sendControlChange(controller: Int, value: Int, channel: Int) {
        sendShortMessage(statusBase: 0xB0, data1: controller, data2: value, channel: channel)
    }

    public func sendProgramChange(program: Int, channel: Int) {
        guard isArmed else { return }
        let status = UInt8((0xC0 | (max(0, min(15, channel)) & 0x0F)) & 0xFF)
        send(bytes: [status, UInt8(max(0, min(127, program)))])
    }

    public func sendBankSelect(bankMSB: Int, bankLSB: Int? = nil, channel: Int) {
        sendControlChange(controller: 0, value: bankMSB, channel: channel)
        if let bankLSB {
            sendControlChange(controller: 32, value: bankLSB, channel: channel)
        }
    }

    public func sendClockTick() {
        guard isArmed else { return }
        send(bytes: [0xF8])
    }

    public func sendStart() {
        guard isArmed else { return }
        send(bytes: [0xFA])
    }

    public func sendStop() {
        guard isArmed else { return }
        send(bytes: [0xFC])
    }

    public var isArmed: Bool {
        outputPort != 0 && destination != 0 && armedDestinationID != nil
    }

    private func sendShortMessage(statusBase: Int, data1: Int, data2: Int, channel: Int) {
        guard isArmed else { return }
        let status = UInt8((statusBase | (max(0, min(15, channel)) & 0x0F)) & 0xFF)
        let clipped1 = UInt8(max(0, min(127, data1)))
        let clipped2 = UInt8(max(0, min(127, data2)))
        send(bytes: [status, clipped1, clipped2])
    }

    private func send(bytes: [UInt8]) {
        guard isArmed, !bytes.isEmpty else { return }
        var packetList = MIDIPacketList()
        bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var packet = MIDIPacketListInit(&packetList)
            packet = MIDIPacketListAdd(
                &packetList,
                1024,
                packet,
                0,
                buffer.count,
                baseAddress
            )
        }
        MIDISend(outputPort, destination, &packetList)
    }

    private static func destination(for id: String) -> MIDIEndpointRef? {
        let destinationCount = MIDIGetNumberOfDestinations()
        guard destinationCount > 0 else { return nil }

        for index in 0 ..< destinationCount {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }
            if endpointUniqueID(endpoint) == id {
                return endpoint
            }
        }
        return nil
    }

    private static func endpointUniqueID(_ endpoint: MIDIEndpointRef) -> String? {
        var uniqueID: MIDIUniqueID = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
        guard status == noErr else { return nil }
        return String(uniqueID)
    }

    private static func endpointName(_ endpoint: MIDIEndpointRef) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName) == noErr,
           let unmanagedName {
            return unmanagedName.takeRetainedValue() as String
        }

        var unmanagedFallback: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &unmanagedFallback) == noErr,
           let unmanagedFallback {
            return unmanagedFallback.takeRetainedValue() as String
        }
        return nil
    }
}

#else

public struct MIDIInputEndpointDescriptor: Identifiable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class CoreMIDIEventSource: MIDIEventSource {
    public init(sourceID: String) {
        _ = sourceID
    }

    public static func availableInputs() -> [MIDIInputEndpointDescriptor] {
        []
    }

    public func start(onEvent: @escaping (MIDIEvent) -> Void) {
        _ = onEvent
    }

    public func stop() {}
}

public struct MIDIOutputEndpointDescriptor: Identifiable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class CoreMIDIOutputEngine {
    public private(set) var armedDestinationID: String?
    public init() {}
    public static func availableDestinations() -> [MIDIOutputEndpointDescriptor] { [] }
    public func arm(destinationID: String) -> Bool {
        _ = destinationID
        return false
    }
    public func disarm() {
        armedDestinationID = nil
    }
    public var isArmed: Bool { false }
    public func sendNoteOn(note: Int, velocity: Int, channel: Int) {
        _ = (note, velocity, channel)
    }
    public func sendNoteOff(note: Int, velocity: Int = 0, channel: Int) {
        _ = (note, velocity, channel)
    }
    public func sendControlChange(controller: Int, value: Int, channel: Int) {
        _ = (controller, value, channel)
    }
    public func sendProgramChange(program: Int, channel: Int) {
        _ = (program, channel)
    }
    public func sendBankSelect(bankMSB: Int, bankLSB: Int? = nil, channel: Int) {
        _ = (bankMSB, bankLSB, channel)
    }
    public func sendClockTick() {}
    public func sendStart() {}
    public func sendStop() {}
}

#endif
