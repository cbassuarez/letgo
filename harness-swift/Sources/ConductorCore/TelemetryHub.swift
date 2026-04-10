import Foundation

public actor TelemetryHub {
    private var devices: [String: DeviceTelemetry] = [:]

    public init() {}

    public func upsertDevice(id: String, permissions: DevicePermissions, zoneName: String?) {
        let current = devices[id]
        devices[id] = DeviceTelemetry(
            id: id,
            lastSeen: Date(),
            zoneName: zoneName ?? current?.zoneName,
            permissions: permissions
        )
    }

    public func markSeen(id: String) {
        guard var existing = devices[id] else { return }
        existing.lastSeen = Date()
        devices[id] = existing
    }

    public func allDevices() -> [DeviceTelemetry] {
        devices.values.sorted { lhs, rhs in lhs.lastSeen > rhs.lastSeen }
    }
}
