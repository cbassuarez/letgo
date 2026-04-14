import AppKit
import SwiftUI

struct HUDNeedleGaugeView: View {
    let descriptor: HUDGaugeDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(descriptor.title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(descriptor.valueText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(gaugeColor)
                    .lineLimit(1)
            }

            ZStack {
                NeedleGaugeLayerHost(
                    model: descriptor.needle,
                    tint: NSColor(gaugeColor),
                    cautionThreshold: descriptor.cautionThreshold,
                    warningThreshold: descriptor.warningThreshold
                )
                .frame(height: 72)

                VStack {
                    Spacer(minLength: 22)
                    Text(descriptor.unitLabel)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            HUDSparklineView(values: descriptor.sparkline, tint: gaugeColor)
                .frame(height: 16)
        }
        .padding(8)
        .background(Color.black.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
        )
    }

    private var gaugeColor: Color {
        let value = descriptor.needle.normalizedValue
        if value >= descriptor.warningThreshold {
            return Color(red: 1.0, green: 0.33, blue: 0.33)
        }
        if value >= descriptor.cautionThreshold {
            return Color(red: 1.0, green: 0.77, blue: 0.32)
        }
        return Color(red: 0.33, green: 0.86, blue: 1.0)
    }
}

private struct HUDSparklineView: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.04))

                Path { path in
                    let points = normalizedPoints(for: geometry.size)
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func normalizedPoints(for size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else {
            return []
        }

        let horizontalStep = size.width / CGFloat(max(1, values.count - 1))
        return values.enumerated().map { index, value in
            let x = CGFloat(index) * horizontalStep
            let y = size.height - (CGFloat(min(1, max(0, value))) * size.height)
            return CGPoint(x: x, y: y)
        }
    }
}

private struct NeedleGaugeLayerHost: NSViewRepresentable {
    let model: HUDNeedleModel
    let tint: NSColor
    let cautionThreshold: Double
    let warningThreshold: Double

    func makeNSView(context: Context) -> NeedleGaugeLayerView {
        let view = NeedleGaugeLayerView()
        view.update(model: model, tint: tint, cautionThreshold: cautionThreshold, warningThreshold: warningThreshold)
        return view
    }

    func updateNSView(_ nsView: NeedleGaugeLayerView, context: Context) {
        nsView.update(model: model, tint: tint, cautionThreshold: cautionThreshold, warningThreshold: warningThreshold)
    }
}

private final class NeedleGaugeLayerView: NSView {
    private let trackLayer = CAShapeLayer()
    private let cautionLayer = CAShapeLayer()
    private let warningLayer = CAShapeLayer()
    private let needleLayer = CAShapeLayer()
    private let centerDotLayer = CAShapeLayer()

    private var model: HUDNeedleModel = HUDNeedleModel(normalizedValue: 0)
    private var tint: NSColor = .systemTeal
    private var cautionThreshold: Double = 0.7
    private var warningThreshold: Double = 0.9

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()

        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
        trackLayer.lineWidth = 2.5

        cautionLayer.fillColor = NSColor.clear.cgColor
        cautionLayer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.7).cgColor
        cautionLayer.lineWidth = 2.5

        warningLayer.fillColor = NSColor.clear.cgColor
        warningLayer.strokeColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        warningLayer.lineWidth = 2.5

        needleLayer.fillColor = NSColor.clear.cgColor
        needleLayer.lineWidth = 2.2
        needleLayer.lineCap = .round

        centerDotLayer.fillColor = NSColor.white.withAlphaComponent(0.9).cgColor
        centerDotLayer.strokeColor = NSColor.black.withAlphaComponent(0.7).cgColor
        centerDotLayer.lineWidth = 1

        layer?.addSublayer(trackLayer)
        layer?.addSublayer(cautionLayer)
        layer?.addSublayer(warningLayer)
        layer?.addSublayer(needleLayer)
        layer?.addSublayer(centerDotLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(cautionLayer)
        layer?.addSublayer(warningLayer)
        layer?.addSublayer(needleLayer)
        layer?.addSublayer(centerDotLayer)
    }

    override func layout() {
        super.layout()
        renderLayers()
    }

    func update(model: HUDNeedleModel, tint: NSColor, cautionThreshold: Double, warningThreshold: Double) {
        self.model = model
        self.tint = tint
        self.cautionThreshold = min(1, max(0, cautionThreshold))
        self.warningThreshold = min(1, max(self.cautionThreshold, warningThreshold))
        renderLayers()
    }

    private func renderLayers() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.maxY - 4)
        let radius = max(4, min(bounds.width * 0.44, bounds.height * 0.92))

        let start = radians(model.startAngleDegrees)
        let end = radians(model.endAngleDegrees)

        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: CGFloat(model.startAngleDegrees), endAngle: CGFloat(model.endAngleDegrees), clockwise: false)
        trackLayer.path = trackPath.cgPath

        cautionLayer.path = arcPath(center: center, radius: radius, startDegrees: model.startAngleDegrees + ((model.endAngleDegrees - model.startAngleDegrees) * cautionThreshold), endDegrees: model.endAngleDegrees)
        warningLayer.path = arcPath(center: center, radius: radius, startDegrees: model.startAngleDegrees + ((model.endAngleDegrees - model.startAngleDegrees) * warningThreshold), endDegrees: model.endAngleDegrees)

        let angle = radians(model.angleDegrees)
        let needleLength = radius - 6
        let needleEnd = CGPoint(
            x: center.x + (CGFloat(cos(angle)) * needleLength),
            y: center.y + (CGFloat(sin(angle)) * needleLength)
        )

        let needlePath = NSBezierPath()
        needlePath.move(to: center)
        needlePath.line(to: needleEnd)
        needleLayer.path = needlePath.cgPath
        needleLayer.strokeColor = tint.cgColor

        let dotRadius: CGFloat = 4.5
        centerDotLayer.path = CGPath(ellipseIn: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2), transform: nil)

        let alpha = max(0.35, min(1.0, 0.4 + (model.normalizedValue * 0.65)))
        trackLayer.opacity = Float(alpha)
        cautionLayer.opacity = Float(alpha)
        warningLayer.opacity = Float(alpha)

        _ = start
        _ = end
    }

    private func arcPath(center: CGPoint, radius: CGFloat, startDegrees: Double, endDegrees: Double) -> CGPath {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: CGFloat(startDegrees), endAngle: CGFloat(endDegrees), clockwise: false)
        return path.cgPath
    }

    private func radians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180.0
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            let type = element(at: index, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}
