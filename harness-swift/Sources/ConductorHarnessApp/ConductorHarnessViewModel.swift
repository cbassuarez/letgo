import AppKit
import AVFoundation
import ConductorCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum FlightOutputMode: String, CaseIterable, Identifiable {
    case off
    case `static`
    case dynamic

    var id: String { rawValue }

    var uiLabel: String {
        switch self {
        case .off:
            return "inter"
        case .static:
            return "static"
        case .dynamic:
            return "dynamic"
        }
    }
}

enum EffectiveOutputMode: String {
    case `static`
    case dynamic
    case interstitial
    case off

    var uiLabel: String {
        switch self {
        case .interstitial, .off:
            return "inter"
        case .static:
            return "static"
        case .dynamic:
            return "dynamic"
        }
    }
}

struct ShowFixedLane: Identifiable, Equatable {
    let id: String
    let label: String
    let mediaURL: URL
}

struct TransportLaneDescriptor: Identifiable, Equatable {
    let id: String
    let label: String
    let canArm: Bool
    let isArmed: Bool
    let isActive: Bool
}

enum MasterArmKeyState {
    case safe
    case armed
}

enum PhoneAudioTargetMode: String, CaseIterable, Identifiable {
    case rotating
    case single
    case subset

    var id: String { rawValue }
}

private struct MediaManifest: Codable {
    var sceneMedia: [String: String]
    var interstitialMedia: String?
    var fixedLanes: [FixedLaneEntry]
    var synthPresetPack: String?
    var samplePackManifest: String?
    var choirProfile: String?

    struct FixedLaneEntry: Codable {
        let id: String
        let label: String
        let path: String
    }

    static let fileName = "conductor_media.json"

    static func preferredFileURL() -> URL {
        if let explicitPath = ProcessInfo.processInfo.environment["CONDUCTOR_MEDIA_MANIFEST_PATH"],
           !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: explicitPath)
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("ConductorHarness", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func candidateFileURLs() -> [URL] {
        var urls: [URL] = [preferredFileURL()]

        let fm = FileManager.default
        let cwdURL = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(fileName)
        urls.append(cwdURL)

        let env = ProcessInfo.processInfo.environment
        let candidateEnvKeys = ["CONDUCTOR_MEDIA_MANIFEST_PATH", "SRCROOT", "PROJECT_DIR", "PWD"]
        for key in candidateEnvKeys {
            guard let value = env[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let candidate: URL
            if key == "CONDUCTOR_MEDIA_MANIFEST_PATH" || value.hasSuffix(".json") {
                candidate = URL(fileURLWithPath: value)
            } else {
                candidate = URL(fileURLWithPath: value).appendingPathComponent(fileName)
            }
            urls.append(candidate)
        }

        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            if seen.contains(path) {
                return false
            }
            seen.insert(path)
            return true
        }
    }
}

private enum BackendEndpoints {
    static let host: String = {
        if let envHost = ProcessInfo.processInfo.environment["CONDUCTOR_BACKEND_HOST"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envHost.isEmpty {
            return envHost
        }
        return "letgo-fe0a.onrender.com"
    }()
    static let healthURL = URL(string: "https://\(host)/health")!
    static let harnessWebSocketURL = URL(string: "wss://\(host)/ws/harness")!
    static let deviceWebSocketBase = "wss://\(host)/ws/device"
}

private struct SamplePackManifest: Codable {
    struct SampleEntry: Codable {
        let id: String
        let path: String
    }

    let samples: [SampleEntry]
}

private struct OutputProfile {
    let mode: EffectiveOutputMode
    let showFixed: Bool
    let showDynamic: Bool
    let loopsIndefinitely: Bool
    let usesInterstitialMedia: Bool
    let showFixedLaneId: String?

    var payload: [String: String] {
        var payload: [String: String] = [
            "showFixed": showFixed ? "true" : "false",
            "showDynamic": showDynamic ? "true" : "false",
            "outputMode": mode.rawValue,
            "outputLoop": loopsIndefinitely ? "true" : "false",
            "interstitialActive": usesInterstitialMedia ? "true" : "false"
        ]
        if let showFixedLaneId {
            payload["showFixedLaneId"] = showFixedLaneId
        }
        return payload
    }
}

private struct TimelineStepPlan {
    let laneId: String
    let targetState: ShowState
    let completionState: ShowState
}

@MainActor
final class ConductorHarnessViewModel: ObservableObject {
    private static let inboundKindsHandledOnMain: [String] = [
        "\"kind\":\"error\"",
        "\"kind\":\"phone_audio_pool_state\"",
        "\"kind\":\"phone_audio_ack\"",
        "\"kind\":\"audio_features\"",
        "\"kind\":\"show_snapshot\""
    ]

    @Published var state: ShowState = .idle
    @Published var vector: ParamVector = .neutral
    @Published var latestCue: CueCommand?
    @Published var generatedLine: String = ""
    @Published var devices: [DeviceTelemetry] = []
    @Published var connectionStatus: String = "Disconnected"
    @Published private(set) var linkState: WebSocketConductorClient.LinkState = .idle
    @Published private(set) var retryInSeconds: Int?
    @Published private(set) var lastLinkError: String?
    @Published private(set) var lastHandshakeAt: Date?

    @Published var modelHealthLevel: ModelHealthLevel = .unavailable
    @Published var modelHealthSummary: String = "No CoreML model loaded"
    @Published var modelChecks: [ModelHealthCheck] = []
    @Published var modelRuntimeFailures: Int = 0
    @Published var modelCandidates: [CompiledModelCandidate] = []
    @Published var selectedModelCandidateID: String = ""

    @Published var previewScene: ShowState = .idle
    @Published var previewStatus: String = "No preview media loaded"
    @Published var sceneMediaURLs: [ShowState: URL] = [:]
    @Published var interstitialMediaURL: URL?
    @Published var showFixedLanes: [ShowFixedLane] = []

    @Published var committedOutputMode: FlightOutputMode = .off
    @Published var effectiveOutputMode: EffectiveOutputMode = .off
    @Published var activeStaticLaneId: String?
    @Published var engineRunning = false
    @Published private(set) var quadRouteChannelCount = 0
    @Published private(set) var quadRouteReady = false
    @Published private(set) var latestAudioFeatures: QuadAudioFeatures = .zero

    @Published private(set) var phoneAudioGateArmed = false
    @Published private(set) var phoneAudioGateCommitted = false
    @Published private(set) var phoneAudioAvailableDevices: [String] = []
    @Published private(set) var phoneAudioActiveVoices: [String: Int] = [:]
    @Published var phoneAudioTargetMode: PhoneAudioTargetMode = .rotating
    @Published var phoneAudioSingleTargetID: String = ""
    @Published var phoneAudioSubsetTargetIDs: Set<String> = []

    @Published var synthPresetPackURL: URL?
    @Published var samplePackManifestURL: URL?
    @Published var choirProfileURL: URL?
    @Published private(set) var samplePackEntries: [String: URL] = [:]
    @Published var selectedSampleID: String = "default"
    @Published var choirNote: Int = 60

    @Published var pendingOutputMode: FlightOutputMode?
    @Published var pendingLaneId: String?
    @Published var isLatchArmed = false
    @Published var canFireGO = false
    @Published var latchSummary: String = "DISARMED"
    @Published var latchCountdownSeconds: Double?
    @Published var latchExpiresAt: Date?
    @Published var statusLineEvent = StatusLineEvent(
        message: "Latch disarmed",
        severity: .info,
        timestamp: Date()
    )
    @Published private(set) var statusLineHistory: [StatusLineEvent] = []
    @Published var masterArmKey: MasterArmKeyState = .safe
    @Published private(set) var abortCoverOpen: Bool = false
    @Published private(set) var lockedTimelineLaneIDs: Set<String> = []

    private static let statusHistoryLimit = 200
    private var abortCoverTimer: Timer?

    let previewPlayer = AVPlayer()

    var scriptBank: [ScriptCandidate] = [
        ScriptCandidate(
            id: "line-1",
            arc: .arc1,
            tags: ["arrival", "confession"],
            text: "I practiced being unshakable until the room shook first.",
            weight: 0.8,
            cooldown: 12,
            tone: "confessional"
        ),
        ScriptCandidate(
            id: "line-2",
            arc: .arc2,
            tags: ["control", "breath"],
            text: "Control was not power. It was timing and listening.",
            weight: 0.7,
            cooldown: 10,
            tone: "directive"
        ),
        ScriptCandidate(
            id: "line-3",
            arc: .arc3,
            tags: ["release", "choir"],
            text: "When we let go together, the whole venue changed key.",
            weight: 0.9,
            cooldown: 15,
            tone: "lyrical"
        )
    ]

    private let machine = ShowStateMachine()
    private let scoringModel: CoreMLScoringModelAdapter
    private let textEngine: TextSelectionEngine
    private let telemetry = TelemetryHub()
    private let replay = ReplayRecorder()
    private let websocket = WebSocketConductorClient()
    private let quadAudioEngine = QuadAudioEngine()

