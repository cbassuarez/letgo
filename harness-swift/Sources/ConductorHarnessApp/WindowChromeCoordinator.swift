import AppKit

@MainActor
enum WindowChromeCoordinator {
    static func applyChromelessHUD(to window: NSWindow, isResizable: Bool) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        window.hasShadow = true

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        var style = window.styleMask
        style.insert(.fullSizeContentView)
        if isResizable {
            style.insert(.resizable)
        } else {
            style.remove(.resizable)
        }
        window.styleMask = style
    }
}
