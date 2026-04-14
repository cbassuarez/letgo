import AVFoundation
import AppKit
import SwiftUI

struct LowLatencyPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.videoGravity = gravity
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        nsView.playerLayer.videoGravity = gravity
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }
}

final class PlayerLayerHostView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindowResolved: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindowResolved = onWindowResolved
        return view
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindowResolved = onWindowResolved
        nsView.resolveWindowIfNeeded()
    }
}

final class WindowAccessorView: NSView {
    var onWindowResolved: ((NSWindow) -> Void)?
    private weak var lastResolvedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindowIfNeeded()
    }

    func resolveWindowIfNeeded() {
        guard let window else { return }
        guard lastResolvedWindow !== window else { return }
        lastResolvedWindow = window
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.onWindowResolved?(window)
        }
    }
}