    private var importedModelCandidates: [CompiledModelCandidate] = []
    private var previewLoopObserver: NSObjectProtocol?
    private var latchController = OutputLatchController(timeoutSeconds: 8)
    private var latchTimer: Timer?
    private var audioFeaturePumpTimer: Timer?
    private var latestAudioFeaturesRaw: QuadAudioFeatures = .zero
    private var lastAudioFeaturesUIPublishAt: CFAbsoluteTime = 0
    private var lastAudioFeaturesSent: QuadAudioFeatures = .zero
    private var lastAudioFeaturesSentAt: CFAbsoluteTime = 0
    private var mediaDurationCache: [String: TimeInterval] = [:]
    private var mediaDurationTaskCache: [String: Task<TimeInterval?, Never>] = [:]
    private var showFixedCounter = 0
    private var sequenceWorkItems: [DispatchWorkItem] = []
    private var phoneCommandSequence = 0
    private var lastLatchStatus: StatusLineEvent?

    private let privilegedLaneStateMap: [String: ShowState] = [
        "preshow": .preshow,
        "introduction": .introduction,
        "ending": .ending
    ]
    private let timelineStepPlans: [String: TimelineStepPlan] = [
        "preshow": TimelineStepPlan(
            laneId: "preshow",
            targetState: .preshow,
            completionState: .preshow
        ),
        "introduction": TimelineStepPlan(
            laneId: "introduction",
            targetState: .introduction,
            completionState: .main
        ),
        "ending": TimelineStepPlan(
            laneId: "ending",
            targetState: .ending,
            completionState: .idle
        )
    ]

    private static let statusTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var fixedHarnessLinkURL: String {
        BackendEndpoints.harnessWebSocketURL.absoluteString
    }

    var fixedHealthURL: String {
        BackendEndpoints.healthURL.absoluteString
    }

    var isLinkHealthy: Bool {
        linkState == .online
    }

    init() {
        let preferredModelName = ProcessInfo.processInfo.environment["CONDUCTOR_COREML_MODEL_NAME"]
        let scoringModel = CoreMLScoringModelAdapter(preferredModelName: preferredModelName)
        self.scoringModel = scoringModel
        self.textEngine = TextSelectionEngine(model: scoringModel)

        websocket.onMessage = { [weak self] text in
            guard Self.shouldHandleBackendMessage(text) else { return }
            MainActor.assumeIsolated {
                self?.handleBackendMessage(text)
            }
        }
        websocket.onStateChange = { [weak self] nextState in
            MainActor.assumeIsolated {
                self?.linkState = nextState
                self?.connectionStatus = Self.connectionStatusText(for: nextState)
            }
        }
        websocket.onOpen = { [weak self] in
            MainActor.assumeIsolated {
                self?.publishPhoneAudioPoolState()
                self?.publishLatestAudioFeatures()
                self?.pushStatus(StatusLineEvent(
                    message: "WS link online",
                    severity: .success,
                    timestamp: Date()
                ))
            }
        }
        websocket.onClose = { [weak self] code, reason in
            MainActor.assumeIsolated {
                let suffix = reason.map { ": \($0)" } ?? ""
                self?.pushStatus(StatusLineEvent(
                    message: "WS link closed (\(code))\(suffix)",
                    severity: .warn,
                    timestamp: Date()
                ))
            }
        }
        websocket.onRetryScheduled = { [weak self] delay in
            MainActor.assumeIsolated {
                self?.pushStatus(StatusLineEvent(
                    message: "WS retry scheduled in \(Int(ceil(delay)))s",
                    severity: .info,
                    timestamp: Date()
                ))
            }
        }
        websocket.onError = { [weak self] message in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastLinkError = message
                self.pushStatus(StatusLineEvent(
                    message: "WS link error: \(message)",
                    severity: .warn,
                    timestamp: Date()
                ))
            }
        }
        websocket.onDiagnostics = { [weak self] diagnostics in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.retryInSeconds != diagnostics.retryInSeconds {
                    self.retryInSeconds = diagnostics.retryInSeconds
                }
                if self.lastHandshakeAt != diagnostics.lastHandshakeAt {
                    self.lastHandshakeAt = diagnostics.lastHandshakeAt
                }
                if self.lastLinkError != diagnostics.lastError {
                    self.lastLinkError = diagnostics.lastError
                }
            }
        }

        quadAudioEngine.onFeatures = { [weak self] features in
            DispatchQueue.main.async {
                self?.ingestAudioFeatures(features)
            }
        }

        refreshModelCatalog()
        applyModelHealth(scoringModel.currentHealth())
        syncLatchState(latchController.snapshot, now: Date())
        startLatchTimer()
        refreshQuadRouteStatus()
        loadMediaManifest()
        websocket.start(url: BackendEndpoints.harnessWebSocketURL)
    }

    deinit {
        if let observer = previewLoopObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        latchTimer?.invalidate()
        audioFeaturePumpTimer?.invalidate()
        abortCoverTimer?.invalidate()
        quadAudioEngine.stop()
        websocket.stop()
    }

    // MARK: - Status helpers

    /// Single funnel for every status line update. Mirrors the latest event
    /// into `statusLineEvent` (the existing API the UI binds to) and appends
    /// to the bounded `statusLineHistory` ring buffer that feeds the flight
    /// log. Consecutive identical messages are deduped so the latch tick
    /// (which fires every 0.2s) doesn't flood the tape.
    private func pushStatus(_ event: StatusLineEvent) {
        if statusLineEvent.message == event.message,
           statusLineEvent.severity == event.severity {
            return
        }
        statusLineEvent = event
        if let last = statusLineHistory.last,
           last.message == event.message,
           last.severity == event.severity {
            return
        }
        statusLineHistory.append(event)
        if statusLineHistory.count > Self.statusHistoryLimit {
            statusLineHistory.removeFirst(statusLineHistory.count - Self.statusHistoryLimit)
        }
    }

    private static func shouldHandleBackendMessage(_ text: String) -> Bool {
        inboundKindsHandledOnMain.contains(where: { text.contains($0) })
    }

    // MARK: - Master arm key

    func toggleMasterArmKey() {
        masterArmKey = (masterArmKey == .safe) ? .armed : .safe
        let now = Date()
        if masterArmKey == .armed {
            pushStatus(StatusLineEvent(
                message: "Master arm key turned to ARM",
                severity: .warn,
                timestamp: now
            ))
        } else {
            pushStatus(StatusLineEvent(
                message: "Master arm key returned to SAFE",
                severity: .info,
                timestamp: now
            ))
        }
    }

    var canFireWithMasterArm: Bool {
        canFireGO && masterArmKey == .armed && isLinkHealthy && quadRouteReady
    }

    // MARK: - Abort safety cover

