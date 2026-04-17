import AppKit
import Foundation

enum VideoOutDisplayRoute: Equatable, Sendable {
    case external(name: String)
    case externalShared(name: String)
    case primaryFallback(name: String)
    case unavailable

    var summary: String {
        switch self {
        case .external(let name):
            return "VIDEO OUT: EXTERNAL (\(name))"
        case .externalShared(let name):
            return "VIDEO OUT: SHARED EXTERNAL (\(name))"
        case .primaryFallback(let name):
            return "VIDEO OUT: PRIMARY FALLBACK (\(name))"
        case .unavailable:
            return "VIDEO OUT: NO DISPLAY"
        }
    }
}

@MainActor
final class VideoOutDisplayCoordinator: ObservableObject {
    @Published private(set) var route: VideoOutDisplayRoute = .unavailable
    @Published private(set) var activeScreenID: String?

    private weak var window: NSWindow?
    private var screenObserver: NSObjectProtocol?

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func attach(window: NSWindow) {
        self.window = window
        configureVideoOutWindow(window)
        observeScreenChangesIfNeeded()
    }

    func detach() {
        window = nil
        route = .unavailable
        activeScreenID = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    func refreshPlacement(avoidingScreenID: String? = nil) {
        guard let window else {
            route = .unavailable
            activeScreenID = nil
            return
        }

        let descriptors = currentScreens()
        let preferredRoute = Self.preferredRoute(for: descriptors, avoidingScreenID: avoidingScreenID)
        route = preferredRoute

        guard let targetDescriptor = targetDescriptor(
            for: preferredRoute,
            in: descriptors,
            avoidingScreenID: avoidingScreenID
        ), let targetScreen = NSScreen.screens.first(where: { screenID(for: $0) == targetDescriptor.id }) else {
            activeScreenID = window.screen.map(screenID(for:))
            return
        }

        activeScreenID = targetDescriptor.id
        window.setFrame(targetScreen.visibleFrame, display: true, animate: false)
        window.orderFrontRegardless()
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
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

    private func configureVideoOutWindow(_ window: NSWindow) {
        var style = window.styleMask
        style.remove(.borderless)
        style.remove(.fullSizeContentView)
        style.insert([.titled, .miniaturizable, .closable, .resizable])
        window.styleMask = style
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.level = .normal
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = true
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.title = "Video Out"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.sharingType = .readWrite
    }

    nonisolated static func preferredRoute(
        for screens: [VufineScreenDescriptor],
        avoidingScreenID: String?
    ) -> VideoOutDisplayRoute {
        let nonPrimary = screens.filter { !$0.isPrimary }

        if let avoidingScreenID,
           let dedicated = nonPrimary.first(where: { $0.id != avoidingScreenID }) {
            return .external(name: dedicated.name)
        }

        if let shared = nonPrimary.first {
            return .externalShared(name: shared.name)
        }

        if let primary = screens.first(where: \.isPrimary) ?? screens.first {
            return .primaryFallback(name: primary.name)
        }

        return .unavailable
    }

    private func targetDescriptor(
        for route: VideoOutDisplayRoute,
        in screens: [VufineScreenDescriptor],
        avoidingScreenID: String?
    ) -> VufineScreenDescriptor? {
        switch route {
        case .external(let name):
            return screens.first(where: { !$0.isPrimary && $0.name == name && $0.id != avoidingScreenID })
                ?? screens.first(where: { !$0.isPrimary && $0.id != avoidingScreenID })
                ?? screens.first(where: { !$0.isPrimary })
        case .externalShared(let name):
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

    private func currentScreens() -> [VufineScreenDescriptor] {
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

    private func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return String(ObjectIdentifier(screen).hashValue)
    }
}
