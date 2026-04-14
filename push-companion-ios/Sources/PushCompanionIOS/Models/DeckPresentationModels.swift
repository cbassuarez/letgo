import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum DeckLayoutProfile: String, CaseIterable {
    case expanded
    case standard
    case compact

    static func profile(for size: CGSize) -> DeckLayoutProfile {
        let shortestEdge = min(size.width, size.height)
        if size.width >= 1220, shortestEdge >= 720 {
            return .expanded
        }
        if size.width >= 920, shortestEdge >= 620 {
            return .standard
        }
        return .compact
    }

    var outerPadding: CGFloat {
        switch self {
        case .expanded:
            return 22
        case .standard:
            return 18
        case .compact:
            return 14
        }
    }

    var verticalSpacing: CGFloat {
        switch self {
        case .expanded:
            return 12
        case .standard:
            return 10
        case .compact:
            return 8
        }
    }

    var actionRailLimit: Int {
        switch self {
        case .expanded:
            return 12
        case .standard:
            return 10
        case .compact:
            return 8
        }
    }

    var macroCellMinHeight: CGFloat {
        switch self {
        case .expanded:
            return 74
        case .standard:
            return 66
        case .compact:
            return 58
        }
    }

    var commandRailControlSize: ControlSize {
        switch self {
        case .expanded:
            return .regular
        case .standard:
            return .small
        case .compact:
            return .mini
        }
    }
}

enum DeckHandedness: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    mutating func toggle() {
        self = self == .left ? .right : .left
    }
}

enum DeckActionSeverity: String, Codable {
    case info
    case act
    case apply
    case block
    case error

    var color: Color {
        switch self {
        case .info:
            return DeckThemeTokens.textMuted
        case .act:
            return DeckThemeTokens.accentMain
        case .apply:
            return DeckThemeTokens.accentApply
        case .block:
            return DeckThemeTokens.accentWarn
        case .error:
            return DeckThemeTokens.accentError
        }
    }
}

struct DeckActionRailEntry: Identifiable, Hashable {
    var id = UUID()
    var timestamp: Date
    var severity: DeckActionSeverity
    var message: String
    var coalescedCount: Int
    var coalescingKey: String?

    var displayMessage: String {
        if coalescedCount > 1 {
            return "\(message) x\(coalescedCount)"
        }
        return message
    }
}

struct DeckActionFlashEvent: Equatable {
    var id = UUID()
    var message: String
    var severity: DeckActionSeverity
    var createdAt: Date = .init()
}

struct PushDeckSettingsState: Equatable {
    var hostDraft: String
    var mirrorHandedness: DeckHandedness
    var prefersHighContrast: Bool
}

struct PushNotesPresentationState: Equatable {
    var isPresented: Bool
}

struct ProposalCardState: Identifiable, Equatable {
    enum Lane: String {
        case audio
        case visualText = "visual_text"
        case unknown

        var displayName: String {
            switch self {
            case .audio:
                return "AUDIO ADD"
            case .visualText:
                return "VISUAL/TEXT"
            case .unknown:
                return "PROPOSAL"
            }
        }
    }

    var id: String
    var lane: Lane
    var confidence: Double
    var rationale: String
    var timeoutMs: Int
    var createdAt: Date
    var acceptHint: String

    var countdownSeconds: Int {
        max(0, Int(ceil(Double(timeoutMs) / 1000.0)))
    }
}

struct DeckThemeTokens {
    static let backgroundTop = Color(red: 0.01, green: 0.03, blue: 0.08)
    static let backgroundBottom = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let panelFill = Color.white.opacity(0.08)
    static let panelStroke = Color.white.opacity(0.16)
    static let textPrimary = Color.white.opacity(0.95)
    static let textMuted = Color.white.opacity(0.70)
    static let accentMain = Color(red: 0.26, green: 0.66, blue: 1.0)
    static let accentApply = Color(red: 0.38, green: 0.93, blue: 0.56)
    static let accentWarn = Color(red: 1.0, green: 0.78, blue: 0.26)
    static let accentError = Color(red: 1.0, green: 0.34, blue: 0.34)

    static let stageGradient = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func monoFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let fontName = ibmPlexMonoFontName(for: weight)
        #if canImport(UIKit)
        if UIFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size).weight(weight)
        }
        #endif
        return .system(size: size, weight: weight, design: .monospaced)
    }

    private static func ibmPlexMonoFontName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .black, .heavy:
            return "IBMPlexMono-Bold"
        case .semibold:
            return "IBMPlexMono-SemiBold"
        case .medium:
            return "IBMPlexMono-Medium"
        default:
            return "IBMPlexMono-Regular"
        }
    }
}
