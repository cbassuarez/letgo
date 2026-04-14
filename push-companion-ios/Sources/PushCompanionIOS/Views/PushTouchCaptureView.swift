import SwiftUI
import UIKit

struct PushTouchPoint {
    let id: Int
    let location: CGPoint
    let force: CGFloat
}

struct PushMultiTouchCaptureView: UIViewRepresentable {
    let onTouchesChanged: ([PushTouchPoint]) -> Void
    let onTouchesEnded: () -> Void

    func makeUIView(context: Context) -> PushTouchCaptureUIView {
        let view = PushTouchCaptureUIView()
        view.onTouchesChanged = onTouchesChanged
        view.onTouchesEnded = onTouchesEnded
        return view
    }

    func updateUIView(_ uiView: PushTouchCaptureUIView, context: Context) {
        uiView.onTouchesChanged = onTouchesChanged
        uiView.onTouchesEnded = onTouchesEnded
    }
}

final class PushTouchCaptureUIView: UIView {
    var onTouchesChanged: (([PushTouchPoint]) -> Void)?
    var onTouchesEnded: (() -> Void)?

    private var activeTouches: [ObjectIdentifier: UITouch] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        updateTouches(touches, remove: false)
        emitTouches()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        updateTouches(touches, remove: false)
        emitTouches()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        updateTouches(touches, remove: true)
        emitTouches()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        updateTouches(touches, remove: true)
        emitTouches()
    }

    private func updateTouches(_ touches: Set<UITouch>, remove: Bool) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if remove {
                activeTouches.removeValue(forKey: key)
            } else {
                activeTouches[key] = touch
            }
        }
    }

    private func emitTouches() {
        guard !activeTouches.isEmpty else {
            onTouchesEnded?()
            return
        }

        let points = activeTouches.map { key, touch in
            let normalizedForce: CGFloat
            if touch.maximumPossibleForce > 0 {
                normalizedForce = min(1, max(0, touch.force / touch.maximumPossibleForce))
            } else {
                normalizedForce = min(1, max(0.08, (touch.majorRadius - 6) / 28))
            }
            return PushTouchPoint(
                id: key.hashValue,
                location: touch.location(in: self),
                force: normalizedForce
            )
        }
        onTouchesChanged?(points)
    }
}
