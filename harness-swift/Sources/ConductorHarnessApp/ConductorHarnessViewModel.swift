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
}

enum EffectiveOutputMode: String {
    case `static`
    case dynamic
    case interstitial
    case off
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

private struct MediaManifest: Codable {
    var sceneMedia: [String: String]
    var interstitialMedia: String?
    var fixedLanes: [FixedLaneEntry]

    struct FixedLaneEntry: Codable {
        let id: String
        let label: String
        let path: String
    }

    static let fileName = "conductor_media.json"

    static func fileURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(fileName)
    }
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

@MainActor
final class ConductorHarnessViewModel: ObservableObject {
    @Published var state: ShowState = .idle
    @Published var vector: ParamVector = .neutral
    @Published var latestCue: CueCommand?
    @Published var generatedLine: String = ""
    @Published var devices: [DeviceTelemetry] = []
    @Published var connectionStatus: String = "Disconnected"

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

    @Published var pendingOutputMode: FlightOutputMode?
    @Published var pendingLaneId: String?
    @Published var isLatchArmed = false
    @Published var canFireGO = false
    @Published var latchSummary: String = "DISARMED"
    @Published var latchCountdownSeconds: Double?
    @Published var statusLineEvent = StatusLineEvent(
        message: "Latch disarmed",
        severity: .info,
        timestamp: Date()
    )
    @Published private(set) var statusLineHistory: [StatusLineEvent] = []
    @Published var masterArmKey: MasterArmKeyState = .safe
    @Published private(set) var abortCoverOpen: Bool = false

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

    private var importedModelCandidates: [CompiledModelCandidate] = []
    private var previewLoopObserver: NSObjectProtocol?
    private var latchController = OutputLatchController(timeoutSeconds: 8)
    private var latchTimer: Timer?
    private var showFixedCounter = 0
    private var sequenceWorkItems: [DispatchWorkItem] = []

    private let privilegedLaneStateMap: [String: ShowState] = [
        "preshow": .preshow,
        "introduction": .introduction,
        "ending": .ending
    ]

    private static let statusTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init() {
        let preferredModelName = ProcessInfo.processInfo.environment["CONDUCTOR_COREML_MODEL_NAME"]
        let scoringModel = CoreMLScoringModelAdapter(preferredModelName: preferredModelName)
        self.scoringModel = scoringModel
        self.textEngine = TextSelectionEngine(model: scoringModel)

        websocket.onMessage = { [weak self] text in
            Task { @MainActor in
                self?.handleBackendMessage(text)
            }
        }

        refreshModelCatalog()
        applyModelHealth(scoringModel.currentHealth())
        syncLatchState(latchController.snapshot, now: Date())
        startLatchTimer()
        loadMediaManifest()
    }

    deinit {
        if let observer = previewLoopObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        latchTimer?.invalidate()
        abortCoverTimer?.invalidate()
    }

    // MARK: - Status helpers

