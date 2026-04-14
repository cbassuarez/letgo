import Foundation

@MainActor
final class PushSessionStore: ObservableObject {
    static let defaultBackendHost = "letgo-fe0a.onrender.com"

    @Published var backendHost: String
    @Published private(set) var controllerID: String

    private let defaults: UserDefaults
    private let controllerIDKey = "push_companion.controller_id"
    private let backendHostKey = "push_companion.backend_host"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: controllerIDKey), PushSessionStore.isValidControllerID(stored) {
            controllerID = stored
        } else {
            let generated = PushSessionStore.generateControllerID()
            controllerID = generated
            defaults.set(generated, forKey: controllerIDKey)
        }

        let configuredHost = defaults.string(forKey: backendHostKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredHost, !configuredHost.isEmpty {
            backendHost = configuredHost
        } else {
            backendHost = Self.defaultBackendHost
        }
    }

    func updateBackendHost(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        backendHost = trimmed.isEmpty ? Self.defaultBackendHost : trimmed
        defaults.set(backendHost, forKey: backendHostKey)
    }

    var websocketURL: URL? {
        let trimmedHost = backendHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        return URL(string: "wss://\(trimmedHost)/ws/device/\(controllerID)")
    }

    private static func generateControllerID() -> String {
        let bytes: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...UInt8.max) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidControllerID(_ value: String) -> Bool {
        guard value.count == 32 else { return false }
        return value.allSatisfy { $0.isHexDigit && $0.isASCII }
    }
}
