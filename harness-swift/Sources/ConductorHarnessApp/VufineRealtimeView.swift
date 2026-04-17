import AVFoundation
import AppKit
import SwiftUI

struct VufineRealtimeView: View {
    @ObservedObject var model: ConductorHarnessViewModel
    @ObservedObject var performanceMode: PerformanceModeState
    @ObservedObject var displayCoordinator: VufineDisplayCoordinator
    @ObservedObject var inspectorPresentation: InspectorPresentationState

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var hudNow: Date = .now

    private let hudTick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    private let hudGreen = Color(red: 0.45, green: 1.0, blue: 0.48)
    private let hudGreenDim = Color(red: 0.33, green: 0.9, blue: 0.43)

    private var hud: VufineHUDSnapshot {
        model.vufineHUDSnapshot
    }

    private var soundSnapshot: SoundSituationalSnapshot {
        model.soundSituationalSnapshot
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: {
                inspectorPresentation.isPresented && inspectorPresentation.source == .vufine
            },
            set: { isPresented in
                if isPresented {
                    inspectorPresentation.present(from: .vufine)
                } else {
                    inspectorPresentation.dismiss()
                }
            }
        )
    }

    private var leftColumnGauges: [HUDGaugeDescriptor] {
        Array(hud.dynamicGauges.prefix(5))
    }

    private var rightColumnGauges: [HUDGaugeDescriptor] {
        Array(hud.dynamicGauges.dropFirst(5).prefix(5))
    }

    private var latestContextEvent: HUDActionEvent? {
        hud.actionFeed.first(where: { event in
            event.severity != .info && isRecent(event, within: 2.8)
        })
    }

    var body: some View {
        ZStack {
            LowLatencyPlayerLayerView(player: model.previewPlayer, gravity: .resizeAspectFill)
                .ignoresSafeArea()

            Color.black.opacity(0.06)
                .ignoresSafeArea()

            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    persistentHUD(size: size)
                    contextualHUD
                    commandCluster
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(14)
            }

            if !model.generatedLine.isEmpty {
                VStack {
                    Spacer()
                    Text(model.generatedLine)
                        .font(.system(size: 19, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hudGreen)
                        .shadow(color: hudGreen.opacity(0.7), radius: 8)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(Color.black.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(hudGreen.opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(18)
                }
                .transition(.opacity)
            }
        }
        .background(Color.black)
        .transaction { tx in
            tx.animation = nil
        }
        .overlay {
            WindowAccessor { window in
                displayCoordinator.attach(window: window)
            }
            .allowsHitTesting(false)
        }
        .onReceive(hudTick) { now in
            hudNow = now
        }
        .onAppear {
            inspectorPresentation.markActive(.vufine)
        }
        .onDisappear {
            displayCoordinator.detach()
        }
        .sheet(isPresented: inspectorBinding) {
            InspectorModalView(model: model, presentation: inspectorPresentation)
        }
    }

    private func persistentHUD(size: CGSize) -> some View {
        ZStack {
            VStack(spacing: 10) {
                topRibbon
                SoundSpineHUDView(snapshot: soundSnapshot)
                Spacer(minLength: 0)
                bottomRibbon
            }

            HStack(alignment: .top, spacing: 10) {
                gaugeColumn(gauges: leftColumnGauges)
                Spacer(minLength: 0)
                gaugeColumn(gauges: rightColumnGauges)
            }
            .padding(.top, 52)
            .padding(.bottom, 110)
        }
    }

    private var contextualHUD: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let event = latestContextEvent {
                    contextEventCard(event)
                }
                Spacer(minLength: 0)
                if let proposal = hud.proposalWidget {
                    proposalCard(proposal)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                actionFeedPanel
            }
        }
    }

    private var topRibbon: some View {
        HStack(spacing: 6) {
            Text("VUFINE MIRROR")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(hudGreen.opacity(0.88))

            ForEach(hud.safetyTokens.prefix(6)) { token in
                statusPill(label: token.label, value: token.value, level: token.level)
            }

            ForEach(hud.modeTokens.prefix(3)) { token in
                statusPill(label: token.label, value: token.value, level: token.level)
            }

            Spacer(minLength: 0)

            Text(hud.transportLine)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.64))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(hudGreen.opacity(0.25), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: hudGreen.opacity(0.15), radius: 8)
    }

    private var bottomRibbon: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hud.vectorLine)
            Text(hud.audioLine)
            Text(hud.ultrachunkLine)
            Text(hud.controlRoleLine)
            Text(hud.statusLine)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(hudGreen.opacity(0.72))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.24))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(hudGreen.opacity(0.23), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func gaugeColumn(gauges: [HUDGaugeDescriptor]) -> some View {
        VStack(spacing: 7) {
            ForEach(gauges) { gauge in
                VufineFlightGaugeView(descriptor: gauge, tint: hudGreen, dimTint: hudGreenDim)
                    .frame(width: 168, height: 72)
            }
        }
    }

    private func contextEventCard(_ event: HUDActionEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(event.stage.rawValue.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                Text(event.severity.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(eventSeverityColor(event.severity))

            Text(event.semanticAction ?? event.controlID)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.9))
                .lineLimit(1)

            Text(event.blockReason ?? event.detail ?? event.outcome)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.68))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(eventSeverityColor(event.severity).opacity(0.55), lineWidth: 0.9)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: eventSeverityColor(event.severity).opacity(0.32), radius: 10)
    }

    private func proposalCard(_ proposal: HUDProposalWidget) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("ML \(proposal.laneLabel) · CONF \(proposal.confidenceText)")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.92))
                .lineLimit(1)

            Text(proposal.expectedEffect)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.72))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text("T-\(proposal.countdownText)s")
                Text(proposal.acceptHint)
                    .fontWeight(.bold)
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(hudGreen)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.34))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(hudGreen.opacity(0.42), lineWidth: 0.9)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: hudGreen.opacity(0.3), radius: 8)
    }

    private var actionFeedPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ACTION STREAM")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.78))

            ForEach(hud.actionFeed.prefix(8)) { event in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(shortTimestamp(event.timestamp))
                        .frame(width: 54, alignment: .leading)
                    Text(event.stage.rawValue.uppercased())
                        .frame(width: 52, alignment: .leading)
                    Text(event.semanticAction ?? event.controlID)
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.7))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: 330, alignment: .leading)
        .background(Color.black.opacity(0.26))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(hudGreen.opacity(0.2), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var commandCluster: some View {
        HStack(spacing: 6) {
            Button {
                inspectorPresentation.present(from: .vufine)
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: AppWindowID.safetyMonitor.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "shield")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: AppWindowID.fullConsole.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: AppWindowID.hotasMapper.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: AppWindowID.videoOut.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "display")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)

            Menu {
                Button("Open Inspector") {
                    inspectorPresentation.present(from: .vufine)
                }
                Button("Open HOTAS Mapper Studio") {
                    openWindow(id: AppWindowID.hotasMapper.rawValue)
                }
                Button("Open Video Out") {
                    openWindow(id: AppWindowID.videoOut.rawValue)
                }
                Button("Startup Chooser") {
                    apply(performanceMode.reopenStartupChooserTransition())
                }
                Button("Safety + Vufine Layout") {
                    apply(performanceMode.transitionToLayout(.safetyAndVufine))
                }
                Button("Safety-Only Layout") {
                    apply(performanceMode.transitionToLayout(.safetyOnly))
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .bold))
            }
            .menuStyle(.borderlessButton)
        }
        .foregroundStyle(hudGreen.opacity(0.94))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.32))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(hudGreen.opacity(0.28), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func statusPill(label: String, value: String, level: HUDStatusTokenLevel) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.65))
            Text(value)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(hudGreen.opacity(0.92))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(tokenBackground(level))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(hudGreen.opacity(0.15), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func tokenBackground(_ level: HUDStatusTokenLevel) -> Color {
        switch level {
        case .nominal:
            return Color.black.opacity(0.34)
        case .caution:
            return Color(red: 0.36, green: 0.28, blue: 0.08).opacity(0.54)
        case .critical:
            return Color(red: 0.4, green: 0.12, blue: 0.12).opacity(0.58)
        case .accent:
            return Color(red: 0.12, green: 0.31, blue: 0.2).opacity(0.6)
        }
    }

    private func eventSeverityColor(_ severity: HUDEventSeverity) -> Color {
        switch severity {
        case .info:
            return hudGreen.opacity(0.72)
        case .act:
            return Color(red: 0.41, green: 1.0, blue: 0.86)
        case .apply:
            return Color(red: 0.45, green: 1.0, blue: 0.52)
        case .block:
            return Color(red: 1.0, green: 0.84, blue: 0.34)
        case .error:
            return Color(red: 1.0, green: 0.42, blue: 0.4)
        }
    }

    private func shortTimestamp(_ timestamp: TimeInterval) -> String {
        Date(timeIntervalSince1970: timestamp)
            .formatted(date: .omitted, time: .standard)
    }

    private func isRecent(_ event: HUDActionEvent, within seconds: TimeInterval) -> Bool {
        (hudNow.timeIntervalSince1970 - event.timestamp) <= seconds
    }

    private func apply(_ transition: PerformanceWindowTransition) {
        for id in transition.close {
            dismissWindow(id: id.rawValue)
        }
        for id in transition.open {
            openWindow(id: id.rawValue)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct VufineFlightGaugeView: View {
    let descriptor: HUDGaugeDescriptor
    let tint: Color
    let dimTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(descriptor.title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.84))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(descriptor.valueText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(needleColor)
                    .lineLimit(1)
            }

            ZStack {
                ArcTrack()
                    .stroke(dimTint.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                ArcTrack(trimEnd: descriptor.needle.normalizedValue)
                    .stroke(needleColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .shadow(color: needleColor.opacity(0.45), radius: 4)

                Rectangle()
                    .fill(needleColor)
                    .frame(width: 1.5, height: 22)
                    .offset(y: -9)
                    .rotationEffect(.degrees(needleAngle))
                    .shadow(color: needleColor.opacity(0.45), radius: 4)

                Circle()
                    .fill(needleColor)
                    .frame(width: 4, height: 4)

                Text(descriptor.unitLabel)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.58))
                    .offset(y: 16)
                    .lineLimit(1)
            }
            .frame(height: 40)

            SparklineBand(values: descriptor.sparkline, tint: needleColor)
                .frame(height: 10)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.24))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(tint.opacity(0.18), lineWidth: 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var needleAngle: Double {
        -120 + (240 * descriptor.needle.normalizedValue)
    }

    private var needleColor: Color {
        let value = descriptor.needle.normalizedValue
        if value >= descriptor.warningThreshold {
            return Color(red: 1.0, green: 0.41, blue: 0.36)
        }
        if value >= descriptor.cautionThreshold {
            return Color(red: 1.0, green: 0.82, blue: 0.38)
        }
        return tint
    }
}

private struct ArcTrack: Shape {
    var trimEnd: Double = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.48
        let center = CGPoint(x: rect.midX, y: rect.midY + 2)
        let startAngle = Angle(degrees: -125)
        let endAngle = Angle(degrees: -125 + (250 * max(0, min(1, trimEnd))))
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

private struct SparklineBand: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(size: geometry.size)
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.02))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func normalizedPoints(size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let step = size.width / CGFloat(max(1, values.count - 1))
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (CGFloat(max(0, min(1, value))) * size.height)
            )
        }
    }
}
