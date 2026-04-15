import Foundation

public enum HOTASLogicalDeviceMatcher {
    public static func classify(sourceDeviceID: String, controlID: String? = nil) -> HOTASLogicalDevice {
        if let controlID, let hinted = classifyControl(controlID: controlID) {
            return hinted
        }

        if sourceDeviceID.lowercased().contains("throttle") {
            return .x56Throttle
        }
        if sourceDeviceID.lowercased().contains("stick") {
            return .x56Stick
        }

        return .unspecified
    }

    public static func normalizedControlID(_ controlID: String) -> String {
        let lowered = controlID.lowercased()
        if let hash = lowered.firstIndex(of: "#") {
            return String(lowered[..<hash])
        }
        if let at = lowered.firstIndex(of: "@") {
            return String(lowered[..<at])
        }
        return lowered
    }

    public static func canonicalControlIDVariants(_ controlID: String) -> Set<String> {
        var variants: Set<String> = []
        var queue: [String] = [controlID.lowercased()]

        while let candidate = queue.popLast() {
            if variants.insert(candidate).inserted {
                if let at = candidate.firstIndex(of: "@") {
                    queue.append(String(candidate[..<at]))
                }
                if let hash = candidate.firstIndex(of: "#") {
                    queue.append(String(candidate[..<hash]))
                }
            }
        }

        return variants
    }

    private static func classifyControl(controlID: String) -> HOTASLogicalDevice? {
        let lowered = normalizedControlID(controlID)

        let stickAxes: Set<String> = ["gd:x", "gd:y", "gd:rx", "gd:ry", "gd:rz", "gd:slider"]
        let throttleAxes: Set<String> = ["gd:z", "gd:wheel", "gd:dial", "gd:42", "gd:43", "gd:slider2", "gd:hat", "gd:hat:up", "gd:hat:right", "gd:hat:down", "gd:hat:left"]

        if stickAxes.contains(lowered) {
            return .x56Stick
        }
        if throttleAxes.contains(lowered) {
            return .x56Throttle
        }

        guard lowered.hasPrefix("btn:"),
              let buttonNumber = Int(lowered.replacingOccurrences(of: "btn:", with: "")) else {
            return nil
        }

        switch buttonNumber {
        case 1 ... 13:
            return .x56Stick
        case 14 ... 63:
            return .x56Throttle
        default:
            return .unspecified
        }
    }
}
