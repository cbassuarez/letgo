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

#endif
