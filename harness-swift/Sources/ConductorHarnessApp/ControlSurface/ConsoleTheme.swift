import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Single source of truth for the launch-console look.
/// All colors, fonts, and metric constants used by the control-surface
/// components live here so the panels feel like one continuous console.
enum ConsoleTheme {
    // MARK: Backgrounds & chrome

    static let consoleBackground = Color(red: 0.045, green: 0.05, blue: 0.058)
    static let panelFill = Color(red: 0.085, green: 0.092, blue: 0.105)
    static let panelInnerFill = Color(red: 0.12, green: 0.13, blue: 0.145)
    static let panelStroke = Color(red: 0.22, green: 0.235, blue: 0.255)
    static let panelHighlight = Color.white.opacity(0.06)
    static let bezelDark = Color.black.opacity(0.85)
    static let labelTape = Color(red: 0.92, green: 0.9, blue: 0.78)
    static let labelTapeInk = Color(red: 0.08, green: 0.08, blue: 0.1)

    // MARK: Lamps & status

    static let lampOff = Color(red: 0.16, green: 0.17, blue: 0.19)
    static let lampStandby = Color(red: 0.45, green: 0.48, blue: 0.55)
    static let lampGreen = Color(red: 0.32, green: 0.92, blue: 0.45)
    static let lampAmber = Color(red: 1.0, green: 0.66, blue: 0.16)
    static let lampRed = Color(red: 1.0, green: 0.28, blue: 0.28)
    static let lampBlue = Color(red: 0.36, green: 0.7, blue: 1.0)

    // MARK: Segmented display

    static let segmentOn = Color(red: 1.0, green: 0.82, blue: 0.32)
    static let segmentOff = Color.white.opacity(0.04)
    static let segmentOnAmber = Color(red: 1.0, green: 0.66, blue: 0.16)
    static let segmentOnRed = Color(red: 1.0, green: 0.32, blue: 0.32)

    // MARK: Stripes (safety cover)

    static let warningStripeYellow = Color(red: 0.98, green: 0.78, blue: 0.05)
    static let warningStripeBlack = Color.black

    // MARK: Fonts

    static func labelTapeFont(size: CGFloat = 10) -> Font {
        monoFont(size: size, weight: .heavy)
    }

    static func panelTitleFont(size: CGFloat = 11) -> Font {
        monoFont(size: size, weight: .black)
    }

    static func telemetryFont(size: CGFloat = 11) -> Font {
        monoFont(size: size, weight: .medium)
    }

    static func segmentFont(size: CGFloat = 64) -> Font {
        monoFont(size: size, weight: .heavy)
    }

    static func smallTagFont(size: CGFloat = 9) -> Font {
        monoFont(size: size, weight: .black)
    }

    static func monoFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .bold, .black, .heavy:
            name = "IBMPlexMono-Bold"
        case .semibold:
            name = "IBMPlexMono-SemiBold"
        case .medium:
            name = "IBMPlexMono-Medium"
        default:
            name = "IBMPlexMono-Regular"
        }
        #if canImport(AppKit)
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size).weight(weight)
        }
        #endif
        return .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Metrics

    static let panelCornerRadius: CGFloat = 6
    static let panelStrokeWidth: CGFloat = 1
    static let bezelInset: CGFloat = 4
    static let lampDiameter: CGFloat = 14
    static let largeLampDiameter: CGFloat = 18

    // MARK: Severity → lamp colors

    static func color(for severity: StatusLineSeverityHint) -> Color {
        switch severity {
        case .info: return lampBlue
        case .success: return lampGreen
        case .warn: return lampAmber
        case .error: return lampRed
        }
    }
}

/// Bridge enum so theme code does not need to import ConductorCore directly
/// in every component (it still does in views that need it).
enum StatusLineSeverityHint {
    case info
    case success
    case warn
    case error
}