    /// Single funnel for every status line update. Mirrors the latest event
    /// into `statusLineEvent` (the existing API the UI binds to) and appends
    /// to the bounded `statusLineHistory` ring buffer that feeds the flight
    /// log. Consecutive identical messages are deduped so the latch tick
    /// (which fires every 0.2s) doesn't flood the tape.
    private func pushStatus(_ event: StatusLineEvent) {
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
        canFireGO && masterArmKey == .armed
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
            Task { @MainActor in
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
        var descriptors: [TransportLaneDescriptor] = []

        if sceneMediaURLs[.main] != nil {
            let laneId = "main-base"
            descriptors.append(
                TransportLaneDescriptor(
                    id: laneId,
                    label: laneId,
                    canArm: true,
                    isArmed: pendingLaneId == laneId,
                    isActive: activeStaticLaneId == laneId || state == .main
                )
            )
        }

        descriptors.append(contentsOf: showFixedLanes.map { lane in
            TransportLaneDescriptor(
                id: lane.id,
                label: lane.label,
                canArm: true,
                isArmed: pendingLaneId == lane.id,
                isActive: activeStaticLaneId == lane.id
            )
        })

        return descriptors
    }

    func connect(to urlString: String) {
        guard let url = URL(string: urlString) else {
            connectionStatus = "Invalid websocket URL"
            return
        }
        websocket.connect(url: url)
        connectionStatus = "Connecting"
    }

    func disconnect() {
        websocket.disconnect()
        connectionStatus = "Disconnected"
    }

    func canApply(action: CueAction, target: ShowState? = nil) -> Bool {
        machine.canApply(action: action, targetState: target)
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
            updatePreview(for: cue, outputProfile: outputProfile)
            if outputProfile.mode == .static, outputProfile.showFixed, !outputProfile.loopsIndefinitely {
                let fallbackState = staticAutoReturnTarget ?? cue.showState
                scheduleStaticAutoReturn(for: cue, targetState: fallbackState, outputProfile: outputProfile)
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
                        self.connectionStatus = "Command dispatch failed: \(error.localizedDescription)"
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
            connectionStatus = "Transition error: \(error.localizedDescription)"
        }
    }

    func patchVector(_ patch: ParamVectorPatch) {
        vector = machine.updateVector(with: patch)

        Task {
            do {
                try await websocket.sendVector(vector)
            } catch {
                await MainActor.run {
                    self.connectionStatus = "Vector dispatch failed: \(error.localizedDescription)"
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
                self.connectionStatus = "Freeze captured: \(events.count) events"
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
        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "Blocked: start engine first",
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
        committedOutputMode = .off
        activeStaticLaneId = nil
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
        runTimelineStep(
            laneId: "preshow",
            targetState: .preshow,
            completionState: .preshow
        )
    }

    func runIntroductionTimelineStep() {
        runTimelineStep(
            laneId: "introduction",
            targetState: .introduction,
            completionState: .main
        )
    }

    func runEndingTimelineStep() {
        runTimelineStep(
            laneId: "ending",
            targetState: .ending,
            completionState: .idle
        )
    }

    private func runTimelineStep(
        laneId: String,
        targetState: ShowState,
        completionState: ShowState
    ) {
        guard engineRunning else {
            pushStatus(StatusLineEvent(
                message: "Blocked: start engine first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        cancelSequenceWork()
        committedOutputMode = .static
        activeStaticLaneId = laneId

        let now = Date()
        let snapshot = latchController.reset(now: now, message: "Timeline \(laneId) armed")
        syncLatchState(snapshot, now: now)

        apply(
            action: .jump,
            target: targetState,
            extraPayload: [
                "sequence": "timeline",
                "sequenceStep": laneId
            ],
            overrideStaticLaneId: laneId,
            staticAutoReturnTarget: completionState
        )
    }

    func resetShowRun() {
        cancelSequenceWork()
        engineRunning = false
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
            connectionStatus = "No .mlmodelc bundle selected"
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
            connectionStatus = "No .mlmodelc bundle found in selected location"
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
            previewStatus = profile.mode == .off ? "Output OFF" : "Dynamic-only mode (no fixed preview video)"
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

        if currentPreviewURL != mediaURL {
            previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: mediaURL))
        }

        let seekSeconds = profile.usesInterstitialMedia ? 0 : max(0, cue.logicalTime)
        let seekTime = CMTime(seconds: seekSeconds, preferredTimescale: 600)
        previewPlayer.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        configurePreviewLoop(shouldLoop: profile.loopsIndefinitely)
        previewPlayer.play()

        previewStatus = "Previewing \(profile.mode.rawValue): \(mediaURL.lastPathComponent)"
    }

    private var currentPreviewURL: URL? {
        (previewPlayer.currentItem?.asset as? AVURLAsset)?.url
    }

    private func resolveOutputProfile(
        for showState: ShowState,
        overrideStaticLaneId: String? = nil
    ) -> OutputProfile {
        switch committedOutputMode {
        case .off:
            return OutputProfile(
                mode: .off,
                showFixed: false,
                showDynamic: false,
                loopsIndefinitely: false,
                usesInterstitialMedia: false,
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
        if laneId == "main-base" {
            return .main
        }
        if showFixedLanes.contains(where: { $0.id == laneId }) {
            return .main
        }
        return nil
    }

    private func laneMediaURL(for laneId: String) -> URL? {
        if let state = privilegedLaneStateMap[laneId] {
            return sceneMediaURLs[state]
        }
        if laneId == "main-base" {
            return sceneMediaURLs[.main]
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
                self.previewPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
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

        guard let duration = staticMediaDuration(for: mediaURL) else {
            pushStatus(StatusLineEvent(
                message: "Static clip duration unavailable; output stays \(committedOutputMode.rawValue.uppercased())",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        cancelSequenceWork()
        let sourceCueId = cue.cueId
        scheduleSequenceStep(after: duration) { [weak self] in
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
                    "sequenceStep": "off",
                    "sourceCueId": sourceCueId
                ]
            )
        }
    }

    private func staticMediaURL(for cue: CueCommand, outputProfile: OutputProfile) -> URL? {
        if let laneId = outputProfile.showFixedLaneId {
            return laneMediaURL(for: laneId)
        }
        return sceneMediaURLs[cue.showState]
    }

    private func staticMediaDuration(for mediaURL: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: mediaURL)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }
        return seconds
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
            Task { @MainActor in
                self?.tickLatch()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        latchTimer = timer
    }

    private func tickLatch() {
        let now = Date()
        let snapshot = latchController.tick(now: now)
        syncLatchState(snapshot, now: now)
    }

    private func syncLatchState(_ snapshot: OutputLatchSnapshot, now: Date) {
        pendingOutputMode = snapshot.pendingMode.flatMap { FlightOutputMode(rawValue: $0) }
        pendingLaneId = snapshot.pendingLaneId
        isLatchArmed = snapshot.isArmed
        canFireGO = snapshot.canFire
        latchSummary = snapshot.summary
        latchCountdownSeconds = snapshot.countdownSeconds(at: now)
        pushStatus(snapshot.status)
    }

    private func applyModelHealth(_ report: ModelHealthReport) {
        modelHealthLevel = report.level
        modelHealthSummary = report.summary
        modelChecks = report.checks
        modelRuntimeFailures = report.runtimeFailureCount
    }

    // MARK: - Media persistence

    private func saveMediaManifest() {
        let manifest = MediaManifest(
            sceneMedia: Dictionary(
                uniqueKeysWithValues: sceneMediaURLs.map { ($0.key.rawValue, $0.value.path) }
            ),
            interstitialMedia: interstitialMediaURL?.path,
            fixedLanes: showFixedLanes.map {
                MediaManifest.FixedLaneEntry(id: $0.id, label: $0.label, path: $0.mediaURL.path)
            }
        )

        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: MediaManifest.fileURL(), options: .atomic)
        } catch {
            pushStatus(StatusLineEvent(
                message: "Media manifest save failed: \(error.localizedDescription)",
                severity: .warn,
                timestamp: Date()
            ))
        }
    }

    private func loadMediaManifest() {
        let url = MediaManifest.fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(MediaManifest.self, from: data)

            let fm = FileManager.default
            for (rawState, path) in manifest.sceneMedia {
                guard let state = ShowState(rawValue: rawState), fm.fileExists(atPath: path) else { continue }
                sceneMediaURLs[state] = URL(fileURLWithPath: path)
            }

            if let interPath = manifest.interstitialMedia, fm.fileExists(atPath: interPath) {
                interstitialMediaURL = URL(fileURLWithPath: interPath)
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

            let count = sceneMediaURLs.count + (interstitialMediaURL != nil ? 1 : 0) + showFixedLanes.count
            if count > 0 {
                pushStatus(StatusLineEvent(
                    message: "Restored \(count) media entries from manifest",
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
            connectionStatus = "Connected"
            return
        }

        if kind == "error",
           let payload = json["data"] as? [String: Any],
           let message = payload["message"] as? String {
            connectionStatus = "Backend error: \(message)"
            return
        }

        if kind == "show_snapshot",
           let payload = json["data"] as? [String: Any],
           let rawState = payload["state"] as? String,
           let snapshotState = ShowState(rawValue: rawState) {
            state = snapshotState
        }

        connectionStatus = "Connected"
    }
}