    /// First click on ABORT lifts the cover and starts a 3s arming window.
    /// If `commitAbort` is not called inside that window the cover slams
    /// shut on its own.
    func openAbortCover() {
        guard !abortCoverOpen else { return }
        abortCoverOpen = true
        pushStatus(StatusLineEvent(
            message: "ABORT cover lifted — confirm within 3s",
            severity: .warn,
            timestamp: Date()
        ))

        abortCoverTimer?.invalidate()
        let timer = Timer(timeInterval: 3.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.expireAbortCover()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        abortCoverTimer = timer
    }

    func cancelAbortCover() {
        guard abortCoverOpen else { return }
        abortCoverTimer?.invalidate()
        abortCoverTimer = nil
        abortCoverOpen = false
        pushStatus(StatusLineEvent(
            message: "ABORT cover closed",
            severity: .info,
            timestamp: Date()
        ))
    }

    private func expireAbortCover() {
        guard abortCoverOpen else { return }
        abortCoverTimer?.invalidate()
        abortCoverTimer = nil
        abortCoverOpen = false
        pushStatus(StatusLineEvent(
            message: "ABORT cover auto-closed",
            severity: .info,
            timestamp: Date()
        ))
    }

    /// Commits the abort, but only if the cover is currently open.
    func commitAbort() {
        guard abortCoverOpen else { return }
        abortCoverTimer?.invalidate()
        abortCoverTimer = nil
        abortCoverOpen = false
        guard canApply(action: .abort) else {
            pushStatus(StatusLineEvent(
                message: "ABORT blocked: invalid state transition",
                severity: .error,
                timestamp: Date()
            ))
            return
        }
        pushStatus(StatusLineEvent(
            message: "ABORT committed",
            severity: .error,
            timestamp: Date()
        ))
        apply(action: .abort)
    }

    var statusLineTimestamp: String {
        Self.statusTimeFormatter.string(from: statusLineEvent.timestamp)
    }

    var transportLaneDescriptors: [TransportLaneDescriptor] {
        showFixedLanes.map { lane in
            TransportLaneDescriptor(
                id: lane.id,
                label: lane.label,
                canArm: true,
                isArmed: pendingLaneId == lane.id,
                isActive: activeStaticLaneId == lane.id
            )
        }
    }

    func canApply(action: CueAction, target: ShowState? = nil) -> Bool {
        machine.canApply(action: action, targetState: target)
    }

    func isTimelineStepLocked(_ laneId: String) -> Bool {
        lockedTimelineLaneIDs.contains(laneId)
    }

    func isTimelineStepArmed(_ laneId: String) -> Bool {
        pendingOutputMode == .static && pendingLaneId == laneId
    }

    private static func connectionStatusText(for state: WebSocketConductorClient.LinkState) -> String {
        switch state {
        case .idle:
            return "Idle"
        case .connecting:
            return "Connecting"
        case .online:
            return "Connected"
        case .degraded:
            return "Connected (Degraded)"
        case .offline:
            return "Offline"
        case .backoff:
            return "Retry Backoff"
        }
    }

    private func guardLinkHealthy(for actionLabel: String) -> Bool {
        guard isLinkHealthy else {
            pushStatus(StatusLineEvent(
                message: "Blocked: \(actionLabel) requires WS LINK ONLINE",
                severity: .warn,
                timestamp: Date()
            ))
            return false
        }
        return true
    }

    func apply(
        action: CueAction,
        target: ShowState? = nil,
        extraPayload: [String: String] = [:],
        overrideStaticLaneId: String? = nil,
        staticAutoReturnTarget: ShowState? = nil
    ) {
        if action == .hold || action == .abort {
            cancelSequenceWork()
        }

        do {
            let previousState = state
            let baseCue = try machine.apply(action: action, targetState: target)
            let outputProfile = resolveOutputProfile(
                for: baseCue.showState,
                overrideStaticLaneId: overrideStaticLaneId
            )
            effectiveOutputMode = outputProfile.mode

            var cuePayload = baseCue.payload
            cuePayload.merge(outputProfile.payload) { _, new in new }
            cuePayload.merge(extraPayload) { _, new in new }
            cuePayload["engineRunning"] = engineRunning ? "true" : "false"

            let cue = CueCommand(
                cueId: baseCue.cueId,
                showState: baseCue.showState,
                logicalTime: baseCue.logicalTime,
                payload: cuePayload,
                version: baseCue.version,
                action: baseCue.action
            )

            latestCue = cue
            state = cue.showState
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.latestCue?.cueId == cue.cueId else { return }
                self.updatePreview(for: cue, outputProfile: outputProfile)
                if outputProfile.mode == .static, outputProfile.showFixed, !outputProfile.loopsIndefinitely {
                    let fallbackState = staticAutoReturnTarget ?? cue.showState
                    self.scheduleStaticAutoReturn(
                        for: cue,
                        targetState: fallbackState,
                        outputProfile: outputProfile
                    )
                }
            }

            Task {
                do {
                    var dispatchPayload = cue.payload
                    dispatchPayload["localCueId"] = cue.cueId
                    dispatchPayload["localLogicalMs"] = String(Int(cue.logicalTime * 1000))
                    dispatchPayload["localState"] = cue.showState.rawValue

                    try await websocket.sendCommand(
                        action,
                        targetState: cue.showState,
                        payload: dispatchPayload
                    )
                } catch {
                    await MainActor.run {
                        self.lastLinkError = error.localizedDescription
                        self.pushStatus(StatusLineEvent(
                            message: "Command dispatch failed: \(error.localizedDescription)",
                            severity: .error,
                            timestamp: Date()
                        ))
                    }
                }

                await replay.append(
                    ReplayEvent(
                        kind: .cue,
                        timestamp: Date(),
                        logicalTime: cue.logicalTime,
                        payload: [
                            "cueId": cue.cueId,
                            "state": cue.showState.rawValue,
                            "action": action.rawValue,
                            "dispatch": "command",
                            "outputMode": outputProfile.mode.rawValue,
                            "showFixedLaneId": outputProfile.showFixedLaneId ?? "none"
                        ]
                    )
                )
            }

            Task {
                if cue.showState == .main, previousState != .main {
                    let decision = await textEngine.select(
                        from: scriptBank,
                        cueId: cue.cueId,
                        arc: .arc2,
                        vector: vector
                    )
                    await MainActor.run {
                        self.generatedLine = decision.text ?? ""
                        self.applyModelHealth(self.scoringModel.currentHealth())
                    }
                    await replay.append(
                        ReplayEvent(
                            kind: .selection,
                            timestamp: Date(),
                            logicalTime: cue.logicalTime,
                            payload: [
                                "selectedId": decision.selectedId ?? "none",
                                "reason": decision.reason
                            ]
                        )
                    )
                }
            }
        } catch {
            pushStatus(StatusLineEvent(
                message: "Transition error: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
        }
    }

    func patchVector(_ patch: ParamVectorPatch) {
        vector = machine.updateVector(with: patch)

        Task {
            do {
                try await websocket.sendVector(vector)
            } catch {
                await MainActor.run {
                    self.lastLinkError = error.localizedDescription
                    self.pushStatus(StatusLineEvent(
                        message: "Vector dispatch failed: \(error.localizedDescription)",
                        severity: .error,
                        timestamp: Date()
                    ))
                }
            }

            await replay.append(
                ReplayEvent(
                    kind: .telemetry,
                    timestamp: Date(),
                    logicalTime: machine.logicalTime(),
                    payload: [
                        "textAmount": String(vector.textAmount),
                        "compositeBias": String(vector.compositeBias),
                        "audioGain": String(vector.audioGain)
                    ]
                )
            )
        }
    }

    func refreshTelemetry() {
        Task {
            let snapshot = await telemetry.allDevices()
            await MainActor.run {
                self.devices = snapshot
            }
        }
    }

    func freezeFrame() {
        Task {
            let events = await replay.freezeFrame(center: Date())
            await MainActor.run {
                self.pushStatus(StatusLineEvent(
                    message: "Freeze captured: \(events.count) events",
                    severity: .info,
                    timestamp: Date()
                ))
            }
        }
    }

    func armOutputMode(_ mode: FlightOutputMode) {
        let snapshot = latchController.armMode(mode.rawValue, now: Date())
        syncLatchState(snapshot, now: Date())
    }

    func armTransportLane(_ laneId: String) {
        let snapshot = latchController.armLane(laneId, now: Date())
        syncLatchState(snapshot, now: Date())
    }

    func fireOutputGO() {
        guard guardLinkHealthy(for: "GO") else {
            return
        }

        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "Blocked: start engine first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        guard quadRouteReady else {
            pushStatus(StatusLineEvent(
                message: "GO blocked: quad route requires >=4 output channels",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let now = Date()
        let fireDecision = latchController.fire(now: now)
        syncLatchState(latchController.snapshot, now: now)

        guard let fireDecision else {
            return
        }

        guard let mode = FlightOutputMode(rawValue: fireDecision.mode) else {
            pushStatus(StatusLineEvent(
                message: "GO failed: unsupported mode",
                severity: .error,
                timestamp: Date()
            ))
            return
        }

        committedOutputMode = mode
        if mode == .static {
            activeStaticLaneId = fireDecision.laneId
        } else {
            activeStaticLaneId = nil
        }

        var payload: [String: String] = [
            "latchId": fireDecision.latchId
        ]
        if let laneId = fireDecision.laneId {
            payload["showFixedLaneId"] = laneId
        }

        if mode == .static, let laneId = fireDecision.laneId {
            if let timelinePlan = timelineStepPlan(for: laneId) {
                guard !lockedTimelineLaneIDs.contains(laneId) else {
                    pushStatus(StatusLineEvent(
                        message: "GO blocked: timeline \(laneId.uppercased()) is locked",
                        severity: .warn,
                        timestamp: Date()
                    ))
                    return
                }

                guard canApply(action: .jump, target: timelinePlan.targetState) else {
                    pushStatus(StatusLineEvent(
                        message: "GO blocked: timeline \(laneId.uppercased()) is NOGO from \(state.rawValue.uppercased())",
                        severity: .warn,
                        timestamp: Date()
                    ))
                    return
                }

                lockedTimelineLaneIDs.insert(laneId)
                payload["sequence"] = "timeline"
                payload["sequenceStep"] = laneId

                apply(
                    action: .jump,
                    target: timelinePlan.targetState,
                    extraPayload: payload,
                    overrideStaticLaneId: laneId,
                    staticAutoReturnTarget: timelinePlan.completionState
                )
                return
            }

            guard let target = laneTargetState(for: laneId) else {
                pushStatus(StatusLineEvent(
                    message: "GO failed: lane target missing",
                    severity: .error,
                    timestamp: Date()
                ))
                return
            }

            apply(
                action: .jump,
                target: target,
                extraPayload: payload,
                overrideStaticLaneId: laneId,
                staticAutoReturnTarget: target
            )
            return
        }

        apply(action: .jump, target: state, extraPayload: payload)
    }

    func startEngine() {
        guard guardLinkHealthy(for: "ENGINE START") else {
            return
        }

        guard !engineRunning else {
            pushStatus(StatusLineEvent(
                message: "Engine already running",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        cancelSequenceWork()
        engineRunning = true
        do {
            let route = try quadAudioEngine.start()
            quadRouteChannelCount = route.channelCount
            quadRouteReady = route.quadReady
            if route.quadReady {
                pushStatus(StatusLineEvent(
                    message: "Quad route ready (\(route.channelCount)ch)",
                    severity: .success,
                    timestamp: Date()
                ))
            } else {
                pushStatus(StatusLineEvent(
                    message: "Quad route NOGO (\(route.channelCount)ch). Requires >=4ch for GO",
                    severity: .warn,
                    timestamp: Date()
                ))
            }
        } catch {
            quadRouteReady = false
            quadRouteChannelCount = 0
            pushStatus(StatusLineEvent(
                message: "Audio engine failed to start: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
        }

        phoneAudioGateArmed = false
        phoneAudioGateCommitted = false
        publishPhoneAudioPoolState()
        startAudioFeaturePump()

        committedOutputMode = .off
        effectiveOutputMode = .interstitial
        activeStaticLaneId = nil
        previewStatus = "Output INTER"
        let now = Date()
        let snapshot = latchController.reset(now: now, message: "Engine started")
        syncLatchState(snapshot, now: now)

        apply(
            action: .jump,
            target: state,
            extraPayload: [
                "sequence": "engine",
                "sequenceStep": "start"
            ]
        )
    }

    func stopEngine() {
        guard guardLinkHealthy(for: "ENGINE STOP") else {
            return
        }

        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "Engine already stopped",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        cancelSequenceWork()
        engineRunning = false
        quadAudioEngine.stop()
        stopAudioFeaturePump()
        quadRouteReady = false
        quadRouteChannelCount = 0
        phoneAudioGateArmed = false
        phoneAudioGateCommitted = false
        publishPhoneAudioPoolState()
        ingestAudioFeatures(.zero, forceUI: true)
        publishLatestAudioFeatures(forceZero: true)
        committedOutputMode = .off
        activeStaticLaneId = nil
        let now = Date()
        let snapshot = latchController.reset(now: now, message: "Engine stopped")
        syncLatchState(snapshot, now: now)

        apply(
            action: .jump,
            target: state,
            extraPayload: [
                "sequence": "engine",
                "sequenceStep": "stop"
            ]
        )
    }

    func runPreshowTimelineStep() {
        queueTimelineStep(laneId: "preshow")
    }

    func runIntroductionTimelineStep() {
        queueTimelineStep(laneId: "introduction")
    }

    func runEndingTimelineStep() {
        queueTimelineStep(laneId: "ending")
    }

    private func queueTimelineStep(laneId: String) {
        guard guardLinkHealthy(for: "TIMELINE STEP") else {
            return
        }

        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "Blocked: start engine first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        guard let plan = timelineStepPlan(for: laneId) else {
            pushStatus(StatusLineEvent(
                message: "Blocked: unknown timeline step \(laneId)",
                severity: .error,
                timestamp: Date()
            ))
            return
        }

        guard !lockedTimelineLaneIDs.contains(plan.laneId) else {
            pushStatus(StatusLineEvent(
                message: "Blocked: \(plan.laneId.uppercased()) already used and locked",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        guard laneMediaURL(for: plan.laneId) != nil else {
            pushStatus(StatusLineEvent(
                message: "Blocked: load media for \(plan.laneId.uppercased()) first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        guard canApply(action: .jump, target: plan.targetState) else {
            pushStatus(StatusLineEvent(
                message: "Blocked: \(plan.laneId.uppercased()) is NOGO from \(state.rawValue.uppercased())",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let now = Date()
        _ = latchController.armMode(FlightOutputMode.static.rawValue, now: now)
        let snapshot = latchController.armLane(plan.laneId, now: now)
        syncLatchState(snapshot, now: now)
        pushStatus(StatusLineEvent(
            message: "\(plan.laneId.uppercased()) queued — TAKE/GO to commit",
            severity: .info,
            timestamp: now
        ))
    }

    func resetShowRun() {
        cancelSequenceWork()
        engineRunning = false
        quadAudioEngine.stop()
        stopAudioFeaturePump()
        quadRouteReady = false
        quadRouteChannelCount = 0
        phoneAudioGateArmed = false
        phoneAudioGateCommitted = false
        publishPhoneAudioPoolState()
        ingestAudioFeatures(.zero, forceUI: true)
        publishLatestAudioFeatures(forceZero: true)
        committedOutputMode = .off
        activeStaticLaneId = nil
        effectiveOutputMode = .off
        let now = Date()
        let snapshot = latchController.reset(now: now, message: "Show reset")
        syncLatchState(snapshot, now: now)
        apply(
            action: .jump,
            target: .idle,
            extraPayload: [
                "sequence": "reset",
                "sequenceStep": "idle"
            ]
        )
    }

    func refreshQuadRouteStatus() {
        let status = quadAudioEngine.routeStatus()
        quadRouteChannelCount = status.channelCount
        quadRouteReady = status.quadReady
        publishPhoneAudioPoolState()
    }

    func takePhoneAudioGate() {
        guard guardLinkHealthy(for: "PHONE AUDIO TAKE") else {
            return
        }
        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "PHONE AUDIO TAKE blocked: start engine first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }
        phoneAudioGateArmed = true
        phoneAudioGateCommitted = false
        publishPhoneAudioPoolState()
        pushStatus(StatusLineEvent(
            message: "PHONE AUDIO gate armed (TAKE)",
            severity: .info,
            timestamp: Date()
        ))
    }

    func goPhoneAudioGate() {
        guard guardLinkHealthy(for: "PHONE AUDIO GO") else {
            return
        }
        guard phoneAudioGateArmed else {
            pushStatus(StatusLineEvent(
                message: "PHONE AUDIO GO blocked: TAKE first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }
        guard quadRouteReady else {
            pushStatus(StatusLineEvent(
                message: "PHONE AUDIO GO blocked: quad route requires >=4ch",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }
        phoneAudioGateCommitted = true
        publishPhoneAudioPoolState()
        pushStatus(StatusLineEvent(
            message: "PHONE AUDIO gate committed (GO)",
            severity: .success,
            timestamp: Date()
        ))
    }

    func safePhoneAudioGate() {
        phoneAudioGateArmed = false
        phoneAudioGateCommitted = false
        publishPhoneAudioPoolState()
        pushStatus(StatusLineEvent(
            message: "PHONE AUDIO gate returned SAFE",
            severity: .info,
            timestamp: Date()
        ))
    }

    func triggerSynthNoteOn() {
        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "SYNTH blocked: engine is stopped",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }
        quadAudioEngine.playSynthNote(note: choirNote, velocity: 0.82, gain: 0.30)
        pushStatus(StatusLineEvent(
            message: "SYNTH note_on \(choirNote)",
            severity: .info,
            timestamp: Date()
        ))
    }

    func triggerSynthNoteOff() {
        quadAudioEngine.stopSynthNote(note: choirNote)
        pushStatus(StatusLineEvent(
            message: "SYNTH note_off \(choirNote)",
            severity: .info,
            timestamp: Date()
        ))
    }

    func triggerSamplePlayback() {
        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "SAMPLE blocked: engine is stopped",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        guard let sampleURL = sampleURLForSelectedID() else {
            pushStatus(StatusLineEvent(
                message: "SAMPLE blocked: load sample pack first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        do {
            try quadAudioEngine.triggerSample(url: sampleURL, gain: 0.34)
            pushStatus(StatusLineEvent(
                message: "SAMPLE triggered: \(sampleURL.lastPathComponent)",
                severity: .info,
                timestamp: Date()
            ))
        } catch {
            pushStatus(StatusLineEvent(
                message: "SAMPLE failed: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
        }
    }

    func triggerPhoneChoirNoteOn() {
        guard guardPhoneAudioDispatchReady(label: "CHOIR NOTE ON") else { return }
        let command = makePhoneCommand(
            kind: .noteOn,
            note: choirNote,
            velocity: 0.84,
            gain: 0.34
        )
        dispatchPhoneAudioCommand(command, label: "CHOIR NOTE ON")
    }

    func triggerPhoneChoirNoteOff() {
        guard guardPhoneAudioDispatchReady(label: "CHOIR NOTE OFF") else { return }
        let command = makePhoneCommand(
            kind: .noteOff,
            note: choirNote
        )
        dispatchPhoneAudioCommand(command, label: "CHOIR NOTE OFF")
    }

    func triggerPhoneAmbientNoise() {
        guard guardPhoneAudioDispatchReady(label: "PHONE AMBIENT") else { return }
        quadAudioEngine.startAmbientNoise(gain: 0.09)
        let command = makePhoneCommand(
            kind: .ambientNoise,
            gain: 0.08,
            seed: Int.random(in: 1 ... Int.max)
        )
        dispatchPhoneAudioCommand(command, label: "PHONE AMBIENT")
    }

    func triggerPhoneSample() {
        guard guardPhoneAudioDispatchReady(label: "PHONE SAMPLE") else { return }
        let sampleID = selectedSampleID
        let command = makePhoneCommand(
            kind: .sampleTrigger,
            sampleId: sampleID,
            gain: 0.34
        )
        dispatchPhoneAudioCommand(command, label: "PHONE SAMPLE")
    }

    func stopAllPhoneAudio() {
        quadAudioEngine.stopAmbientNoise()
        let command = makePhoneCommand(kind: .stopAll)
        dispatchPhoneAudioCommand(command, label: "PHONE STOP ALL")
    }

    private func guardPhoneAudioDispatchReady(label: String) -> Bool {
        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "\(label) blocked: engine is stopped",
                severity: .warn,
                timestamp: Date()
            ))
            return false
        }

        guard phoneAudioGateCommitted else {
            pushStatus(StatusLineEvent(
                message: "\(label) blocked: PHONE AUDIO gate not committed",
                severity: .warn,
                timestamp: Date()
            ))
            return false
        }
        return true
    }

    private func makePhoneCommand(
        kind: PhoneAudioCommandKind,
        note: Int? = nil,
        velocity: Double? = nil,
        sampleId: String? = nil,
        gain: Double? = nil,
        seed: Int? = nil
    ) -> HarnessPhoneAudioCommandPayload {
        phoneCommandSequence += 1
        let issuedAt = Date().timeIntervalSince1970 * 1000
        return HarnessPhoneAudioCommandPayload(
            commandId: "cmd-\(Int(issuedAt))-\(phoneCommandSequence)",
            kind: kind,
            targetHashedIds: resolvedPhoneTargets(),
            note: note,
            velocity: velocity,
            sampleId: sampleId,
            gain: gain,
            seed: seed,
            issuedAt: issuedAt
        )
    }

    private func dispatchPhoneAudioCommand(_ command: HarnessPhoneAudioCommandPayload, label: String) {
        guard phoneAudioGateCommitted else {
            pushStatus(StatusLineEvent(
                message: "\(label) blocked: PHONE AUDIO gate not committed",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }
        guard quadRouteReady else {
            pushStatus(StatusLineEvent(
                message: "\(label) blocked: quad route not ready",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }
        guard guardLinkHealthy(for: label) else {
            return
        }

        Task {
            do {
                try await websocket.sendEnvelope(kind: "phone_audio_command", data: command)
                await MainActor.run {
                    self.pushStatus(StatusLineEvent(
                        message: "\(label) dispatched",
                        severity: .info,
                        timestamp: Date()
                    ))
                }
            } catch {
                await MainActor.run {
                    self.lastLinkError = error.localizedDescription
                    self.pushStatus(StatusLineEvent(
                        message: "\(label) dispatch failed: \(error.localizedDescription)",
                        severity: .error,
                        timestamp: Date()
                    ))
                }
            }
        }
    }

    private func ingestAudioFeatures(_ features: QuadAudioFeatures, forceUI: Bool = false) {
        latestAudioFeaturesRaw = features
        let now = CFAbsoluteTimeGetCurrent()
        let minPublishInterval: CFAbsoluteTime = 0.12
        let previous = latestAudioFeatures
        let changedEnough =
            abs(previous.rms - features.rms) > 0.02 ||
            abs(previous.spectralCentroid - features.spectralCentroid) > 0.03 ||
            abs(previous.flux - features.flux) > 0.03 ||
            abs(previous.transientDensity - features.transientDensity) > 0.03

        guard forceUI || (changedEnough && now - lastAudioFeaturesUIPublishAt >= minPublishInterval) else {
            return
        }

        lastAudioFeaturesUIPublishAt = now
        latestAudioFeatures = features
    }

    private func startAudioFeaturePump() {
        audioFeaturePumpTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishLatestAudioFeatures()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        audioFeaturePumpTimer = timer
    }

    private func stopAudioFeaturePump() {
        audioFeaturePumpTimer?.invalidate()
        audioFeaturePumpTimer = nil
    }

    private func publishLatestAudioFeatures(forceZero: Bool = false) {
        guard linkState == .online || linkState == .degraded else { return }
        let source = forceZero ? QuadAudioFeatures.zero : latestAudioFeaturesRaw
        let now = CFAbsoluteTimeGetCurrent()

        if !forceZero {
            let changedEnough =
                abs(lastAudioFeaturesSent.rms - source.rms) > 0.02 ||
                abs(lastAudioFeaturesSent.spectralCentroid - source.spectralCentroid) > 0.03 ||
                abs(lastAudioFeaturesSent.flux - source.flux) > 0.03 ||
                abs(lastAudioFeaturesSent.transientDensity - source.transientDensity) > 0.03
            let keepAliveWindow: CFAbsoluteTime = 1.0
            guard changedEnough || (now - lastAudioFeaturesSentAt >= keepAliveWindow) else {
                return
            }
        }

        lastAudioFeaturesSent = source
        lastAudioFeaturesSentAt = now
        let payload = HarnessAudioFeaturePayload(
            rms: source.rms,
            spectralCentroid: source.spectralCentroid,
            flux: source.flux,
            transientDensity: source.transientDensity,
            updatedAt: source.updatedAt
        )
        Task {
            do {
                try await websocket.sendEnvelope(kind: "audio_features", data: payload)
            } catch {
                await MainActor.run {
                    self.lastLinkError = error.localizedDescription
                }
            }
        }
    }

    private func publishPhoneAudioPoolState() {
        guard linkState == .online || linkState == .degraded else { return }
        let payload = HarnessPhoneAudioPoolStatePayload(
            gateArmed: phoneAudioGateArmed,
            gateCommitted: phoneAudioGateCommitted,
            quadRouteReady: quadRouteReady,
            availableDevices: phoneAudioAvailableDevices,
            activeVoices: phoneAudioActiveVoices,
            updatedAt: Date().timeIntervalSince1970 * 1000
        )
        Task {
            do {
                try await websocket.sendEnvelope(kind: "phone_audio_pool_state", data: payload)
            } catch {
                await MainActor.run {
                    self.lastLinkError = error.localizedDescription
                }
            }
        }
    }

    func importSynthPresetPackFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Import Synth Preset Pack"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .data]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        synthPresetPackURL = selectedURL
        saveMediaManifest()
        pushStatus(StatusLineEvent(
            message: "Loaded synth preset pack: \(selectedURL.lastPathComponent)",
            severity: .success,
            timestamp: Date()
        ))
    }

    func importSamplePackManifestFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Import Sample Pack Manifest"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .audio, .movie]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            let entries = try resolveSamplePackEntries(from: selectedURL)
            samplePackManifestURL = selectedURL
            samplePackEntries = entries
            if let firstID = entries.keys.sorted().first {
                selectedSampleID = firstID
            }
            saveMediaManifest()
            pushStatus(StatusLineEvent(
                message: "Loaded sample pack (\(entries.count) entries)",
                severity: .success,
                timestamp: Date()
            ))
        } catch {
            pushStatus(StatusLineEvent(
                message: "Sample pack import failed: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
        }
    }

    func importChoirProfileFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Import Choir Profile"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .text]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        choirProfileURL = selectedURL
        saveMediaManifest()
        pushStatus(StatusLineEvent(
            message: "Loaded choir profile: \(selectedURL.lastPathComponent)",
            severity: .success,
            timestamp: Date()
        ))
    }

    func synthPresetFilename() -> String {
        synthPresetPackURL?.lastPathComponent ?? "none"
    }

    func samplePackFilename() -> String {
        samplePackManifestURL?.lastPathComponent ?? "none"
    }

    func choirProfileFilename() -> String {
        choirProfileURL?.lastPathComponent ?? "none"
    }

    func sampleEntrySummary() -> String {
        if samplePackEntries.isEmpty {
            return "none"
        }
        return "\(samplePackEntries.count) entries"
    }

    func togglePhoneAudioSubsetTarget(_ hashedId: String) {
        if phoneAudioSubsetTargetIDs.contains(hashedId) {
            phoneAudioSubsetTargetIDs.remove(hashedId)
        } else {
            phoneAudioSubsetTargetIDs.insert(hashedId)
        }
    }

    private func sampleURLForSelectedID() -> URL? {
        if let selected = samplePackEntries[selectedSampleID] {
            return selected
        }
        return samplePackEntries.values.first
    }

    private func resolveSamplePackEntries(from selectedURL: URL) throws -> [String: URL] {
        if selectedURL.pathExtension.lowercased() != "json" {
            return ["default": selectedURL]
        }

        let data = try Data(contentsOf: selectedURL)
        let decoder = JSONDecoder()
        if let manifest = try? decoder.decode(SamplePackManifest.self, from: data) {
            return resolveSampleEntries(manifest.samples, baseURL: selectedURL.deletingLastPathComponent())
        }

        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let samples = root["samples"] as? [String: String] {
                return samples.reduce(into: [String: URL]()) { result, entry in
                    let url = resolveMediaURL(path: entry.value, baseURL: selectedURL.deletingLastPathComponent())
                    if FileManager.default.fileExists(atPath: url.path) {
                        result[entry.key] = url
                    }
                }
            }
            if let samples = root["samples"] as? [[String: Any]] {
                var resolved: [String: URL] = [:]
                for sample in samples {
                    guard let id = sample["id"] as? String,
                          let path = sample["path"] as? String else { continue }
                    let url = resolveMediaURL(path: path, baseURL: selectedURL.deletingLastPathComponent())
                    if FileManager.default.fileExists(atPath: url.path) {
                        resolved[id] = url
                    }
                }
                if !resolved.isEmpty {
                    return resolved
                }
            }
        }

        throw NSError(
            domain: "ConductorHarness",
            code: 1902,
            userInfo: [NSLocalizedDescriptionKey: "Manifest format unsupported"]
        )
    }

    private func resolveSampleEntries(_ entries: [SamplePackManifest.SampleEntry], baseURL: URL) -> [String: URL] {
        entries.reduce(into: [String: URL]()) { result, entry in
            let url = resolveMediaURL(path: entry.path, baseURL: baseURL)
            if FileManager.default.fileExists(atPath: url.path) {
                result[entry.id] = url
            }
        }
    }

    private func resolveMediaURL(path: String, baseURL: URL) -> URL {
        let direct = URL(fileURLWithPath: path)
        if direct.path.hasPrefix("/") {
            return direct
        }
        return baseURL.appendingPathComponent(path)
    }

    private func resolvedPhoneTargets() -> [String] {
        switch phoneAudioTargetMode {
        case .rotating:
            return []
        case .single:
            if phoneAudioAvailableDevices.contains(phoneAudioSingleTargetID), !phoneAudioSingleTargetID.isEmpty {
                return [phoneAudioSingleTargetID]
            }
            return phoneAudioAvailableDevices.first.map { [$0] } ?? []
        case .subset:
            let sorted = phoneAudioAvailableDevices.filter { phoneAudioSubsetTargetIDs.contains($0) }
            if sorted.isEmpty {
                return Array(phoneAudioAvailableDevices.prefix(2))
            }
            return sorted
        }
    }

    func refreshModelCatalog() {
        let discovered = scoringModel.availableModelCandidates()
        var map: [String: CompiledModelCandidate] = [:]

        for candidate in importedModelCandidates + discovered {
            map[candidate.id] = candidate
        }

        let merged = map.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        modelCandidates = merged

        if selectedModelCandidateID.isEmpty || !merged.contains(where: { $0.id == selectedModelCandidateID }) {
            selectedModelCandidateID = merged.first?.id ?? ""
        }
    }

    func reloadPreferredModel() {
        let report = scoringModel.reload(
            preferredModelName: ProcessInfo.processInfo.environment["CONDUCTOR_COREML_MODEL_NAME"]
        )
        refreshModelCatalog()
        if let path = report.modelPath {
            selectedModelCandidateID = path
        }
        applyModelHealth(report)
    }

    func loadSelectedModelBundle() {
        guard let candidate = modelCandidates.first(where: { $0.id == selectedModelCandidateID }) else {
            pushStatus(StatusLineEvent(
                message: "No .mlmodelc bundle selected",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let report = scoringModel.loadModel(at: candidate.url)
        applyModelHealth(report)
    }

    func importModelBundleFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Import Compiled CoreML Bundle"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let compiledModelType = UTType(filenameExtension: "mlmodelc") {
            panel.allowedContentTypes = [compiledModelType]
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        guard let modelBundleURL = resolveModelBundleURL(from: selectedURL) else {
            pushStatus(StatusLineEvent(
                message: "No .mlmodelc bundle found in selected location",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let candidate = CompiledModelCandidate(
            name: modelBundleURL.deletingPathExtension().lastPathComponent,
            url: modelBundleURL
        )

        if !importedModelCandidates.contains(where: { $0.id == candidate.id }) {
            importedModelCandidates.append(candidate)
        }

        selectedModelCandidateID = candidate.id
        let report = scoringModel.loadModel(at: candidate.url)
        refreshModelCatalog()
        applyModelHealth(report)
    }

    func importSceneMedia(for scene: ShowState) {
        guard scene != .main else {
            pushStatus(StatusLineEvent(
                message: "Main media import is disabled (main is lane-driven)",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Import Media for \(scene.rawValue.capitalized)"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .audio]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        sceneMediaURLs[scene] = selectedURL
        prewarmMediaDuration(for: selectedURL)
        saveMediaManifest()
        let previewCue = latestCue ?? CueCommand(cueId: "\(scene.rawValue):0", showState: scene, logicalTime: 0, action: .jump)
        if state == scene || latestCue == nil {
            updatePreview(for: previewCue)
        }
    }

    func importShowFixedLaneMedia() {
        let panel = NSOpenPanel()
        panel.title = "Add showFixed Lane Media"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .audio]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        showFixedCounter += 1
        let lane = ShowFixedLane(
            id: String(format: "main-%02d", showFixedCounter),
            label: "main-\(showFixedCounter)",
            mediaURL: selectedURL
        )
        showFixedLanes.append(lane)
        prewarmMediaDuration(for: selectedURL)

        pushStatus(StatusLineEvent(
            message: "Added showFixed lane \(lane.id)",
            severity: .success,
            timestamp: Date()
        ))
        saveMediaManifest()
    }

    func importInterstitialMedia() {
        let panel = NSOpenPanel()
        panel.title = "Import Interstitial Loop Media"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        interstitialMediaURL = selectedURL
        prewarmMediaDuration(for: selectedURL)
        saveMediaManifest()
        updatePreviewForCurrentMode()
    }

    func mediaFilename(for scene: ShowState) -> String {
        sceneMediaURLs[scene]?.lastPathComponent ?? "none"
    }

    func interstitialFilename() -> String {
        interstitialMediaURL?.lastPathComponent ?? "none"
    }

    func playPreview() {
        previewPlayer.play()
    }

    func pausePreview() {
        previewPlayer.pause()
    }

    private func resolveModelBundleURL(from selectedURL: URL) -> URL? {
        if selectedURL.pathExtension.lowercased() == "mlmodelc" {
            return selectedURL
        }

        let nested = CoreMLModelLocator.discoverCompiledModels(in: [selectedURL])
        return nested.first?.url
    }

    private func updatePreviewForCurrentMode() {
        let cue = latestCue ?? CueCommand(cueId: "\(state.rawValue):0", showState: state, logicalTime: 0, action: .jump)
        updatePreview(for: cue)
    }

    private func updatePreview(for cue: CueCommand, outputProfile: OutputProfile? = nil) {
        let profile = outputProfile ?? resolveOutputProfile(for: cue.showState)
        effectiveOutputMode = profile.mode
        previewScene = cue.showState

        guard profile.showFixed else {
            configurePreviewLoop(shouldLoop: false)
            if profile.mode == .off {
                previewStatus = "Engine stopped (video output inactive)"
            } else if profile.mode == .interstitial {
                previewStatus = "No interstitial loop media imported"
            } else {
                previewStatus = "Dynamic-only mode (no fixed preview video)"
            }
            previewPlayer.pause()
            return
        }

        let mediaURL: URL?
        if profile.usesInterstitialMedia {
            mediaURL = interstitialMediaURL
        } else if let laneId = profile.showFixedLaneId {
            mediaURL = laneMediaURL(for: laneId)
        } else {
            mediaURL = sceneMediaURLs[cue.showState]
        }

        guard let mediaURL else {
            configurePreviewLoop(shouldLoop: false)
            previewStatus = profile.usesInterstitialMedia
                ? "No interstitial loop media imported"
                : "No fixed media for current output lane"
            previewPlayer.pause()
            return
        }

        let replacingPreviewItem = currentPreviewURL != mediaURL
        if replacingPreviewItem {
            previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: mediaURL))
        }

        let seekSeconds = profile.usesInterstitialMedia ? 0 : max(0, cue.logicalTime)
        if shouldSeekPreview(
            replacingItem: replacingPreviewItem,
            targetSeconds: seekSeconds
        ) {
            let seekTime = CMTime(seconds: seekSeconds, preferredTimescale: 600)
            let seekTolerance = CMTime(seconds: 0.08, preferredTimescale: 600)
            previewPlayer.seek(to: seekTime, toleranceBefore: seekTolerance, toleranceAfter: seekTolerance)
        }
        configurePreviewLoop(shouldLoop: profile.loopsIndefinitely)
        if previewPlayer.timeControlStatus != .playing {
            previewPlayer.play()
        }

        previewStatus = "Previewing \(profile.mode.rawValue): \(mediaURL.lastPathComponent)"
    }

    private var currentPreviewURL: URL? {
        (previewPlayer.currentItem?.asset as? AVURLAsset)?.url
    }

    private func shouldSeekPreview(replacingItem: Bool, targetSeconds: TimeInterval) -> Bool {
        guard !replacingItem else {
            // Fresh items start at zero naturally; only seek if we need a non-zero jump.
            return targetSeconds > 0.08
        }

        let currentSeconds = CMTimeGetSeconds(previewPlayer.currentTime())
        guard currentSeconds.isFinite else {
            return true
        }

        // Skip near-identical seeks to keep TAKE/GO and timeline commits responsive.
        return abs(currentSeconds - targetSeconds) > 0.20
    }

    private func resolveOutputProfile(
        for showState: ShowState,
        overrideStaticLaneId: String? = nil
    ) -> OutputProfile {
        switch committedOutputMode {
        case .off:
            guard engineRunning else {
                return OutputProfile(
                    mode: .off,
                    showFixed: false,
                    showDynamic: false,
                    loopsIndefinitely: false,
                    usesInterstitialMedia: false,
                    showFixedLaneId: nil
                )
            }
            return OutputProfile(
                mode: .interstitial,
                showFixed: true,
                showDynamic: false,
                loopsIndefinitely: true,
                usesInterstitialMedia: true,
                showFixedLaneId: nil
            )
        case .dynamic:
            return OutputProfile(
                mode: .dynamic,
                showFixed: false,
                showDynamic: true,
                loopsIndefinitely: false,
                usesInterstitialMedia: false,
                showFixedLaneId: nil
            )
        case .static:
            let laneId = overrideStaticLaneId ?? activeStaticLaneId
            if let laneId, laneMediaURL(for: laneId) != nil {
                return OutputProfile(
                    mode: .static,
                    showFixed: true,
                    showDynamic: false,
                    loopsIndefinitely: false,
                    usesInterstitialMedia: false,
                    showFixedLaneId: laneId
                )
            }

            if shouldUseInterstitial(for: showState) {
                return OutputProfile(
                    mode: .interstitial,
                    showFixed: true,
                    showDynamic: false,
                    loopsIndefinitely: true,
                    usesInterstitialMedia: true,
                    showFixedLaneId: laneId
                )
            }

            return OutputProfile(
                mode: .static,
                showFixed: true,
                showDynamic: false,
                loopsIndefinitely: false,
                usesInterstitialMedia: false,
                showFixedLaneId: laneId
            )
        }
    }

    private func laneTargetState(for laneId: String) -> ShowState? {
        if let privileged = privilegedLaneStateMap[laneId] {
            return privileged
        }
        if showFixedLanes.contains(where: { $0.id == laneId }) {
            return .main
        }
        return nil
    }

    private func timelineStepPlan(for laneId: String) -> TimelineStepPlan? {
        timelineStepPlans[laneId]
    }

    private func laneMediaURL(for laneId: String) -> URL? {
        if let state = privilegedLaneStateMap[laneId] {
            return sceneMediaURLs[state]
        }
        return showFixedLanes.first(where: { $0.id == laneId })?.mediaURL
    }

    private func shouldUseInterstitial(for showState: ShowState) -> Bool {
        guard interstitialMediaURL != nil else {
            return false
        }
        return isBetweenStartedAndEnding(showState)
    }

    private func isBetweenStartedAndEnding(_ showState: ShowState) -> Bool {
        switch showState {
        case .preshow, .introduction, .main, .hold, .aborted, .recovery:
            return true
        case .idle, .ending:
            return false
        }
    }

    private func configurePreviewLoop(shouldLoop: Bool) {
        if shouldLoop {
            previewPlayer.actionAtItemEnd = .none
            guard previewLoopObserver == nil else {
                return
            }
            previewLoopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self,
                      let endedItem = note.object as? AVPlayerItem,
                      endedItem == self.previewPlayer.currentItem
                else {
                    return
                }
                let loopTolerance = CMTime(seconds: 0.03, preferredTimescale: 600)
                self.previewPlayer.seek(to: .zero, toleranceBefore: loopTolerance, toleranceAfter: loopTolerance)
                self.previewPlayer.play()
            }
            return
        }

        previewPlayer.actionAtItemEnd = .pause
        if let observer = previewLoopObserver {
            NotificationCenter.default.removeObserver(observer)
            previewLoopObserver = nil
        }
    }

    private func scheduleStaticAutoReturn(
        for cue: CueCommand,
        targetState: ShowState,
        outputProfile: OutputProfile
    ) {
        guard let mediaURL = staticMediaURL(for: cue, outputProfile: outputProfile) else {
            return
        }

        let sourceCueId = cue.cueId
        Task { [weak self] in
            guard let self else { return }
            guard self.latestCue?.cueId == sourceCueId else { return }
            guard self.committedOutputMode == .static else { return }

            guard let duration = await self.cachedMediaDuration(for: mediaURL) else {
                self.pushStatus(StatusLineEvent(
                    message: "Static clip duration unavailable; output stays \(self.committedOutputMode.uiLabel.uppercased())",
                    severity: .warn,
                    timestamp: Date()
                ))
                return
            }

            self.cancelSequenceWork()
            self.scheduleSequenceStep(after: duration) { [weak self] in
                guard let self else { return }
                guard self.latestCue?.cueId == sourceCueId else { return }
                guard self.committedOutputMode == .static else { return }

                self.committedOutputMode = .off
                self.activeStaticLaneId = nil

                self.apply(
                    action: .jump,
                    target: targetState,
                    extraPayload: [
                        "sequence": "static_complete",
                        "sequenceStep": "inter",
                        "sourceCueId": sourceCueId
                    ]
                )
            }
        }
    }

    private func staticMediaURL(for cue: CueCommand, outputProfile: OutputProfile) -> URL? {
        if let laneId = outputProfile.showFixedLaneId {
            return laneMediaURL(for: laneId)
        }
        return sceneMediaURLs[cue.showState]
    }

    private func cachedMediaDuration(for mediaURL: URL) async -> TimeInterval? {
        let key = mediaURL.standardizedFileURL.path
        if let cached = mediaDurationCache[key] {
            return cached
        }

        let task = mediaDurationTask(for: mediaURL)
        let duration = await task.value
        mediaDurationTaskCache[key] = nil
        if let duration {
            mediaDurationCache[key] = duration
        }
        return duration
    }

    private func prewarmMediaDuration(for mediaURL: URL) {
        _ = mediaDurationTask(for: mediaURL)
    }

    private func prewarmMediaDurations(_ mediaURLs: [URL]) {
        for mediaURL in mediaURLs {
            prewarmMediaDuration(for: mediaURL)
        }
    }

    private func mediaDurationTask(for mediaURL: URL) -> Task<TimeInterval?, Never> {
        let key = mediaURL.standardizedFileURL.path
        if let cached = mediaDurationCache[key] {
            return Task { cached }
        }
        if let existing = mediaDurationTaskCache[key] {
            return existing
        }

        let task = Task.detached(priority: .utility) { [mediaURL] () -> TimeInterval? in
            let asset = AVURLAsset(url: mediaURL)
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else {
                    return nil
                }
                return seconds
            } catch {
                return nil
            }
        }
        mediaDurationTaskCache[key] = task

        Task { [weak self] in
            let value = await task.value
            await MainActor.run {
                guard let self else { return }
                self.mediaDurationTaskCache[key] = nil
                if let value {
                    self.mediaDurationCache[key] = value
                }
            }
        }

        return task
    }

    private func scheduleSequenceStep(after delay: TimeInterval, block: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: block)
        sequenceWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelSequenceWork() {
        for workItem in sequenceWorkItems {
            workItem.cancel()
        }
        sequenceWorkItems.removeAll()
    }

    private func startLatchTimer() {
        latchTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickLatch()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        latchTimer = timer
    }

    private func tickLatch() {
        guard isLatchArmed else { return }
        let now = Date()
        let snapshot = latchController.tick(now: now)
        syncLatchState(snapshot, now: now)
    }

    private func syncLatchState(_ snapshot: OutputLatchSnapshot, now: Date) {
        let nextPendingOutputMode = snapshot.pendingMode.flatMap { FlightOutputMode(rawValue: $0) }
        if pendingOutputMode != nextPendingOutputMode {
            pendingOutputMode = nextPendingOutputMode
        }

        if pendingLaneId != snapshot.pendingLaneId {
            pendingLaneId = snapshot.pendingLaneId
        }

        if isLatchArmed != snapshot.isArmed {
            isLatchArmed = snapshot.isArmed
        }

        if latchExpiresAt != snapshot.expiresAt {
            latchExpiresAt = snapshot.expiresAt
        }

        if canFireGO != snapshot.canFire {
            canFireGO = snapshot.canFire
        }

        let nextSummary = snapshot.summary
        if latchSummary != nextSummary {
            latchSummary = nextSummary
        }

        let nextCountdown = snapshot.countdownSeconds(at: now)
        let countdownChanged: Bool = {
            switch (latchCountdownSeconds, nextCountdown) {
            case (nil, nil):
                return false
            case (.some(let lhs), .some(let rhs)):
                return abs(lhs - rhs) > 0.049
            default:
                return true
            }
        }()
        if countdownChanged {
            latchCountdownSeconds = nextCountdown
        }
        if lastLatchStatus != snapshot.status {
            lastLatchStatus = snapshot.status
            pushStatus(snapshot.status)
        }
    }

    private func applyModelHealth(_ report: ModelHealthReport) {
        modelHealthLevel = report.level
        modelHealthSummary = report.summary
        modelChecks = report.checks
        modelRuntimeFailures = report.runtimeFailureCount
    }

    // MARK: - Media persistence

    private func saveMediaManifest() {
        let destinationURL = MediaManifest.preferredFileURL()
        let manifest = MediaManifest(
            sceneMedia: Dictionary(
                uniqueKeysWithValues: sceneMediaURLs
                    .filter { $0.key != .main }
                    .map { ($0.key.rawValue, $0.value.path) }
            ),
            interstitialMedia: interstitialMediaURL?.path,
            fixedLanes: showFixedLanes.map {
                MediaManifest.FixedLaneEntry(id: $0.id, label: $0.label, path: $0.mediaURL.path)
            },
            synthPresetPack: synthPresetPackURL?.path,
            samplePackManifest: samplePackManifestURL?.path,
            choirProfile: choirProfileURL?.path
        )

        do {
            let directoryURL = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: destinationURL, options: .atomic)
            pushStatus(StatusLineEvent(
                message: "Saved media manifest: \(destinationURL.path)",
                severity: .info,
                timestamp: Date()
            ))
        } catch {
            pushStatus(StatusLineEvent(
                message: "Media manifest save failed: \(error.localizedDescription)",
                severity: .warn,
                timestamp: Date()
            ))
        }
    }

    private func loadMediaManifest() {
        let candidates = MediaManifest.candidateFileURLs()
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            if let preferred = candidates.first {
                pushStatus(StatusLineEvent(
                    message: "No media manifest found (checked: \(preferred.path))",
                    severity: .info,
                    timestamp: Date()
                ))
            }
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(MediaManifest.self, from: data)

            let fm = FileManager.default
            for (rawState, path) in manifest.sceneMedia {
                guard let state = ShowState(rawValue: rawState), state != .main, fm.fileExists(atPath: path) else { continue }
                sceneMediaURLs[state] = URL(fileURLWithPath: path)
            }

            if let interPath = manifest.interstitialMedia, fm.fileExists(atPath: interPath) {
                interstitialMediaURL = URL(fileURLWithPath: interPath)
            }

            if let synthPath = manifest.synthPresetPack, fm.fileExists(atPath: synthPath) {
                synthPresetPackURL = URL(fileURLWithPath: synthPath)
            }

            if let sampleManifestPath = manifest.samplePackManifest, fm.fileExists(atPath: sampleManifestPath) {
                let manifestURL = URL(fileURLWithPath: sampleManifestPath)
                samplePackManifestURL = manifestURL
                if let entries = try? resolveSamplePackEntries(from: manifestURL) {
                    samplePackEntries = entries
                    if let firstID = entries.keys.sorted().first {
                        selectedSampleID = firstID
                    }
                }
            }

            if let choirPath = manifest.choirProfile, fm.fileExists(atPath: choirPath) {
                choirProfileURL = URL(fileURLWithPath: choirPath)
            }

            var restoredLanes: [ShowFixedLane] = []
            for entry in manifest.fixedLanes {
                guard fm.fileExists(atPath: entry.path) else { continue }
                restoredLanes.append(ShowFixedLane(
                    id: entry.id,
                    label: entry.label,
                    mediaURL: URL(fileURLWithPath: entry.path)
                ))
            }
            showFixedLanes = restoredLanes
            showFixedCounter = restoredLanes.count

            var warmupURLs = Array(sceneMediaURLs.values)
            if let interstitialMediaURL {
                warmupURLs.append(interstitialMediaURL)
            }
            warmupURLs.append(contentsOf: restoredLanes.map(\.mediaURL))
            prewarmMediaDurations(warmupURLs)

            let count = sceneMediaURLs.count
                + (interstitialMediaURL != nil ? 1 : 0)
                + showFixedLanes.count
                + (synthPresetPackURL != nil ? 1 : 0)
                + (samplePackManifestURL != nil ? 1 : 0)
                + (choirProfileURL != nil ? 1 : 0)
            if count > 0 {
                pushStatus(StatusLineEvent(
                    message: "Restored \(count) media entries from \(url.path)",
                    severity: .success,
                    timestamp: Date()
                ))
            }
        } catch {
            pushStatus(StatusLineEvent(
                message: "Media manifest load failed: \(error.localizedDescription)",
                severity: .warn,
                timestamp: Date()
            ))
        }
    }

    private func handleBackendMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = json["kind"] as? String
        else {
            return
        }

        if kind == "error",
           let payload = json["data"] as? [String: Any],
           let message = payload["message"] as? String {
            lastLinkError = message
            pushStatus(StatusLineEvent(
                message: "Backend error: \(message)",
                severity: .error,
                timestamp: Date()
            ))
            return
        }

        if kind == "phone_audio_pool_state",
           let payload = json["data"] as? [String: Any] {
            if let gateArmed = payload["gateArmed"] as? Bool {
                if phoneAudioGateArmed != gateArmed {
                    phoneAudioGateArmed = gateArmed
                }
            }
            if let gateCommitted = payload["gateCommitted"] as? Bool {
                if phoneAudioGateCommitted != gateCommitted {
                    phoneAudioGateCommitted = gateCommitted
                }
            }
            if let quadReady = payload["quadRouteReady"] as? Bool {
                if quadRouteReady != quadReady {
                    quadRouteReady = quadReady
                }
            }
            if let available = payload["availableDevices"] as? [String] {
                if phoneAudioAvailableDevices != available {
                    phoneAudioAvailableDevices = available
                }

                let nextSingleTarget: String
                if available.contains(phoneAudioSingleTargetID) {
                    nextSingleTarget = phoneAudioSingleTargetID
                } else {
                    nextSingleTarget = available.first ?? ""
                }
                if phoneAudioSingleTargetID != nextSingleTarget {
                    phoneAudioSingleTargetID = nextSingleTarget
                }

                let nextSubset = phoneAudioSubsetTargetIDs.intersection(Set(available))
                if phoneAudioSubsetTargetIDs != nextSubset {
                    phoneAudioSubsetTargetIDs = nextSubset
                }
            }
            if let voices = payload["activeVoices"] as? [String: Any] {
                var normalized: [String: Int] = [:]
                for (key, value) in voices {
                    if let intValue = value as? Int {
                        normalized[key] = intValue
                    } else if let doubleValue = value as? Double {
                        normalized[key] = Int(doubleValue)
                    }
                }
                if phoneAudioActiveVoices != normalized {
                    phoneAudioActiveVoices = normalized
                }
            }
            return
        }

        if kind == "phone_audio_ack",
           let payload = json["data"] as? [String: Any] {
            let commandId = payload["commandId"] as? String ?? "unknown"
            let hashedId = payload["hashedId"] as? String ?? "device"
            let ok = payload["ok"] as? Bool ?? false
            let detail = payload["detail"] as? String
            let suffix = detail.map { " (\($0))" } ?? ""
            if !ok {
                pushStatus(StatusLineEvent(
                    message: "PHONE ACK \(commandId) FAIL @ \(hashedId)\(suffix)",
                    severity: .warn,
                    timestamp: Date()
                ))
            }
            return
        }

        if kind == "audio_features",
           let payload = json["data"] as? [String: Any] {
            let current = latestAudioFeaturesRaw
            ingestAudioFeatures(QuadAudioFeatures(
                rms: payload["rms"] as? Double ?? current.rms,
                spectralCentroid: payload["spectralCentroid"] as? Double ?? current.spectralCentroid,
                flux: payload["flux"] as? Double ?? current.flux,
                transientDensity: payload["transientDensity"] as? Double ?? current.transientDensity,
                updatedAt: payload["updatedAt"] as? Double ?? current.updatedAt
            ))
            return
        }

        if kind == "show_snapshot",
           let payload = json["data"] as? [String: Any],
           let rawState = payload["state"] as? String,
           let snapshotState = ShowState(rawValue: rawState) {
            if state != snapshotState {
                state = snapshotState
            }
        }
    }
}
