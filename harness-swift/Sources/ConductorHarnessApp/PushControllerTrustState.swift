import Foundation

struct PushControllerTrustState: Equatable, Codable, Sendable {
    var enabled: Bool
    var trustedControllerIDs: [String]

    init(enabled: Bool = false, trustedControllerIDs: [String] = []) {
        self.enabled = enabled
        self.trustedControllerIDs = trustedControllerIDs
    }
}
