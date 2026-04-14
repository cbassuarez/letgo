import AppKit
import Foundation
import SwiftUI

struct VufineScreenDescriptor: Equatable, Sendable {
    let id: String
    let name: String
    let frame: CGRect
    let isPrimary: Bool
}

enum VufineDisplayRoute: Equatable, Sendable {
    case external(name: String)
    case primaryFallback(name: String)
    case unavailable

    var summary: String {
        switch self {
        case .external(let name):
            return "VUFINE: EXTERNAL (\(name))"
        case .primaryFallback(let name):
            return "VUFINE: PRIMARY FALLBACK (\(name))"
        case .unavailable:
            return "VUFINE: NO DISPLAY"
        }
    }
}

@MainActor
final class VufineDisplayCoordinator: ObservableObject {
    @Published private(set) var route: VufineDisplayRoute = .unavailable

    private weak var window: NSWindow?
    private var screenObserver: NSObjectProtocol?

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func attach(window: NSWindow) {
        self.window = window
        configureVufineWindow(window)
        observeScreenChangesIfNeeded()
        refreshPlacement()
    }

    func detach() {
        window = nil
        route = .unavailable
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    func refreshPlacement() {
        guard let window else {
            route = .unavailable
            return
        }

        let descriptors = Self.currentScreens()
        let preferredRoute = Self.preferredRoute(for: descriptors)
        route = preferredRoute

        guard let targetDescriptor = Self.targetDescriptor(for: preferredRoute),
              let targetScreen = NSScreen.screens.first(where: { Self.screenID(for: $0) == targetDescriptor.id }) else {
            return
        }

        window.setFrame(targetScreen.frame, display: true, animate: false)
        window.orderFrontRegardless()
    }

    nonisolated static func preferredRoute(for screens: [VufineScreenDescriptor]) -> VufineDisplayRoute {
        if let external = screens.first(where: { !$0.isPrimary }) {
            return .external(name: external.name)
        }
        if let primary = screens.first(where: \.isPrimary) ?? screens.first {
            return .primaryFallback(name: primary.name)
        }
        return .unavailable
    }

    nonisolated static func hasExternalDisplay(_ screens: [VufineScreenDescriptor]) -> Bool {
        screens.contains(where: { !$0.isPrimary })
    }

    @MainActor
    func externalDisplayCurrentlyAvailable() -> Bool {
        Self.hasExternalDisplay(Self.currentScreens())
    }

    private func observeScreenChangesIfNeeded() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPlacement()
            }
        }
    }

    private func configureVufineWindow(_ window: NSWindow) {
        var style = window.styleMask
        style.remove([.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView])
        style.insert(.borderless)
        window.styleMask = style
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.level = .normal
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.isMovable = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }

    private static func targetDescriptor(for route: VufineDisplayRoute) -> VufineScreenDescriptor? {
        let screens = currentScreens()
        switch route {
        case .external(let name):
            return screens.first(where: { !$0.isPrimary && $0.name == name })
                ?? screens.first(where: { !$0.isPrimary })
        case .primaryFallback(let name):
            return screens.first(where: { $0.isPrimary && $0.name == name })
                ?? screens.first(where: \.isPrimary)
                ?? screens.first
        case .unavailable:
            return nil
        }
    }

    private static func currentScreens() -> [VufineScreenDescriptor] {
        let mainID = NSScreen.main.map(screenID(for:))
        return NSScreen.screens.enumerated().map { index, screen in
            let id = screenID(for: screen)
            let isPrimary = id == mainID
            return VufineScreenDescriptor(
                id: id,
                name: screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName,
                frame: screen.frame,
                isPrimary: isPrimary
            )
        }
    }

    private static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return String(ObjectIdentifier(screen).hashValue)
    }
}
