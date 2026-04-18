import AVFoundation
import CoreAudio
import Foundation

public struct AudioRoute: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let channelCount: Int
    public let isSystemDefault: Bool

    public init(id: String, name: String, channelCount: Int, isSystemDefault: Bool = false) {
        self.id = id
        self.name = name
        self.channelCount = channelCount
        self.isSystemDefault = isSystemDefault
    }
}

public enum AudioRouterError: LocalizedError {
    case routeNotFound(String)
    case coreAudioFailure(OSStatus, String)

    public var errorDescription: String? {
        switch self {
        case .routeNotFound(let id):
            return "Audio device not found for route id: \(id)"
        case .coreAudioFailure(let status, let operation):
            return "\(operation) failed (OSStatus \(status))"
        }
    }
}

public final class AudioRouter {
    private let fallbackEngine = AVAudioEngine()

    public init() {}

    public func availableRoutes() -> [AudioRoute] {
        let deviceIDs = outputDeviceIDs()
        let defaultDeviceID = currentDefaultOutputDeviceID()
        var routes: [AudioRoute] = []

        for deviceID in deviceIDs {
            let channelCount = outputChannelCount(deviceID: deviceID)
            guard channelCount > 0 else { continue }
            let id = deviceUID(deviceID: deviceID) ?? "device-\(deviceID)"
            let name = deviceName(deviceID: deviceID) ?? "Audio Device \(deviceID)"
            routes.append(AudioRoute(
                id: id,
                name: name,
                channelCount: channelCount,
                isSystemDefault: deviceID == defaultDeviceID
            ))
        }

        if routes.isEmpty {
            let fallbackChannels = Int(fallbackEngine.outputNode.outputFormat(forBus: 0).channelCount)
            routes = [
                AudioRoute(
                    id: "default-output",
                    name: "Default Output Device",
                    channelCount: max(2, fallbackChannels),
                    isSystemDefault: true
                )
            ]
        } else {
            routes.sort { lhs, rhs in
                if lhs.isSystemDefault != rhs.isSystemDefault {
                    return lhs.isSystemDefault && !rhs.isSystemDefault
                }
                if lhs.channelCount != rhs.channelCount {
                    return lhs.channelCount > rhs.channelCount
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        return routes
    }

    @discardableResult
    public func setDefaultOutputRoute(routeID: String) throws -> Bool {
        let trimmed = routeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed == "default-output" { return false }

        let targetDeviceID = outputDeviceIDs().first { deviceUID(deviceID: $0) == trimmed }
        guard let targetDeviceID else {
            throw AudioRouterError.routeNotFound(trimmed)
        }

        if currentDefaultOutputDeviceID() == targetDeviceID {
            return false
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var writableTarget = targetDeviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &writableTarget
        )
        guard status == noErr else {
            throw AudioRouterError.coreAudioFailure(status, "Set default output device")
        }
        return true
    }

    public func startEngine() throws {
        if !fallbackEngine.isRunning {
            try fallbackEngine.start()
        }
    }

    public func stopEngine() {
        fallbackEngine.stop()
    }

    private func outputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard dataStatus == noErr else { return [] }
        return deviceIDs
    }

    private func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else { return nil }
        return deviceID
    }

    private func outputChannelCount(deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return 0 }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let bufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        let dataStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            bufferList
        )
        guard dataStatus == noErr else { return 0 }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(into: 0) { result, buffer in
            result += Int(buffer.mNumberChannels)
        }
    }

    private func deviceName(deviceID: AudioDeviceID) -> String? {
        stringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private func deviceUID(deviceID: AudioDeviceID) -> String? {
        stringProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<CFString?>.alignment
        )
        let typedPointer = rawPointer.bindMemory(to: CFString?.self, capacity: 1)
        typedPointer.initialize(repeating: nil, count: 1)
        defer {
            typedPointer.deinitialize(count: 1)
            rawPointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            rawPointer
        )
        guard status == noErr else { return nil }
        guard let cfString = typedPointer.pointee else { return nil }
        return cfString as String
    }
}
