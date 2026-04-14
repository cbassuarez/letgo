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

    private var hud: VufineHUDSnapshot {
        model.vufineHUDSnapshot
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

    var body: some View {
        ZStack {
            LowLatencyPlayerLayerView(player: model.previewPlayer, gravity: .resizeAspectFill)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                topBar
                hudOverlay
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if !model.generatedLine.isEmpty {
                VStack {
                    Spacer()
                    Text(model.generatedLine)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(16)
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

    private var hudOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            safetyStrip
            modeStrip
            proposalStrip

            HStack(alignment: .top, spacing: 10) {
                dynamicControlCluster
                actionFeedPanel
            }

            systemHealthStrip
        }
        .padding(10)
        .background(Color.black.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        )
    }

    private var safetyStrip: some View {
        HStack(spacing: 6) {
            Text(displayCoordinator.route.summary)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.cyan.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            ForEach(hud.safetyTokens) { token in
                tokenChip(token)
            }
            Spacer(minLength: 0)
        }
    }

    private var modeStrip: some View {
        HStack(spacing: 6) {
            ForEach(hud.modeTokens) { token in
                tokenChip(token)
            }
            Spacer(minLength: 0)
            Text(hud.transportLine)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)
        }
    }

    private var dynamicControlCluster: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            ForEach(hud.dynamicGauges) { gauge in
                HUDNeedleGaugeView(descriptor: gauge)
                    .frame(minWidth: 118)
            }
        }
        .frame(maxWidth: 760)
    }

    @ViewBuilder
    private var proposalStrip: some View {
        if let proposal = hud.proposalWidget {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ML COPILOT · \(proposal.laneLabel) · CONF \(proposal.confidenceText)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.cyan.opacity(0.92))
                    Text(proposal.rationale)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                    Text(proposal.expectedEffect)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("T-\(proposal.countdownText)s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text(proposal.acceptHint)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.cyan.opacity(0.25), lineWidth: 0.8)
            )
        } else {
            HStack(spacing: 8) {
                Text("ML COPILOT")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.62))
                Text("NO ACTIVE PROPOSAL")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer(minLength: 0)
                Text("JOY_1 READY")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.52))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var actionFeedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTION FEED · RAW / MAPPED / APPLIED")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(Color.white.opacity(0.55))

            ForEach(hud.actionFeed.prefix(18)) { event in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(shortTimestamp(event.timestamp))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .frame(width: 60, alignment: .leading)

                    Text(event.severity.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(severityColor(event.severity))
                        .frame(width: 44, alignment: .leading)

                    Text(event.stage.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .frame(width: 60, alignment: .leading)

                    Text(event.controlID)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .frame(width: 96, alignment: .leading)

                    Text(event.blockReason ?? event.semanticAction ?? event.detail ?? event.outcome)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(8)
        .frame(minWidth: 420, maxWidth: 460, alignment: .topLeading)
        .background(Color.black.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
        )
    }

    private var systemHealthStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hud.stateLine)
            Text(hud.linkLine)
            ForEach(hud.systemHealthLines, id: \.self) { line in
                Text(line)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.7))
        .lineLimit(1)
    }

    private func tokenChip(_ token: HUDStatusToken) -> some View {
        HStack(spacing: 5) {
            Text(token.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.65))
            Text(token.value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(tokenColor(token.level))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func tokenColor(_ level: HUDStatusTokenLevel) -> Color {
        switch level {
        case .nominal:
            return Color.white.opacity(0.08)
        case .caution:
            return Color.orange.opacity(0.24)
        case .critical:
            return Color.red.opacity(0.28)
        case .accent:
            return Color.cyan.opacity(0.2)
        }
    }

    private func severityColor(_ severity: HUDEventSeverity) -> Color {
        switch severity {
        case .info:
            return Color.white.opacity(0.7)
        case .act:
            return Color(red: 0.35, green: 0.89, blue: 1.0)
        case .apply:
            return Color(red: 0.45, green: 1.0, blue: 0.52)
        case .block:
            return Color(red: 1.0, green: 0.80, blue: 0.3)
        case .error:
            return Color(red: 1.0, green: 0.38, blue: 0.38)
        }
    }

    private func shortTimestamp(_ timestamp: TimeInterval) -> String {
        Date(timeIntervalSince1970: timestamp)
            .formatted(date: .omitted, time: .standard)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("Vufine Realtime")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))

            Spacer(minLength: 0)

            Button("INSPECTOR") {
                inspectorPresentation.present(from: .vufine)
            }
            .buttonStyle(.borderedProminent)

            Button("SAFETY") {
                openWindow(id: AppWindowID.safetyMonitor.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)

            Button("MAC ONLY") {
                apply(performanceMode.transitionToLayout(.safetyOnly))
            }
            .buttonStyle(.bordered)

            Button("CONSOLE") {
                openWindow(id: AppWindowID.fullConsole.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)

            Menu("MENU") {
                Button("Open Inspector") {
                    inspectorPresentation.present(from: .vufine)
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
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        )
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
