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

enum SoundModePrimary: String, Equatable {
    case normal = "NORMAL"
    case phoneChoir = "PHONE CHOIR"
}

enum SoundModeDetail: String, Equatable {
    case `static` = "STATIC"
    case dynamic = "DYNAMIC"
    case inter = "INTER"
    case off = "OFF"
}

enum SoundSignalLevel: Equatable {
    case nominal
    case caution
    case critical
}

enum ActiveSoundBankDomain: String, Equatable {
    case main = "MAIN"
    case choir = "CHOIR"
}

struct SoundBankImportState: Equatable {
    let mainBank: Int
    let choirBank: Int
    let samplePackFile: String
    let sampleEntryCount: Int
    let synthPresetFile: String
    let choirProfileFile: String
    let sampleImportReady: Bool
    let level: SoundSignalLevel
}

struct SoundIOState: Equatable {
    let outputRouteName: String
    let outputRouteSummary: String
    let midiInputName: String
    let midiStatus: String
    let hotasStatus: String
    let pushStatus: String
    let level: SoundSignalLevel
}

struct ActiveSoundTarget: Equatable {
    let sampleID: String
    let label: String
    let fileName: String
    let bankDomain: ActiveSoundBankDomain
    let bank: Int
}

struct SoundManipulationFocus: Equatable {
    let source: String
    let controlID: String
    let lane: String
    let normalizedValue: Double
    let updatedAt: TimeInterval
}

struct SoundSituationalSnapshot: Equatable {
    static let manipulationStaleThresholdMs: TimeInterval = 1400

    let banksImport: SoundBankImportState
    let modePrimary: SoundModePrimary
    let modeDetail: SoundModeDetail
    let modeLevel: SoundSignalLevel
    let io: SoundIOState
    let activeTarget: ActiveSoundTarget
    let manipulation: SoundManipulationFocus?
    let manipulationIsStale: Bool
    let generatedAt: TimeInterval
}

enum AudioRouteCapability: String, CaseIterable, Identifiable {
    case unavailable
    case stereoFallback
    case quad

    var id: String { rawValue }

    var uiLabel: String {
        switch self {
        case .unavailable:
            return "nogo"
        case .stereoFallback:
            return "2ch fallback"
        case .quad:
            return "quad ready"
        }
    }
}

struct MIDIInputOption: Identifiable, Equatable {
    let id: String
    let name: String
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
        let label: String?
        let name: String?
        let displayName: String?
        let sampleClass: String?
        let key: String?
        let bpm: Double?
        let energy: Double?
        let timbre: Double?
        let loop: Bool?

        private enum CodingKeys: String, CodingKey {
            case id
            case path
            case label
            case name
            case displayName
            case sampleClass = "class"
            case key
            case bpm
            case energy
            case timbre
            case loop
        }
    }

    let samples: [SampleEntry]
}

private struct PushCompanionPadMap: Codable {
    struct Slice: Codable {
        let slot: Int
        let fileName: String?
        let label: String?
        let startSec: Double?
        let oneShotSec: Double?
    }

    let bank: Int?
    let title: String?
    let sourceFile: String?
    let slices: [Slice]
}

private struct PushPadLabelsPayload: Codable {
    var padLabels: [String]
    var bank: Int
    var updatedAt: TimeInterval
}

private struct ControlProfileDocument: Codable {
    var version: Int
    var activeProfile: ControlProfile
    var lastKnownGoodProfile: ControlProfile?
    var hotasStaticVideoOverrideEnabled: Bool
    var pushControlEnabled: Bool
    var trustedPushControllerIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case version
        case activeProfile
        case lastKnownGoodProfile
        case hotasStaticVideoOverrideEnabled
        case pushControlEnabled
        case trustedPushControllerIDs
    }

    init(
        version: Int,
        activeProfile: ControlProfile,
        lastKnownGoodProfile: ControlProfile?,
        hotasStaticVideoOverrideEnabled: Bool = true,
        pushControlEnabled: Bool = true,
        trustedPushControllerIDs: [String] = []
    ) {
        self.version = version
        self.activeProfile = activeProfile
        self.lastKnownGoodProfile = lastKnownGoodProfile
        self.hotasStaticVideoOverrideEnabled = hotasStaticVideoOverrideEnabled
        self.pushControlEnabled = pushControlEnabled
        self.trustedPushControllerIDs = trustedPushControllerIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        activeProfile = try container.decode(ControlProfile.self, forKey: .activeProfile)
        lastKnownGoodProfile = try container.decodeIfPresent(ControlProfile.self, forKey: .lastKnownGoodProfile)
        hotasStaticVideoOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotasStaticVideoOverrideEnabled) ?? true
        pushControlEnabled = try container.decodeIfPresent(Bool.self, forKey: .pushControlEnabled) ?? true
        trustedPushControllerIDs = try container.decodeIfPresent([String].self, forKey: .trustedPushControllerIDs) ?? []
    }

    static let fileName = "conductor_controls.json"

    static func preferredFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("ConductorHarness", isDirectory: true)
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

private struct TimelineStepPlan {
    let laneId: String
    let targetState: ShowState
    let completionState: ShowState
}

@MainActor
final class ConductorHarnessViewModel: ObservableObject, ControlActionRouting {
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
    @Published var modelSearchPaths: [String] = []
    @Published var modelSearchOverridePath: String? = nil

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
    @Published private(set) var audioRouteCapability: AudioRouteCapability = .unavailable
    @Published var allowStereoFallback = true
    @Published private(set) var availableAudioRoutes: [AudioRoute] = []
    @Published var selectedAudioRouteID: String = "default-output"
    @Published private(set) var latestAudioFeatures: QuadAudioFeatures = .zero
    @Published private(set) var availableMIDIInputs: [MIDIInputOption] = []
    @Published var selectedMIDIInputID: String = ""
    @Published private(set) var midiInputActive = false
    @Published private(set) var midiInputStatus = "MIDI OFF"
    @Published private(set) var hotasInputActive = false
    @Published private(set) var hotasInputStatus = "HOTAS OFF"
    @Published private(set) var hotasControlsEnabled = false
    @Published var hotasInputMode: ControlInputMode = .hybrid
    @Published private(set) var hotasProfileName: String = ControlProfile.defaultX56StrictLive.name
    @Published private(set) var hotasMissingRequiredRoles: [ControlRole] = []
    @Published private(set) var hotasBindingConflicts: [String] = []
    @Published private(set) var hotasConflictRoles: Set<ControlRole> = []
    @Published private(set) var hotasLastSignalSummary = "No HOTAS signal"
    @Published private(set) var hotasLastSignal: ControlSignal?
    @Published private(set) var hotasObservedSignals: [ControlSignal] = []
    @Published private(set) var hotasPendingCaptureRole: ControlRole?
    @Published private(set) var hotasTrainingActive = false
    @Published private(set) var hotasPhoneChoirContextActive = false
    @Published private(set) var activeSampleBank = 1
    @Published private(set) var activeChoirSampleBank = 1
    @Published var hotasStaticVideoOverrideEnabled = true
    @Published var pushControlEnabled = true
    @Published private(set) var pushRecentControllerIDs: [String] = []
    @Published private(set) var pushTrustedControllerIDs: [String] = []
    @Published private(set) var pushLastSignalSummary = "Push OFF"
    @Published private(set) var pushPhonePadEchoProbability: Double = 0
    @Published private(set) var soundManipulationFocus: SoundManipulationFocus?
    @Published private(set) var hotasStaticVisualOverrideHeld = false
    @Published private(set) var effectsChainState: EffectsChainState = .idle
    @Published private(set) var activeEffectsPreset = EffectsChainPreset(chainAName: "Rhythm", chainBName: "Space", bankID: 1)
    @Published private(set) var staticAudioMacroState: StaticAudioMacroState = .neutral
    @Published private(set) var choirFieldState: ChoirFieldState = .neutral
    @Published private(set) var ultrachunkControlFrame: UltrachunkControlFrame = .neutral
    @Published private(set) var ultrachunkDSPState: UltrachunkDSPState = .neutral
    @Published private(set) var ultrachunkGranularity: Double = 0
    @Published private(set) var ultrachunkIntensity: Double = 0
    @Published private(set) var ultrachunkPrimarySampleID: String?
    @Published private(set) var ultrachunkSecondarySampleID: String?
    @Published private(set) var hotasUltrachunkOverlayEnabled = false
    @Published private(set) var dynamicBinManifest: [DynamicBinClip] = []
    @Published private(set) var programProceduralState: ProgramProceduralState = .default()
    @Published private(set) var programAudioState: ProgramAudioState = .default
    @Published private(set) var stateDevelopmentMetrics: StateDevelopmentMetrics = .neutral
    @Published private(set) var activeMLProposal: MLProposal?
    @Published private(set) var activeMLProposalCountdownSeconds: Double?
    @Published private(set) var lastMLProposalDecision: MLProposalDecision?
    @Published private(set) var proposalStructuredLatchActive = false

    @Published private(set) var phoneAudioGateArmed = false
    @Published private(set) var phoneAudioGateCommitted = false
    @Published private(set) var phoneAudioAvailableDevices: [String] = []
    @Published private(set) var phoneAudioActiveVoices: [String: Int] = [:]
    @Published private(set) var phoneAudioZoneOccupancy: [String: Int] = [:]
    @Published private(set) var phoneAudioDeviceHealth: [String: HarnessPhoneAudioPoolStatePayload.DeviceHealth] = [:]
    @Published private(set) var phoneAudioFailoverCount: Int = 0
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
    @Published private(set) var hudTelemetryFrame: HUDTelemetryFrame = .empty
    @Published var masterArmKey: MasterArmKeyState = .safe
    @Published private(set) var abortCoverOpen: Bool = false
    @Published private(set) var lockedTimelineLaneIDs: Set<String> = []
    @Published private(set) var timelineStepPlaybackWindows: [String: DateInterval] = [:]

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
    private let audioRouter = AudioRouter()
    private let sampleMorphEngine = SampleMorphEngine()

    private var importedModelCandidates: [CompiledModelCandidate] = []
    private var previewLoopObserver: NSObjectProtocol?
    private var latchController = OutputLatchController(timeoutSeconds: 8)
    private var latchTimer: Timer?
    private var latchExpiryTimer: DispatchSourceTimer?
    private var scheduledLatchExpiryID: String?
    private var scheduledLatchExpiryAt: Date?
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
    private var midiIngestor: MIDIIngestor?
    private var hotasProfile: ControlProfile = .defaultX56StrictLive
    private var hotasLastKnownGoodProfile: ControlProfile?
    private var hotasMapper: ControlProfileMapper?
    private var hotasInputMultiplexer: InputMultiplexer?
    private var hotasCaptureRole: ControlRole?
    private var hotasCaptureExpectedKinds: Set<ControlSignalKind> = Set(ControlSignalKind.allCases)
    private var hotasCaptureAxisCandidateControlID: String?
    private var hotasCaptureAxisCandidateSamples: Int = 0
    private var hotasCaptureAxisCandidateStrength: Double = 0
    private var hotasCaptureAxisCandidateUpdatedAtMs: TimeInterval = 0
    private var hotasCaptureArmedAtMs: TimeInterval = 0
    private var hotasCaptureBaselineByControlKey: [String: ControlSignal] = [:]
    private var hotasTrainingBackupProfile: ControlProfile?
    private var hotasObservedByControlKey: [String: ControlSignal] = [:]
    private var hotasLastObservationPublishAtMs: TimeInterval = 0
    private var hotasLastSummaryPublishAtMs: TimeInterval = 0
    private var activeChoirMIDINotes: [Int: Int] = [:]
    private var sampleMetadataByID: [String: SampleMetadata] = [:]
    private var sampleLabelByID: [String: String] = [:]
    private var performerProceduralState: ProgramProceduralState = .default()
    private var lastSentProceduralState: ProgramProceduralState?
    private lazy var controlActionRouter = ControlActionRouter(delegate: self)
    private let hudTelemetryStore = HUDTelemetryStore()
    private let cognitiveProposalEngine = CognitiveProposalEngine()
    private var hudTelemetryPumpTimer: Timer?
    private var hudTelemetrySnapshotTaskInFlight = false
    private var routedHOTASActionContext: RoutedHOTASActionContext?
    private var pushDeckEventRouter = PushDeckEventRouter()
    private var trustedPushControllerIDSet: Set<String> = []
    private var pushLastUntrustedStatusAtByController: [String: TimeInterval] = [:]
    private var pushLastPadEchoStatusAt: TimeInterval = 0
    private var pushLastPadLabelsSignature: String = ""
    private var pushActiveChoirPadNotes: [Int: Int] = [:]
    private var pushQuantizedPadWorkItems: [String: DispatchWorkItem] = [:]
    private var hotasStaticSampleAuditionLastAtMs: TimeInterval = 0
    private var hotasStaticSampleAuditionLastValueByLane: [String: Double] = [:]
    private var hotasStaticSampleAuditionLastSampleID: String?
    private var hotasStaticSampleAuditionLastStatusAtMs: TimeInterval = 0
    private var hotasSampleSpaceX: Double = 0.5
    private var hotasSampleSpaceY: Double = 0.5
    private var hotasSampleSpaceZ: Double = 0.5
    private var hotasSampleSpaceDrift: Double = 0
    private var hotasLastRhythmAccentAtMs: TimeInterval = 0
    private var hotasLastSpaceAccentAtMs: TimeInterval = 0
    private var hotasLastPaulstretchAtMs: TimeInterval = 0
    private var hotasLastPaulstretchMorphAtMs: TimeInterval = 0
    private var hotasUltrachunkLastFrameAtMs: TimeInterval = 0
    private var hotasUltrachunkLastRenderAtMs: TimeInterval = 0
    private var hotasUltrachunkLastFrame: UltrachunkControlFrame = .neutral
    private let hotasUltrachunkQualityProfile: UltrachunkQualityProfile = .maxQuality

    private struct RoutedHOTASActionContext {
        let signal: ControlSignal
        let action: ControlAction
        var emittedAppliedEventFromStatus = false
    }

    private enum HOTASSampleSpaceAxis {
        case x
        case y
        case z
    }

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

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func remap01(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return value >= max ? 1 : 0 }
        return clamp01((value - min) / (max - min))
    }

    private static func smoothstep01(_ value: Double) -> Double {
        let t = clamp01(value)
        return t * t * (3 - (2 * t))
    }

    private static func normalizedMilliseconds(_ timestamp: TimeInterval) -> TimeInterval {
        timestamp > 100_000 ? timestamp : timestamp * 1_000
    }

    private static func nowMilliseconds() -> TimeInterval {
        Date().timeIntervalSince1970 * 1_000
    }

    var fixedHarnessLinkURL: String {
        BackendEndpoints.harnessWebSocketURL.absoluteString
    }

    var fixedHealthURL: String {
        BackendEndpoints.healthURL.absoluteString
    }

    var isLinkHealthy: Bool {
        linkState == .online
    }

    var outputRouteReady: Bool {
        switch audioRouteCapability {
        case .quad:
            return true
        case .stereoFallback:
            return allowStereoFallback
        case .unavailable:
            return false
        }
    }

    var audioRouteStatusSummary: String {
        switch audioRouteCapability {
        case .quad:
            return "QUAD READY (\(quadRouteChannelCount)ch)"
        case .stereoFallback:
            return allowStereoFallback
                ? "2CH FALLBACK ACTIVE (\(quadRouteChannelCount)ch)"
                : "2CH AVAILABLE (FALLBACK DISABLED)"
        case .unavailable:
            return "ROUTE NOGO (\(quadRouteChannelCount)ch)"
        }
    }

    var selectedAudioRouteDisplayName: String {
        Self.resolveAudioRouteDisplayName(
            routes: availableAudioRoutes,
            selectedRouteID: selectedAudioRouteID
        )
    }

    func audioRouteMenuLabel(_ route: AudioRoute) -> String {
        var parts: [String] = ["\(route.name)", "\(route.channelCount)ch"]
        if route.isSystemDefault {
            parts.append("SYSTEM")
        }
        return parts.joined(separator: " · ")
    }

    var selectedMIDIInputDisplayName: String {
        Self.resolveMIDIInputDisplayName(
            inputs: availableMIDIInputs,
            selectedInputID: selectedMIDIInputID
        )
    }

    var soundSituationalSnapshot: SoundSituationalSnapshot {
        let nowMs = ConductorHarnessViewModel.nowMilliseconds()

        let modeDerivation = Self.deriveSoundMode(
            engineRunning: engineRunning,
            effectiveOutputMode: effectiveOutputMode,
            choirContextActive: hotasPhoneChoirContextActive,
            phonePoolCount: phoneAudioAvailableDevices.count,
            phoneGateCommitted: phoneAudioGateCommitted
        )

        let importLevel: SoundSignalLevel = {
            if samplePackEntries.isEmpty {
                return .critical
            }
            if samplePackManifestURL == nil {
                return .caution
            }
            return .nominal
        }()

        let ioLevel = Self.deriveSoundIOLevel(audioRouteCapability: audioRouteCapability)

        let target = Self.resolveActiveSoundTarget(
            selectedSampleID: selectedSampleID,
            sampleEntries: samplePackEntries,
            labels: sampleLabelByID,
            choirContextActive: hotasPhoneChoirContextActive,
            activeSampleBank: activeSampleBank,
            activeChoirSampleBank: activeChoirSampleBank
        )
        let focus = soundManipulationFocus
        let stale = Self.isSoundManipulationStale(focus, nowMs: nowMs)

        return SoundSituationalSnapshot(
            banksImport: SoundBankImportState(
                mainBank: activeSampleBank,
                choirBank: activeChoirSampleBank,
                samplePackFile: samplePackFilename(),
                sampleEntryCount: samplePackEntries.count,
                synthPresetFile: synthPresetFilename(),
                choirProfileFile: choirProfileFilename(),
                sampleImportReady: !samplePackEntries.isEmpty,
                level: importLevel
            ),
            modePrimary: modeDerivation.primary,
            modeDetail: modeDerivation.detail,
            modeLevel: modeDerivation.level,
            io: SoundIOState(
                outputRouteName: selectedAudioRouteDisplayName,
                outputRouteSummary: audioRouteStatusSummary,
                midiInputName: selectedMIDIInputDisplayName,
                midiStatus: midiInputStatus,
                hotasStatus: hotasInputStatus,
                pushStatus: pushControlEnabled ? pushLastSignalSummary : "Push OFF",
                level: ioLevel
            ),
            activeTarget: target,
            manipulation: focus,
            manipulationIsStale: stale,
            generatedAt: nowMs
        )
    }

    nonisolated static func resolveAudioRouteDisplayName(routes: [AudioRoute], selectedRouteID: String) -> String {
        if let selected = routes.first(where: { $0.id == selectedRouteID }) {
            let suffix = selected.isSystemDefault ? " · SYSTEM" : ""
            return "\(selected.name) (\(selected.channelCount)ch)\(suffix)"
        }
        if let fallbackDefault = routes.first(where: { $0.isSystemDefault }) {
            return "\(fallbackDefault.name) (\(fallbackDefault.channelCount)ch) · SYSTEM"
        }
        if let first = routes.first {
            return "\(first.name) (\(first.channelCount)ch)"
        }
        return "NO OUTPUT ROUTES"
    }

    nonisolated static func resolveMIDIInputDisplayName(inputs: [MIDIInputOption], selectedInputID: String) -> String {
        if let selected = inputs.first(where: { $0.id == selectedInputID }) {
            return selected.name
        }
        if let first = inputs.first {
            return first.name
        }
        return "NO MIDI INPUTS"
    }

    nonisolated static func deriveSoundMode(
        engineRunning: Bool,
        effectiveOutputMode: EffectiveOutputMode,
        choirContextActive: Bool,
        phonePoolCount: Int,
        phoneGateCommitted: Bool
    ) -> (primary: SoundModePrimary, detail: SoundModeDetail, level: SoundSignalLevel) {
        let primary: SoundModePrimary = choirContextActive ? .phoneChoir : .normal
        let detail: SoundModeDetail = {
            if !engineRunning {
                return .off
            }
            switch effectiveOutputMode {
            case .static:
                return .static
            case .dynamic:
                return .dynamic
            case .interstitial:
                return .inter
            case .off:
                return .off
            }
        }()
        let level: SoundSignalLevel = {
            guard primary == .phoneChoir else { return .nominal }
            if phonePoolCount == 0 {
                return .critical
            }
            return phoneGateCommitted ? .nominal : .caution
        }()
        return (primary, detail, level)
    }

    nonisolated static func deriveSoundIOLevel(audioRouteCapability: AudioRouteCapability) -> SoundSignalLevel {
        switch audioRouteCapability {
        case .quad:
            return .nominal
        case .stereoFallback:
            return .caution
        case .unavailable:
            return .critical
        }
    }

    nonisolated static func resolveActiveSoundTarget(
        selectedSampleID: String,
        sampleEntries: [String: URL],
        labels: [String: String],
        choirContextActive: Bool,
        activeSampleBank: Int,
        activeChoirSampleBank: Int
    ) -> ActiveSoundTarget {
        let domain: ActiveSoundBankDomain = choirContextActive ? .choir : .main
        let bank = domain == .choir ? activeChoirSampleBank : activeSampleBank

        let resolvedID: String = {
            if sampleEntries[selectedSampleID] != nil {
                return selectedSampleID
            }
            return sampleEntries.keys.sorted().first ?? "none"
        }()

        guard let sampleURL = sampleEntries[resolvedID] else {
            return ActiveSoundTarget(
                sampleID: "none",
                label: "none",
                fileName: "none",
                bankDomain: domain,
                bank: bank
            )
        }

        let label: String = {
            if let curated = labels[resolvedID]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !curated.isEmpty {
                return curated
            }
            return sampleURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        }()

        return ActiveSoundTarget(
            sampleID: resolvedID,
            label: label,
            fileName: sampleURL.lastPathComponent,
            bankDomain: domain,
            bank: bank
        )
    }

    nonisolated static func isSoundManipulationStale(
        _ focus: SoundManipulationFocus?,
        nowMs: TimeInterval,
        thresholdMs: TimeInterval = SoundSituationalSnapshot.manipulationStaleThresholdMs
    ) -> Bool {
        guard let focus else { return true }
        return (nowMs - focus.updatedAt) > thresholdMs
    }

    static let coreMLSearchDirectoryDefaultsKey = "coreMLModelSearchDirectoryOverride"

    static func loadCoreMLSearchDirectoryOverride() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: coreMLSearchDirectoryDefaultsKey),
              !raw.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    static func buildCoreMLSearchDirectories(overrideURL: URL?) -> [URL] {
        var extras: [URL] = []
        if let overrideURL {
            extras.append(overrideURL)
        }
        return CoreMLModelLocator.defaultSearchDirectories(additionalDirectories: extras)
    }

    init() {
        let preferredModelName = ProcessInfo.processInfo.environment["CONDUCTOR_COREML_MODEL_NAME"]
        let overrideURL = Self.loadCoreMLSearchDirectoryOverride()
        let searchDirectories = Self.buildCoreMLSearchDirectories(overrideURL: overrideURL)
        let scoringModel = CoreMLScoringModelAdapter(
            preferredModelName: preferredModelName,
            searchDirectories: searchDirectories
        )
        self.scoringModel = scoringModel
        self.modelSearchOverridePath = overrideURL?.path
        self.modelSearchPaths = searchDirectories.map { $0.path }
        self.textEngine = TextSelectionEngine(model: scoringModel)
        configurePreviewPlayerForPerformanceMode()
        let proceduralSeed = Int(Date().timeIntervalSince1970)
        performerProceduralState = .default(seed: proceduralSeed)
        programProceduralState = performerProceduralState
        startHUDTelemetryPump()

        websocket.onMessage = { [weak self] text in
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
                self?.publishProceduralState(force: true)
                self?.publishPushPadLabelsForActiveMainBank(force: true)
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
            MainActor.assumeIsolated {
                self?.ingestAudioFeatures(features)
            }
        }

        refreshModelCatalog()
        applyModelHealth(scoringModel.currentHealth())
        syncLatchState(latchController.snapshot, now: Date())
        startLatchTimer()
        refreshSetupInventory()
        loadControlProfileDocument()
        refreshHOTASActivation()
        refreshQuadRouteStatus()
        loadMediaManifest()
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
        websocket.start(url: BackendEndpoints.harnessWebSocketURL)
    }

    deinit {
        if let observer = previewLoopObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        latchTimer?.invalidate()
        latchExpiryTimer?.setEventHandler {}
        latchExpiryTimer?.cancel()
        latchExpiryTimer = nil
        audioFeaturePumpTimer?.invalidate()
        hudTelemetryPumpTimer?.invalidate()
        hudTelemetryPumpTimer = nil
        abortCoverTimer?.invalidate()
        midiIngestor?.stop()
        midiIngestor = nil
        hotasInputMultiplexer?.stop()
        hotasInputMultiplexer = nil
        for work in pushQuantizedPadWorkItems.values {
            work.cancel()
        }
        pushQuantizedPadWorkItems.removeAll()
        pushActiveChoirPadNotes.removeAll()
        quadAudioEngine.stop()
        websocket.stop()
    }

    // MARK: - Status helpers

    private func startHUDTelemetryPump() {
        guard hudTelemetryPumpTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.hudTelemetrySnapshotTaskInFlight else { return }
                self.hudTelemetrySnapshotTaskInFlight = true
                let snapshot = await self.hudTelemetryStore.snapshot(maxEvents: 160)
                defer {
                    self.hudTelemetrySnapshotTaskInFlight = false
                }
                if snapshot != self.hudTelemetryFrame {
                    self.hudTelemetryFrame = snapshot
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hudTelemetryPumpTimer = timer
    }

    private func hudSeverity(for statusEvent: StatusLineEvent) -> HUDEventSeverity {
        if statusEvent.severity == .error {
            return .error
        }
        let lowered = statusEvent.message.lowercased()
        if lowered.contains("blocked") {
            return .block
        }
        return .apply
    }

    private func recordAppliedHUDStatusFromActionContext(_ event: StatusLineEvent) {
        guard var context = routedHOTASActionContext else { return }
        let severity = hudSeverity(for: event)
        let lowered = event.message.lowercased()
        let blockReason = lowered.contains("blocked") ? event.message : nil
        let capturedContext = context
        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestApplied(
                signal: capturedContext.signal,
                action: capturedContext.action,
                severity: severity,
                outcome: event.severity.rawValue.uppercased(),
                blockReason: blockReason,
                detail: event.message
            )
        }
        context.emittedAppliedEventFromStatus = true
        routedHOTASActionContext = context
    }

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
        recordAppliedHUDStatusFromActionContext(event)
    }

    private func proposalContext(nowMs: TimeInterval) -> CognitiveProposalContext {
        CognitiveProposalContext(
            nowMs: nowMs,
            engineRunning: engineRunning,
            outputRouteReady: outputRouteReady,
            linkHealthy: isLinkHealthy,
            isLatchArmed: isLatchArmed,
            masterArmArmed: masterArmKey == .armed,
            pendingOutputModeArmed: pendingOutputMode != nil,
            activeSampleBank: activeSampleBank,
            activeChoirSampleBank: activeChoirSampleBank,
            selectedSampleID: selectedSampleID == "default" ? nil : selectedSampleID,
            effectsState: effectsChainState,
            proceduralState: programProceduralState,
            latestAudioFeatures: latestAudioFeaturesRaw
        )
    }

    private func proposalActionLabel(for action: ControlAction) -> String {
        switch action {
        case .acceptActiveProposal:
            return "proposal_accept"
        case .startEngine:
            return "engine_start"
        case .stopEngine:
            return "engine_stop"
        case .patchVector:
            return "patch_vector"
        case .armOutputMode:
            return "arm_mode"
        case .armTransportLane:
            return "arm_lane"
        case .queueTimelineStep:
            return "queue_timeline"
        case .setDynamicBinSelection:
            return "dynamic_bin"
        case .setCutCadence:
            return "cut_cadence"
        case .setCompositorBlend:
            return "compositor_blend"
        case .setStaticVisualOverrideHold(let held):
            return held ? "static_visual_clutch_on" : "static_visual_clutch_off"
        case .setStaticSampleMorph:
            return "static_sample_morph"
        case .setStaticArticulation:
            return "static_articulation"
        case .setStaticTimbre:
            return "static_timbre"
        case .setStaticTextureSend:
            return "static_texture_send"
        case .setChoirFieldSpread:
            return "choir_field_spread"
        case .setChoirFieldDepth:
            return "choir_field_depth"
        case .setChoirFieldDetune:
            return "choir_field_detune"
        case .setTextProbability:
            return "text_probability"
        case .setStrictLooseBlend:
            return "strict_loose_blend"
        case .setVisualVariance:
            return "visual_variance"
        case .toggleUltrachunkOverlay:
            return "ultrachunk_overlay_toggle"
        case .contextualTake:
            return "contextual_take"
        case .setMasterArm(let armed):
            return armed ? "master_arm" : "master_safe"
        case .phoneGateTake:
            return "phone_take"
        case .phoneGateGo:
            return "phone_go"
        case .phoneGateSafe:
            return "phone_safe"
        case .togglePreviewPlayback:
            return "preview_toggle"
        case .setSampleBank(_, let domain):
            return "sample_bank_\(domain.rawValue)"
        case .setEffectsChain(let chain, let active, _):
            return "fx_\(chain.rawValue)_\(active ? "on" : "off")"
        case .triggerPhoneChoirNoteOn:
            return "choir_note_on"
        case .triggerPhoneChoirNoteOff:
            return "choir_note_off"
        case .stopAllPhoneAudio:
            return "choir_stop_all"
        case .setPhoneChoirContextActive(let active):
            return active ? "choir_ctx_on" : "choir_ctx_off"
        }
    }

    private func tickCognitiveProposalEngine(nowMs: TimeInterval) {
        let result = cognitiveProposalEngine.tick(context: proposalContext(nowMs: nowMs))
        stateDevelopmentMetrics = result.metrics

        if activeMLProposal?.id != result.activeProposal?.id {
            activeMLProposal = result.activeProposal
        } else if let proposal = result.activeProposal {
            activeMLProposal = proposal
        }

        if let proposal = activeMLProposal {
            activeMLProposalCountdownSeconds = max(0, (proposal.expiresAt - nowMs) / 1_000)
        } else {
            activeMLProposalCountdownSeconds = nil
        }

        if let lifecycle = result.lifecycleEvent {
            handleProposalLifecycleEvent(lifecycle)
        }

        refreshProgramAudioState(nowMs: nowMs)
    }

    private func handleProposalLifecycleEvent(_ event: CognitiveProposalLifecycleEvent) {
        let severity: StatusLineSeverity
        let hudSeverity: HUDEventSeverity
        let outcome: String

        switch event.decision {
        case .accepted:
            severity = .success
            hudSeverity = .apply
            outcome = "ACCEPTED"
        case .expired:
            severity = .warn
            hudSeverity = .block
            outcome = "EXPIRED"
        case .rejected:
            severity = .info
            hudSeverity = .act
            outcome = "STAGED"
        case .blocked:
            severity = .warn
            hudSeverity = .block
            outcome = "BLOCKED"
        }

        let laneLabel = event.proposal.lane.rawValue.replacingOccurrences(of: "_", with: "/").uppercased()
        pushStatus(StatusLineEvent(
            message: "ML \(laneLabel) \(outcome): \(event.message)",
            severity: severity,
            timestamp: Date()
        ))

        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestSystem(
                stage: .applied,
                severity: hudSeverity,
                controlID: "ml:proposal",
                semanticAction: "proposal_\(event.proposal.lane.rawValue)",
                outcome: outcome,
                detail: event.proposal.rationale
            )
        }
    }

    private func refreshProgramAudioState(nowMs: TimeInterval) {
        let clampedPoolRatio = ConductorHarnessViewModel.clamp01(Double(phoneAudioActiveVoices.count) / 24.0)
        let chainPressure = max(effectsChainState.chainAIntensity, effectsChainState.chainBIntensity)
        let densityEstimate = ConductorHarnessViewModel.clamp01(
            (latestAudioFeaturesRaw.transientDensity * 0.55)
                + (latestAudioFeaturesRaw.flux * 0.3)
                + (clampedPoolRatio * 0.15)
        )

        let stems: [AudioStemFeatureFrame] = [
            AudioStemFeatureFrame(
                stem: .master,
                rms: latestAudioFeaturesRaw.rms,
                spectralCentroid: latestAudioFeaturesRaw.spectralCentroid,
                flux: latestAudioFeaturesRaw.flux,
                transientDensity: latestAudioFeaturesRaw.transientDensity
            ),
            AudioStemFeatureFrame(
                stem: .mainSamples,
                rms: ConductorHarnessViewModel.clamp01(latestAudioFeaturesRaw.rms * 0.82),
                spectralCentroid: latestAudioFeaturesRaw.spectralCentroid,
                flux: ConductorHarnessViewModel.clamp01(latestAudioFeaturesRaw.flux * 0.78),
                transientDensity: ConductorHarnessViewModel.clamp01(latestAudioFeaturesRaw.transientDensity * 0.72)
            ),
            AudioStemFeatureFrame(
                stem: .synthAmbient,
                rms: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.rms * 0.46) + (chainPressure * 0.21)),
                spectralCentroid: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.spectralCentroid * 0.78) + 0.08),
                flux: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.flux * 0.38) + (chainPressure * 0.22)),
                transientDensity: ConductorHarnessViewModel.clamp01(latestAudioFeaturesRaw.transientDensity * 0.42)
            ),
            AudioStemFeatureFrame(
                stem: .choir,
                rms: clampedPoolRatio,
                spectralCentroid: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.spectralCentroid * 0.65) + 0.1),
                flux: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.flux * 0.5) + (clampedPoolRatio * 0.24)),
                transientDensity: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.transientDensity * 0.44) + (clampedPoolRatio * 0.3))
            ),
            AudioStemFeatureFrame(
                stem: .ipadIn,
                rms: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.rms * 0.36) + (stateDevelopmentMetrics.intensityTrend * 0.2)),
                spectralCentroid: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.spectralCentroid * 0.7) + 0.06),
                flux: ConductorHarnessViewModel.clamp01((latestAudioFeaturesRaw.flux * 0.42) + (stateDevelopmentMetrics.repeatability * 0.16)),
                transientDensity: ConductorHarnessViewModel.clamp01(latestAudioFeaturesRaw.transientDensity * 0.36)
            )
        ]

        let previous = programAudioState
        let changed = previous.activeSampleBank != activeSampleBank
            || previous.activeChoirSampleBank != activeChoirSampleBank
            || previous.choirContextActive != hotasPhoneChoirContextActive
            || previous.phoneGateCommitted != phoneAudioGateCommitted
            || previous.effects != effectsChainState
            || previous.staticMacros != staticAudioMacroState
            || previous.choirField != choirFieldState
            || previous.staticVisualOverrideHeld != hotasStaticVisualOverrideHeld
            || previous.master != latestAudioFeaturesRaw
            || previous.stems != stems
            || previous.activeProposalID != activeMLProposal?.id
            || previous.structuredLatchActive != proposalStructuredLatchActive
            || previous.ultrachunkFrame != ultrachunkControlFrame
            || previous.ultrachunkDSPState != ultrachunkDSPState
            || previous.ultrachunkPrimarySampleID != ultrachunkPrimarySampleID
            || previous.ultrachunkSecondarySampleID != ultrachunkSecondarySampleID
            || abs(previous.estimatedDensity - densityEstimate) > 0.01

        let epoch = changed ? previous.epoch + 1 : previous.epoch
        if !changed, abs(previous.updatedAt - nowMs) < 300 {
            return
        }

        programAudioState = ProgramAudioState(
            epoch: epoch,
            updatedAt: nowMs,
            activeSampleBank: activeSampleBank,
            activeChoirSampleBank: activeChoirSampleBank,
            choirContextActive: hotasPhoneChoirContextActive,
            phoneGateCommitted: phoneAudioGateCommitted,
            estimatedDensity: densityEstimate,
            effects: effectsChainState,
            master: latestAudioFeaturesRaw,
            stems: stems,
            activeProposalID: activeMLProposal?.id,
            structuredLatchActive: proposalStructuredLatchActive,
            staticMacros: staticAudioMacroState,
            choirField: choirFieldState,
            staticVisualOverrideHeld: hotasStaticVisualOverrideHeld,
            ultrachunkFrame: ultrachunkControlFrame,
            ultrachunkDSPState: ultrachunkDSPState,
            ultrachunkPrimarySampleID: ultrachunkPrimarySampleID,
            ultrachunkSecondarySampleID: ultrachunkSecondarySampleID
        )
    }

    private func clearProposalStructuredLatchIfNeeded(_ reason: String) {
        guard proposalStructuredLatchActive else { return }
        proposalStructuredLatchActive = false
        pushStatus(StatusLineEvent(
            message: "ML audio latch cleared (\(reason))",
            severity: .info,
            timestamp: Date()
        ))
    }

    private func resetCognitiveProposalState(reason: String) {
        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        cognitiveProposalEngine.reset(nowMs: nowMs)
        activeMLProposal = nil
        activeMLProposalCountdownSeconds = nil
        proposalStructuredLatchActive = false
        stateDevelopmentMetrics = .neutral
        lastMLProposalDecision = nil
        refreshProgramAudioState(nowMs: nowMs)
        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestSystem(
                stage: .applied,
                severity: .info,
                controlID: "ml:proposal",
                semanticAction: "proposal_reset",
                outcome: "RESET",
                detail: reason
            )
        }
    }

    // MARK: - Master arm key

    func toggleMasterArmKey() {
        let next: MasterArmKeyState = (masterArmKey == .safe) ? .armed : .safe
        setMasterArmKey(next, source: "panel")
    }

    func setMasterArmFromControl(_ isArmed: Bool) {
        let target: MasterArmKeyState = isArmed ? .armed : .safe
        setMasterArmKey(target, source: "HOTAS")
    }

    private func setMasterArmKey(_ key: MasterArmKeyState, source: String) {
        guard masterArmKey != key else { return }
        masterArmKey = key
        let now = Date()
        if key == .armed {
            pushStatus(StatusLineEvent(
                message: "\(source) set MASTER ARM",
                severity: .warn,
                timestamp: now
            ))
        } else {
            pushStatus(StatusLineEvent(
                message: "\(source) set MASTER SAFE",
                severity: .info,
                timestamp: now
            ))
        }
    }

    var canFireWithMasterArm: Bool {
        canFireGO && masterArmKey == .armed && isLinkHealthy && outputRouteReady
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

    func canArmTimelineStep(_ laneId: String) -> Bool {
        guard isLinkHealthy, engineRunning else { return false }
        guard !lockedTimelineLaneIDs.contains(laneId) else { return false }
        guard let plan = timelineStepPlan(for: laneId) else { return false }
        guard laneMediaURL(for: laneId) != nil else { return false }
        return canApply(action: .jump, target: plan.targetState)
    }

    func canTakeArmedTimelineStep() -> Bool {
        guard pendingOutputMode == .static, let laneId = pendingLaneId else { return false }
        guard timelineStepPlan(for: laneId) != nil else { return false }
        guard isLinkHealthy, engineRunning else { return false }
        return masterArmKey == .armed
    }

    func timelineStepProgress(for laneId: String, at now: Date = Date()) -> Double {
        if let interval = timelineStepPlaybackWindows[laneId] {
            let duration = max(0.001, interval.duration)
            let elapsed = now.timeIntervalSince(interval.start)
            return max(0, min(1, elapsed / duration))
        }
        if lockedTimelineLaneIDs.contains(laneId) {
            return 1.0
        }
        return 0.0
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
        performerProceduralState.performerVector = vector
        programProceduralState.performerVector = vector

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

        guard outputRouteReady else {
            let message: String
            switch audioRouteCapability {
            case .stereoFallback:
                message = "GO blocked: stereo route detected. Enable 2ch fallback in SETUP"
            case .unavailable:
                message = "GO blocked: no usable audio route (requires >=2ch)"
            case .quad:
                message = "GO blocked: audio route unavailable"
            }
            pushStatus(StatusLineEvent(
                message: message,
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
        do {
            let route = try quadAudioEngine.start()
            engineRunning = true
            applyRouteStatus(route, emitStatus: true)
        } catch {
            engineRunning = false
            resetAudioRouteStatus()
            pushStatus(StatusLineEvent(
                message: "Audio engine failed to start: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
            return
        }

        phoneAudioGateArmed = false
        phoneAudioGateCommitted = false
        phoneAudioZoneOccupancy.removeAll()
        phoneAudioDeviceHealth.removeAll()
        phoneAudioFailoverCount = 0
        hotasPhoneChoirContextActive = false
        activeChoirMIDINotes.removeAll()
        effectsChainState = .idle
        hotasStaticVisualOverrideHeld = false
        staticAudioMacroState = .neutral
        resetHOTASStaticSampleAuditionState()
        choirFieldState = .neutral
        updateEffectsPresetForActiveBank()
        quadAudioEngine.setChoirFieldState(choirFieldState)
        quadAudioEngine.setStaticMacroFrame(EffectsMacroFrame(
            chainAIntensity: 0,
            chainBIntensity: 0,
            articulation: staticAudioMacroState.articulation,
            timbre: staticAudioMacroState.timbre,
            textureSend: staticAudioMacroState.textureSend
        ))
        publishPhoneAudioPoolState()
        startAudioFeaturePump()
        resetCognitiveProposalState(reason: "engine_start")

        committedOutputMode = .off
        effectiveOutputMode = .interstitial
        activeStaticLaneId = nil
        timelineStepPlaybackWindows.removeAll()
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

    func startEngineFromControl() {
        startEngine()
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

        cancelPendingPushQuantizedPadWork()
        cancelSequenceWork()
        engineRunning = false
        quadAudioEngine.stop()
        stopAudioFeaturePump()
        resetAudioRouteStatus()
        phoneAudioGateArmed = false
        phoneAudioGateCommitted = false
        phoneAudioZoneOccupancy.removeAll()
        phoneAudioDeviceHealth.removeAll()
        phoneAudioFailoverCount = 0
        hotasPhoneChoirContextActive = false
        activeChoirMIDINotes.removeAll()
        effectsChainState = .idle
        hotasStaticVisualOverrideHeld = false
        staticAudioMacroState = .neutral
        resetHOTASStaticSampleAuditionState()
        choirFieldState = .neutral
        updateEffectsPresetForActiveBank()
        stopMIDIInput(notify: false)
        publishPhoneAudioPoolState()
        ingestAudioFeatures(.zero, forceUI: true)
        publishLatestAudioFeatures(forceZero: true)
        resetCognitiveProposalState(reason: "engine_stop")
        committedOutputMode = .off
        activeStaticLaneId = nil
        timelineStepPlaybackWindows.removeAll()
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

    func stopEngineFromControl() {
        stopEngine()
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

    func takeArmedTimelineStep() {
        guard pendingOutputMode == .static,
              let laneId = pendingLaneId,
              timelineStepPlan(for: laneId) != nil else {
            pushStatus(StatusLineEvent(
                message: "TIMELINE TAKE blocked: arm a timeline chip first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        fireOutputGO()
    }

    func queueTimelineStepFromControl(_ laneId: String) {
        queueTimelineStep(laneId: laneId)
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
        cancelPendingPushQuantizedPadWork()
        cancelSequenceWork()
        engineRunning = false
        quadAudioEngine.stop()
        stopAudioFeaturePump()
        resetAudioRouteStatus()
        phoneAudioGateArmed = false
        phoneAudioGateCommitted = false
        hotasPhoneChoirContextActive = false
        effectsChainState = .idle
        resetHOTASStaticSampleAuditionState()
        stopMIDIInput(notify: false)
        publishPhoneAudioPoolState()
        ingestAudioFeatures(.zero, forceUI: true)
        publishLatestAudioFeatures(forceZero: true)
        resetCognitiveProposalState(reason: "show_reset")
        committedOutputMode = .off
        activeStaticLaneId = nil
        effectiveOutputMode = .off
        timelineStepPlaybackWindows.removeAll()
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
        applyRouteStatus(status)
        publishPhoneAudioPoolState()
    }

    func refreshSetupInventory() {
        let routes = audioRouter.availableRoutes()
        if availableAudioRoutes != routes {
            availableAudioRoutes = routes
        }
        if !routes.contains(where: { $0.id == selectedAudioRouteID }) {
            selectedAudioRouteID = routes.first(where: { $0.isSystemDefault })?.id
                ?? routes.first?.id
                ?? "default-output"
        }

        let midiInputs = CoreMIDIEventSource.availableInputs()
            .map { MIDIInputOption(id: $0.id, name: $0.name) }
        if availableMIDIInputs != midiInputs {
            availableMIDIInputs = midiInputs
        }
        if !midiInputs.contains(where: { $0.id == selectedMIDIInputID }) {
            selectedMIDIInputID = midiInputs.first?.id ?? ""
        }
        refreshHOTASActivation()
    }

    func applySetupConfiguration() {
        refreshSetupInventory()
        if !selectedAudioRouteID.isEmpty {
            do {
                let applied = try audioRouter.setDefaultOutputRoute(routeID: selectedAudioRouteID)
                if applied {
                    pushStatus(StatusLineEvent(
                        message: "Audio output set: \(selectedAudioRouteDisplayName)",
                        severity: .success,
                        timestamp: Date()
                    ))
                }
            } catch {
                pushStatus(StatusLineEvent(
                    message: "Audio output selection failed: \(error.localizedDescription)",
                    severity: .warn,
                    timestamp: Date()
                ))
            }
        }
        refreshSetupInventory()
        if engineRunning {
            if ensureScoringEngineReady(operation: "Audio output apply") {
                quadAudioEngine.stop()
                if ensureScoringEngineReady(operation: "Audio output restart") {
                    quadAudioEngine.setChoirFieldState(choirFieldState)
                    quadAudioEngine.setEffectsChainState(chain: .a, active: effectsChainState.chainAActive, intensity: effectsChainState.chainAIntensity)
                    quadAudioEngine.setEffectsChainState(chain: .b, active: effectsChainState.chainBActive, intensity: effectsChainState.chainBIntensity)
                    applyStaticMacroAudioState()
                }
            }
        }
        refreshQuadRouteStatus()
        refreshHOTASActivation()
    }

    func testSelectedAudioOutput() {
        guard let sampleURL = sampleURLForSelectedID() else {
            pushStatus(StatusLineEvent(
                message: "AUDIO TEST blocked: load sample pack first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let startedTemporarily = !quadAudioEngine.isRunning
        do {
            if startedTemporarily {
                _ = try quadAudioEngine.start()
                applyRouteStatus(quadAudioEngine.routeStatus())
            }

            try quadAudioEngine.triggerSample(url: sampleURL, gain: 0.62)
            pushStatus(StatusLineEvent(
                message: "AUDIO TEST: \(sampleURL.lastPathComponent)",
                severity: .success,
                timestamp: Date()
            ))
        } catch {
            pushStatus(StatusLineEvent(
                message: "AUDIO TEST failed: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
        }

        if startedTemporarily && !engineRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self else { return }
                guard !self.engineRunning else { return }
                self.quadAudioEngine.stop()
                self.refreshQuadRouteStatus()
            }
        }
    }

    func updatePushControlEnabled(_ enabled: Bool) {
        guard pushControlEnabled != enabled else { return }
        pushControlEnabled = enabled
        persistControlProfileDocument()
        pushStatus(StatusLineEvent(
            message: enabled ? "Push control lane enabled" : "Push control lane disabled",
            severity: .info,
            timestamp: Date()
        ))
    }

    func isPushControllerTrusted(_ controllerID: String) -> Bool {
        trustedPushControllerIDSet.contains(controllerID)
    }

    func setPushControllerTrusted(_ controllerID: String, trusted: Bool) {
        let normalized = controllerID.lowercased()
        guard !normalized.isEmpty else { return }
        if trusted {
            trustedPushControllerIDSet.insert(normalized)
        } else {
            trustedPushControllerIDSet.remove(normalized)
        }
        pushTrustedControllerIDs = trustedPushControllerIDSet.sorted()
        persistControlProfileDocument()
        pushStatus(StatusLineEvent(
            message: trusted ? "Push controller trusted: \(normalized.prefix(8))…" : "Push controller untrusted: \(normalized.prefix(8))…",
            severity: .info,
            timestamp: Date()
        ))
    }

    func armMIDIInput() {
        refreshSetupInventory()
        guard !selectedMIDIInputID.isEmpty else {
            pushStatus(StatusLineEvent(
                message: "MIDI arm blocked: no MIDI input source found",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let source = CoreMIDIEventSource(sourceID: selectedMIDIInputID)
        let ingestor = MIDIIngestor(source: source) { [weak self] patch in
            Task { @MainActor in
                self?.patchVector(patch)
            }
        }
        ingestor.start()

        midiIngestor?.stop()
        midiIngestor = ingestor
        midiInputActive = true
        let sourceLabel = availableMIDIInputs.first(where: { $0.id == selectedMIDIInputID })?.name
            ?? selectedMIDIInputID
        midiInputStatus = "MIDI IN: \(sourceLabel)"
        pushStatus(StatusLineEvent(
            message: "MIDI input armed: \(sourceLabel)",
            severity: .success,
            timestamp: Date()
        ))
    }

    func stopMIDIInput(notify: Bool = true) {
        midiIngestor?.stop()
        midiIngestor = nil
        midiInputActive = false
        midiInputStatus = "MIDI OFF"
        if notify {
            pushStatus(StatusLineEvent(
                message: "MIDI input disarmed",
                severity: .info,
                timestamp: Date()
            ))
        }
    }

    private func applyRouteStatus(_ status: QuadRouteStatus, emitStatus: Bool = false) {
        quadRouteChannelCount = status.channelCount
        quadRouteReady = status.quadReady

        switch status.mode {
        case .quad:
            audioRouteCapability = .quad
        case .stereoFallback:
            audioRouteCapability = .stereoFallback
        case .unavailable:
            audioRouteCapability = .unavailable
        }

        guard emitStatus else { return }

        switch audioRouteCapability {
        case .quad:
            pushStatus(StatusLineEvent(
                message: "Quad route ready (\(status.channelCount)ch)",
                severity: .success,
                timestamp: Date()
            ))
        case .stereoFallback:
            if allowStereoFallback {
                pushStatus(StatusLineEvent(
                    message: "Stereo fallback active (\(status.channelCount)ch). Show controls remain enabled.",
                    severity: .warn,
                    timestamp: Date()
                ))
            } else {
                pushStatus(StatusLineEvent(
                    message: "Stereo route detected (\(status.channelCount)ch), but fallback is disabled in SETUP.",
                    severity: .warn,
                    timestamp: Date()
                ))
            }
        case .unavailable:
            pushStatus(StatusLineEvent(
                message: "Audio route NOGO (\(status.channelCount)ch). Requires >=2ch output",
                severity: .warn,
                timestamp: Date()
            ))
        }
    }

    private func resetAudioRouteStatus() {
        quadRouteReady = false
        quadRouteChannelCount = 0
        audioRouteCapability = .unavailable
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
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
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
        guard outputRouteReady else {
            pushStatus(StatusLineEvent(
                message: "PHONE AUDIO GO blocked: audio route not ready",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }
        phoneAudioGateCommitted = true
        publishPhoneAudioPoolState()
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
        pushStatus(StatusLineEvent(
            message: "PHONE AUDIO gate committed (GO)",
            severity: .success,
            timestamp: Date()
        ))
    }

    func safePhoneAudioGate() {
        phoneAudioGateArmed = false
        phoneAudioGateCommitted = false
        activeChoirMIDINotes.removeAll()
        publishPhoneAudioPoolState()
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
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
        guard ensureScoringEngineReady(operation: "SAMPLE") else {
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
            recordSoundManipulationFocus(
                lane: "SAMPLE TRIGGER",
                value: 0.34,
                controlIDHint: "sample:manual",
                sourceHint: "MANUAL"
            )
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
        triggerPhoneChoirNoteOn(note: mapChoirMIDINote(choirNote), velocity: 0.84)
    }

    func triggerPhoneChoirNoteOn(note: Int, velocity: Double) {
        guard guardPhoneAudioDispatchReady(label: "CHOIR NOTE ON") else { return }
        let clampedNote = min(127, max(0, note))
        let clampedVelocity = min(1, max(0, velocity))
        recordSoundManipulationFocus(
            lane: "CHOIR NOTE ON \(clampedNote)",
            value: clampedVelocity,
            controlIDHint: "phone:note_on",
            sourceHint: "CHOIR"
        )
        let command = makePhoneCommand(
            kind: .noteOn,
            note: clampedNote,
            velocity: clampedVelocity,
            gain: 0.34
        )
        dispatchPhoneAudioCommand(command, label: "CHOIR NOTE ON")
    }

    func triggerPhoneChoirNoteOff() {
        triggerPhoneChoirNoteOff(note: mapChoirMIDINote(choirNote))
    }

    func triggerPhoneChoirNoteOff(note: Int) {
        guard guardPhoneAudioDispatchReady(label: "CHOIR NOTE OFF") else { return }
        let clampedNote = min(127, max(0, note))
        let command = makePhoneCommand(
            kind: .noteOff,
            note: clampedNote
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
        recordSoundManipulationFocus(
            lane: "PHONE SAMPLE",
            value: 0.34,
            controlIDHint: "phone:sample",
            sourceHint: "MANUAL"
        )
        let command = makePhoneCommand(
            kind: .sampleTrigger,
            sampleId: sampleID,
            gain: 0.34
        )
        dispatchPhoneAudioCommand(command, label: "PHONE SAMPLE")
    }

    func stopAllPhoneAudio() {
        quadAudioEngine.stopAmbientNoise()
        activeChoirMIDINotes.removeAll()
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
        let priority: String
        switch kind {
        case .noteOn, .noteOff:
            priority = "high"
        case .sampleTrigger:
            priority = "medium"
        case .ambientNoise:
            priority = "low"
        case .stopAll:
            priority = "high"
        }
        return HarnessPhoneAudioCommandPayload(
            commandId: "cmd-\(Int(issuedAt))-\(phoneCommandSequence)",
            kind: kind,
            targetHashedIds: resolvedPhoneTargets(),
            note: note,
            velocity: velocity,
            sampleId: sampleId,
            gain: gain,
            seed: seed,
            renderHints: .init(
                detuneCents: (choirFieldState.detune - 0.5) * 80,
                grainMix: choirFieldState.depth,
                motionEnergy: latestAudioFeaturesRaw.flux,
                priority: priority
            ),
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
        guard outputRouteReady else {
            pushStatus(StatusLineEvent(
                message: "\(label) blocked: audio route not ready",
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
        tickCognitiveProposalEngine(nowMs: ConductorHarnessViewModel.nowMilliseconds())

        // During latch windows we prioritize TAKE/GO responsiveness over
        // metering repaint cadence. Transport still publishes from raw.
        if isLatchArmed && !forceUI {
            return
        }

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
            // Backward-compatible field name. Value reflects route readiness,
            // including stereo fallback when enabled.
            quadRouteReady: outputRouteReady,
            availableDevices: phoneAudioAvailableDevices,
            activeVoices: phoneAudioActiveVoices,
            zoneOccupancy: phoneAudioZoneOccupancy,
            deviceHealth: phoneAudioDeviceHealth,
            failoverCount: phoneAudioFailoverCount,
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
            let resolved = try resolveSamplePackEntries(from: selectedURL)
            samplePackManifestURL = selectedURL
            samplePackEntries = resolved.entries
            sampleMetadataByID = resolved.metadata
            sampleLabelByID = resolved.labels
            if let firstID = resolved.entries.keys.sorted().first {
                selectedSampleID = firstID
            }
            updateEffectsPresetForActiveBank()
            applyStaticSampleMorphSelection()
            publishPushPadLabelsForActiveMainBank(force: true)
            saveMediaManifest()
            pushStatus(StatusLineEvent(
                message: "Loaded sample pack (\(resolved.entries.count) entries)",
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

    func selectedSampleDisplayLabel() -> String {
        guard let sampleID = resolvedSelectedSampleID() else {
            return "none"
        }
        return sampleDisplayLabel(for: sampleID)
    }

    func selectedSampleFileName() -> String {
        guard let sampleID = resolvedSelectedSampleID(),
              let sampleURL = samplePackEntries[sampleID] else {
            return "none"
        }
        return sampleURL.lastPathComponent
    }

    private func resolvedSelectedSampleID() -> String? {
        if samplePackEntries[selectedSampleID] != nil {
            return selectedSampleID
        }
        return samplePackEntries.keys.sorted().first
    }

    private func sampleDisplayLabel(for sampleID: String) -> String {
        if let curated = sampleLabelByID[sampleID]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !curated.isEmpty {
            return curated
        }
        if let sampleURL = samplePackEntries[sampleID] {
            return sampleURL
                .deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
        }
        return sampleID
    }

    private func resolvedActiveSoundTarget() -> ActiveSoundTarget {
        let domain: ActiveSoundBankDomain = hotasPhoneChoirContextActive ? .choir : .main
        let bank = domain == .choir ? activeChoirSampleBank : activeSampleBank
        guard let sampleID = resolvedSelectedSampleID() else {
            return ActiveSoundTarget(
                sampleID: "none",
                label: "none",
                fileName: "none",
                bankDomain: domain,
                bank: bank
            )
        }
        let label = sampleDisplayLabel(for: sampleID)
        let fileName = samplePackEntries[sampleID]?.lastPathComponent ?? "none"
        return ActiveSoundTarget(
            sampleID: sampleID,
            label: label,
            fileName: fileName,
            bankDomain: domain,
            bank: bank
        )
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

    private func mainBankSampleIDs(for bank: Int) -> [String] {
        let configured = hotasProfile.sampleBanks
            .sampleIDs(for: bank, domain: .main)
            .filter { samplePackEntries[$0] != nil }
        if !configured.isEmpty {
            return configured
        }

        let prefix = "main_b\(min(3, max(1, bank)))_"
        let inferred = samplePackEntries.keys
            .filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
            .sorted()
        if !inferred.isEmpty {
            return inferred
        }

        return samplePackEntries.keys.sorted()
    }

    private func pushPadLabelsForMainBank(_ bank: Int) -> [String] {
        let candidateIDs = mainBankSampleIDs(for: bank)
        var labels: [String] = []

        if !candidateIDs.isEmpty {
            labels = candidateIDs.prefix(64).map { id in
                if let curated = sampleLabelByID[id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !curated.isEmpty {
                    return curated
                }
                if let url = samplePackEntries[id] {
                    return url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                }
                return id
            }
        }

        while labels.count < 64 {
            labels.append(String(format: "main b%d %02d", min(3, max(1, bank)), labels.count + 1))
        }
        return labels
    }

    private func publishPushPadLabelsForActiveMainBank(force: Bool = false) {
        let labels = pushPadLabelsForMainBank(activeSampleBank)
        let signature = "\(activeSampleBank)|" + labels.joined(separator: "|")
        if !force, signature == pushLastPadLabelsSignature {
            return
        }
        pushLastPadLabelsSignature = signature
        let payload = PushPadLabelsPayload(
            padLabels: labels,
            bank: activeSampleBank,
            updatedAt: Date().timeIntervalSince1970 * 1000
        )
        Task {
            try? await websocket.sendEnvelope(kind: "push_pad_labels", data: payload)
        }
    }

    private func resolveSamplePackEntries(from selectedURL: URL) throws -> (entries: [String: URL], metadata: [String: SampleMetadata], labels: [String: String]) {
        if selectedURL.pathExtension.lowercased() != "json" {
            return (
                entries: ["default": selectedURL],
                metadata: ["default": SampleMetadata(id: "default", renderClass: .misc)],
                labels: ["default": "default"]
            )
        }

        let data = try Data(contentsOf: selectedURL)
        let decoder = JSONDecoder()
        if let manifest = try? decoder.decode(SamplePackManifest.self, from: data) {
            return resolveSampleEntries(manifest.samples, baseURL: selectedURL.deletingLastPathComponent())
        }
        if let padMap = try? decoder.decode(PushCompanionPadMap.self, from: data) {
            let resolved = resolvePushCompanionPadMapEntries(primaryMap: padMap, primaryMapURL: selectedURL)
            if !resolved.entries.isEmpty {
                return resolved
            }
        }

        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let samples = root["samples"] as? [String: String] {
                let resolved = samples.reduce(into: [String: URL]()) { result, entry in
                    let url = resolveMediaURL(path: entry.value, baseURL: selectedURL.deletingLastPathComponent())
                    if FileManager.default.fileExists(atPath: url.path) {
                        result[entry.key] = url
                    }
                }
                if !resolved.isEmpty {
                    let metadata = resolved.keys.reduce(into: [String: SampleMetadata]()) { result, id in
                        result[id] = SampleMetadata(id: id, renderClass: .misc)
                    }
                    return (entries: resolved, metadata: metadata, labels: [:])
                }
            }
            if let samples = root["samples"] as? [[String: Any]] {
                var resolved: [String: URL] = [:]
                var metadata: [String: SampleMetadata] = [:]
                var labels: [String: String] = [:]
                for sample in samples {
                    guard let id = sample["id"] as? String,
                          let path = sample["path"] as? String else { continue }
                    let url = resolveMediaURL(path: path, baseURL: selectedURL.deletingLastPathComponent())
                    if FileManager.default.fileExists(atPath: url.path) {
                        resolved[id] = url
                        metadata[id] = sampleMetadata(from: sample, id: id)
                        if let label = (sample["label"] as? String) ?? (sample["name"] as? String) ?? (sample["displayName"] as? String),
                           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            labels[id] = label
                        }
                    }
                }
                if !resolved.isEmpty {
                    for id in resolved.keys where metadata[id] == nil {
                        metadata[id] = SampleMetadata(id: id, renderClass: .misc)
                    }
                    return (entries: resolved, metadata: metadata, labels: labels)
                }
            }
        }

        let wavFallback = resolvePushCompanionWavEntriesByFolder(from: selectedURL)
        if !wavFallback.entries.isEmpty {
            return wavFallback
        }

        throw NSError(
            domain: "ConductorHarness",
            code: 1902,
            userInfo: [NSLocalizedDescriptionKey: "Manifest format unsupported"]
        )
    }

    private func resolvePushCompanionPadMapEntries(
        primaryMap: PushCompanionPadMap,
        primaryMapURL: URL
    ) -> (entries: [String: URL], metadata: [String: SampleMetadata], labels: [String: String]) {
        let fm = FileManager.default
        let primaryBankFolder = primaryMapURL.deletingLastPathComponent()
        let sampleRoot = primaryBankFolder.deletingLastPathComponent()

        var mapURLs: [URL] = [primaryMapURL]
        let b1 = sampleRoot.appendingPathComponent("main_b1").appendingPathComponent("pad_map.json")
        let b2 = sampleRoot.appendingPathComponent("main_b2").appendingPathComponent("pad_map.json")
        if fm.fileExists(atPath: b1.path), b1.standardizedFileURL.path != primaryMapURL.standardizedFileURL.path {
            mapURLs.append(b1)
        }
        if fm.fileExists(atPath: b2.path), b2.standardizedFileURL.path != primaryMapURL.standardizedFileURL.path {
            mapURLs.append(b2)
        }

        var entries: [String: URL] = [:]
        var metadata: [String: SampleMetadata] = [:]
        var labels: [String: String] = [:]
        let decoder = JSONDecoder()

        for mapURL in mapURLs {
            let map: PushCompanionPadMap
            if mapURL.standardizedFileURL.path == primaryMapURL.standardizedFileURL.path {
                map = primaryMap
            } else {
                guard let data = try? Data(contentsOf: mapURL),
                      let decoded = try? decoder.decode(PushCompanionPadMap.self, from: data) else {
                    continue
                }
                map = decoded
            }

            let bankFolder = mapURL.deletingLastPathComponent()
            let folderName = bankFolder.lastPathComponent.lowercased()
            let inferredBank: Int = {
                if let bank = map.bank, (1...9).contains(bank) {
                    return bank
                }
                if folderName.hasPrefix("main_b"),
                   let parsed = Int(folderName.replacingOccurrences(of: "main_b", with: "")) {
                    return parsed
                }
                return 1
            }()

            for slice in map.slices where (0..<64).contains(slice.slot) {
                let rawFileName = slice.fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fileName = (rawFileName?.isEmpty == false)
                    ? rawFileName!
                    : String(format: "main_b%d_%02d.wav", inferredBank, slice.slot + 1)
                let fileURL = bankFolder.appendingPathComponent(fileName)
                guard fm.fileExists(atPath: fileURL.path) else { continue }
                let sampleID = fileURL.deletingPathExtension().lastPathComponent
                entries[sampleID] = fileURL
                metadata[sampleID] = SampleMetadata(id: sampleID, renderClass: .misc)
                if let label = slice.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !label.isEmpty {
                    labels[sampleID] = label
                } else {
                    labels[sampleID] = fileURL.lastPathComponent
                }
            }

            ingestAdditionalBankMedia(
                bankFolder: bankFolder,
                inferredBank: inferredBank,
                entries: &entries,
                metadata: &metadata,
                labels: &labels
            )
        }

        return (entries: entries, metadata: metadata, labels: labels)
    }

    private func resolvePushCompanionWavEntriesByFolder(
        from selectedURL: URL
    ) -> (entries: [String: URL], metadata: [String: SampleMetadata], labels: [String: String]) {
        let fm = FileManager.default
        let manifestFolder = selectedURL.deletingLastPathComponent()
        let sampleRoot: URL = {
            let folderName = manifestFolder.lastPathComponent.lowercased()
            if folderName.hasPrefix("main_b") {
                return manifestFolder.deletingLastPathComponent()
            }
            return manifestFolder
        }()

        var folders: [URL] = [
            sampleRoot.appendingPathComponent("main_b1"),
            sampleRoot.appendingPathComponent("main_b2")
        ]
        if !folders.contains(where: { $0.standardizedFileURL.path == manifestFolder.standardizedFileURL.path }) {
            folders.append(manifestFolder)
        }

        var entries: [String: URL] = [:]
        var metadata: [String: SampleMetadata] = [:]
        var labels: [String: String] = [:]

        for folder in folders where fm.fileExists(atPath: folder.path) {
            guard let files = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let wavFiles = files
                .filter { $0.pathExtension.lowercased() == "wav" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            for fileURL in wavFiles {
                let sampleID = fileURL.deletingPathExtension().lastPathComponent
                entries[sampleID] = fileURL
                metadata[sampleID] = SampleMetadata(id: sampleID, renderClass: .misc)
                labels[sampleID] = sampleID.replacingOccurrences(of: "_", with: " ")
            }

            let inferredBank: Int = {
                let folderName = folder.lastPathComponent.lowercased()
                if folderName.hasPrefix("main_b"),
                   let parsed = Int(folderName.replacingOccurrences(of: "main_b", with: "")) {
                    return parsed
                }
                return 1
            }()
            ingestAdditionalBankMedia(
                bankFolder: folder,
                inferredBank: inferredBank,
                entries: &entries,
                metadata: &metadata,
                labels: &labels
            )
        }

        return (entries: entries, metadata: metadata, labels: labels)
    }

    private func ingestAdditionalBankMedia(
        bankFolder: URL,
        inferredBank: Int,
        entries: inout [String: URL],
        metadata: inout [String: SampleMetadata],
        labels: inout [String: String]
    ) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: bankFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let supportedExtensions = Set(["wav", "aif", "aiff", "m4a", "caf", "mp3"])
        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let normalizedBase = baseName.lowercased()
            let prefixedID: String = {
                let bankPrefix = "main_b\(min(9, max(1, inferredBank)))_"
                if normalizedBase.hasPrefix(bankPrefix) {
                    return baseName
                }
                return "\(bankPrefix)\(baseName)"
            }()
            guard entries[prefixedID] == nil else { continue }

            entries[prefixedID] = fileURL
            let renderClass: SampleRenderClass = {
                if normalizedBase.contains("long") || normalizedBase.contains("paul") {
                    return .texture
                }
                return .misc
            }()
            metadata[prefixedID] = SampleMetadata(id: prefixedID, renderClass: renderClass)
            labels[prefixedID] = baseName.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func shouldAutoloadPushCompanionSamples() -> Bool {
        if samplePackEntries.isEmpty {
            return true
        }
        if samplePackEntries.count == 1, samplePackEntries["default"] != nil {
            return true
        }
        return false
    }

    @discardableResult
    private func autoloadPushCompanionSampleBanksIfNeeded() -> Bool {
        guard shouldAutoloadPushCompanionSamples() else { return false }
        let fm = FileManager.default

        var candidateMapURLs: [URL] = []
        if let explicit = ProcessInfo.processInfo.environment["CONDUCTOR_PUSH_PAD_MAP_PATH"],
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidateMapURLs.append(URL(fileURLWithPath: explicit))
        }
        if let explicitRoot = ProcessInfo.processInfo.environment["CONDUCTOR_PUSH_SAMPLES_DIR"],
           !explicitRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidateMapURLs.append(
                URL(fileURLWithPath: explicitRoot)
                    .appendingPathComponent("main_b1")
                    .appendingPathComponent("pad_map.json")
            )
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        var probe = cwd
        for _ in 0..<8 {
            candidateMapURLs.append(
                probe
                    .appendingPathComponent("push-companion-ios")
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("PushCompanionIOS")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent("Samples")
                    .appendingPathComponent("main_b1")
                    .appendingPathComponent("pad_map.json")
            )
            candidateMapURLs.append(
                probe
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("PushCompanionIOS")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent("Samples")
                    .appendingPathComponent("main_b1")
                    .appendingPathComponent("pad_map.json")
            )
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path { break }
            probe = parent
        }

        let fallbackUserPath = URL(fileURLWithPath: "/Users/seb/letgo/push-companion-ios/Sources/PushCompanionIOS/Resources/Samples/main_b1/pad_map.json")
        candidateMapURLs.append(fallbackUserPath)

        var seen = Set<String>()
        let uniqueCandidates = candidateMapURLs.filter { url in
            let standardized = url.standardizedFileURL.path
            guard !seen.contains(standardized) else { return false }
            seen.insert(standardized)
            return true
        }

        for candidate in uniqueCandidates where fm.fileExists(atPath: candidate.path) {
            guard let resolved = try? resolveSamplePackEntries(from: candidate),
                  !resolved.entries.isEmpty else {
                continue
            }

            let hasB1 = resolved.entries.keys.contains { $0.hasPrefix("main_b1_") }
            let hasB2 = resolved.entries.keys.contains { $0.hasPrefix("main_b2_") }
            guard hasB1, hasB2 else { continue }

            samplePackManifestURL = candidate
            samplePackEntries = resolved.entries
            sampleMetadataByID = resolved.metadata
            sampleLabelByID = resolved.labels
            if let firstID = resolved.entries.keys.sorted().first {
                selectedSampleID = firstID
            }
            updateEffectsPresetForActiveBank()
            applyStaticSampleMorphSelection()
            publishPushPadLabelsForActiveMainBank(force: true)
            saveMediaManifest()
            pushStatus(StatusLineEvent(
                message: "Auto-loaded Push sample banks (B1/B2): \(resolved.entries.count) slices",
                severity: .success,
                timestamp: Date()
            ))
            return true
        }

        return false
    }

    private func resolveSampleEntries(
        _ entries: [SamplePackManifest.SampleEntry],
        baseURL: URL
    ) -> (entries: [String: URL], metadata: [String: SampleMetadata], labels: [String: String]) {
        var resolved: [String: URL] = [:]
        var metadata: [String: SampleMetadata] = [:]
        var labels: [String: String] = [:]
        for entry in entries {
            let url = resolveMediaURL(path: entry.path, baseURL: baseURL)
            if FileManager.default.fileExists(atPath: url.path) {
                resolved[entry.id] = url
                metadata[entry.id] = sampleMetadata(from: entry)
                let label = entry.label ?? entry.name ?? entry.displayName
                if let curated = label?.trimmingCharacters(in: .whitespacesAndNewlines), !curated.isEmpty {
                    labels[entry.id] = curated
                }
            }
        }
        return (entries: resolved, metadata: metadata, labels: labels)
    }

    private func sampleMetadata(from entry: SamplePackManifest.SampleEntry) -> SampleMetadata {
        let renderClass = SampleRenderClass(rawValue: (entry.sampleClass ?? "").lowercased()) ?? .misc
        return SampleMetadata(
            id: entry.id,
            renderClass: renderClass,
            key: entry.key,
            bpm: entry.bpm,
            energy: entry.energy ?? 0.5,
            timbre: entry.timbre ?? 0.5,
            isLoop: entry.loop ?? false
        )
    }

    private func sampleMetadata(from dict: [String: Any], id: String) -> SampleMetadata {
        func number(_ key: String) -> Double? {
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
            if let value = dict[key] as? NSNumber {
                return value.doubleValue
            }
            return nil
        }
        let renderClass = SampleRenderClass(rawValue: ((dict["class"] as? String) ?? "").lowercased()) ?? .misc
        return SampleMetadata(
            id: id,
            renderClass: renderClass,
            key: dict["key"] as? String,
            bpm: number("bpm"),
            energy: number("energy") ?? 0.5,
            timbre: number("timbre") ?? 0.5,
            isLoop: dict["loop"] as? Bool ?? false
        )
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
        let overrideURL = Self.loadCoreMLSearchDirectoryOverride()
        let rebuilt = Self.buildCoreMLSearchDirectories(overrideURL: overrideURL)
        scoringModel.updateSearchDirectories(rebuilt)
        modelSearchOverridePath = overrideURL?.path
        modelSearchPaths = rebuilt.map { $0.path }

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

        pushStatus(StatusLineEvent(
            message: "Model catalog refreshed — \(merged.count) bundle(s) across \(rebuilt.count) path(s)",
            severity: merged.isEmpty ? .warn : .info,
            timestamp: Date()
        ))
    }

    func pickCoreMLSearchDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Select CoreML Models Directory"
        panel.prompt = "Use Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        UserDefaults.standard.set(chosen.path, forKey: Self.coreMLSearchDirectoryDefaultsKey)
        pushStatus(StatusLineEvent(
            message: "Models directory set: \(chosen.path)",
            severity: .success,
            timestamp: Date()
        ))
        refreshModelCatalog()
        reloadPreferredModel()
    }

    func clearCoreMLSearchDirectoryOverride() {
        UserDefaults.standard.removeObject(forKey: Self.coreMLSearchDirectoryDefaultsKey)
        pushStatus(StatusLineEvent(
            message: "Models directory override cleared",
            severity: .info,
            timestamp: Date()
        ))
        refreshModelCatalog()
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
        rebuildDynamicBinManifest()
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
        rebuildDynamicBinManifest()
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
        rebuildDynamicBinManifest()
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

    func togglePreviewPlayback() {
        if previewPlayer.timeControlStatus == .playing {
            pausePreview()
        } else {
            playPreview()
        }
    }

    func setActiveSampleBankFromControl(_ bank: Int, domain: SampleBankDomain) {
        clearProposalStructuredLatchIfNeeded("manual bank override")
        applySampleBankSelection(bank, domain: domain, emitStatus: true)
    }

    func setDynamicBinSelectionFromControl(_ value: Double) {
        let normalized = Self.clamp01(value)
        updatePerformerProceduralState { state in
            state.dynamicBinSelection = normalized
        }
        recordSoundManipulationFocus(lane: "SRC X", value: normalized, controlIDHint: "gd:x")
        maybeTriggerHOTASDynamicSampleScoring(
            lane: "SRC X",
            axis: .x,
            normalizedControlValue: normalized
        )
    }

    func setCutCadenceFromControl(_ value: Double) {
        let normalized = Self.clamp01(value)
        updatePerformerProceduralState { state in
            state.cutCadence = normalized
            switch normalized {
            case ..<0.28:
                state.transitionMode = .cut
            case ..<0.62:
                state.transitionMode = .crossfade
            case ..<0.82:
                state.transitionMode = .fade
            default:
                state.transitionMode = .stutter
            }
        }
        recordSoundManipulationFocus(lane: "CUT Y", value: normalized, controlIDHint: "gd:y")
        maybeTriggerHOTASDynamicSampleScoring(
            lane: "CUT Y",
            axis: .y,
            normalizedControlValue: normalized
        )
    }

    func setCompositorBlendFromControl(_ value: Double) {
        let normalized = Self.clamp01(value)
        updatePerformerProceduralState { state in
            state.fade = normalized
            switch normalized {
            case ..<0.17:
                state.compositorPreset = .blend
            case ..<0.34:
                state.compositorPreset = .screen
            case ..<0.50:
                state.compositorPreset = .multiply
            case ..<0.67:
                state.compositorPreset = .mask
            case ..<0.84:
                state.compositorPreset = .pip
            default:
                state.compositorPreset = .stutter
            }
        }
        recordSoundManipulationFocus(lane: "COMP Z", value: normalized, controlIDHint: "gd:rz")
        maybeTriggerHOTASDynamicSampleScoring(
            lane: "COMP Z",
            axis: .z,
            normalizedControlValue: normalized
        )
    }

    private func recordSoundManipulationFocus(
        lane: String,
        value: Double,
        controlIDHint: String? = nil,
        sourceHint: String? = nil
    ) {
        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        let normalizedValue = Self.clamp01(value)

        var source = sourceHint ?? "CONTROL"
        var controlID = controlIDHint ?? lane

        if let signal = hotasLastSignal {
            let signalMs = ConductorHarnessViewModel.normalizedMilliseconds(signal.timestamp)
            if abs(nowMs - signalMs) < 420 {
                source = signal.sourceKind.rawValue.uppercased()
                controlID = signal.controlID
            }
        }

        soundManipulationFocus = SoundManipulationFocus(
            source: source,
            controlID: controlID,
            lane: lane,
            normalizedValue: normalizedValue,
            updatedAt: nowMs
        )
    }

    func setStaticVisualOverrideHoldFromControl(_ isHeld: Bool) {
        let next = hotasStaticVideoOverrideEnabled ? isHeld : false
        guard hotasStaticVisualOverrideHeld != next else { return }
        hotasStaticVisualOverrideHeld = next
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestSystem(
                stage: .applied,
                severity: .apply,
                controlID: "clutch:static_visual",
                semanticAction: next ? "static_visual_clutch_on" : "static_visual_clutch_off",
                outcome: next ? "HELD" : "RELEASED",
                detail: nil
            )
        }
    }

    func setStaticSampleMorphFromControl(_ value: Double) {
        clearProposalStructuredLatchIfNeeded("manual static sample morph")
        let normalized = Self.clamp01(value)
        guard abs(staticAudioMacroState.sampleMorph - normalized) > 0.01 else { return }
        staticAudioMacroState.sampleMorph = normalized
        recordSoundManipulationFocus(lane: "SAMPLE MORPH", value: normalized, controlIDHint: "gd:x")
        applyStaticSampleMorphSelection()
        applyStaticMacroAudioState()
        maybeTriggerHOTASStaticSampleAudition(
            lane: "SAMPLE MORPH",
            axis: .x,
            normalizedControlValue: normalized
        )
    }

    func setStaticArticulationFromControl(_ value: Double) {
        clearProposalStructuredLatchIfNeeded("manual static articulation")
        let normalized = Self.clamp01(value)
        guard abs(staticAudioMacroState.articulation - normalized) > 0.01 else { return }
        staticAudioMacroState.articulation = normalized
        recordSoundManipulationFocus(lane: "ARTICULATION", value: normalized, controlIDHint: "gd:y")
        applyStaticMacroAudioState()
        maybeTriggerHOTASStaticSampleAudition(
            lane: "ARTICULATION",
            axis: .y,
            normalizedControlValue: normalized
        )
    }

    func setStaticTimbreFromControl(_ value: Double) {
        clearProposalStructuredLatchIfNeeded("manual static timbre")
        let normalized = Self.clamp01(value)
        guard abs(staticAudioMacroState.timbre - normalized) > 0.01 else { return }
        staticAudioMacroState.timbre = normalized
        recordSoundManipulationFocus(lane: "TIMBRE", value: normalized, controlIDHint: "gd:rz")
        applyStaticMacroAudioState()
        maybeTriggerHOTASStaticSampleAudition(
            lane: "TIMBRE",
            axis: .z,
            normalizedControlValue: normalized
        )
    }

    func setStaticTextureSendFromControl(_ value: Double) {
        clearProposalStructuredLatchIfNeeded("manual static texture send")
        let normalized = Self.clamp01(value)
        guard abs(staticAudioMacroState.textureSend - normalized) > 0.01 else { return }
        staticAudioMacroState.textureSend = normalized
        recordSoundManipulationFocus(lane: "TEXTURE SEND", value: normalized, controlIDHint: "gd:slider")
        applyStaticMacroAudioState()
    }

    func setChoirFieldSpreadFromControl(_ value: Double) {
        let normalized = Self.clamp01(value)
        guard abs(choirFieldState.spread - normalized) > 0.01 else { return }
        choirFieldState.spread = normalized
        recordSoundManipulationFocus(lane: "CHOIR SPREAD", value: normalized, controlIDHint: "gd:x")
        quadAudioEngine.setChoirFieldState(choirFieldState)
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
    }

    func setChoirFieldDepthFromControl(_ value: Double) {
        let normalized = Self.clamp01(value)
        guard abs(choirFieldState.depth - normalized) > 0.01 else { return }
        choirFieldState.depth = normalized
        recordSoundManipulationFocus(lane: "CHOIR DEPTH", value: normalized, controlIDHint: "gd:y")
        quadAudioEngine.setChoirFieldState(choirFieldState)
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
    }

    func setChoirFieldDetuneFromControl(_ value: Double) {
        let normalized = Self.clamp01(value)
        guard abs(choirFieldState.detune - normalized) > 0.01 else { return }
        choirFieldState.detune = normalized
        recordSoundManipulationFocus(lane: "CHOIR DETUNE", value: normalized, controlIDHint: "gd:rz")
        quadAudioEngine.setChoirFieldState(choirFieldState)
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
    }

    func setTextProbabilityFromControl(_ value: Double) {
        updatePerformerProceduralState { state in
            state.textProbability = Self.clamp01(value)
        }
    }

    func setStrictLooseBlendFromControl(_ value: Double) {
        updatePerformerProceduralState { state in
            state.strictLooseBlend = Self.clamp01(value)
        }
    }

    func setVisualVarianceFromControl(_ value: Double) {
        updatePerformerProceduralState { state in
            let normalized = Self.clamp01(value)
            state.visualVariance = normalized
            switch normalized {
            case ..<0.35:
                state.splitLayout = .none
            case ..<0.60:
                state.splitLayout = .split2
            case ..<0.82:
                state.splitLayout = .split3
            default:
                state.splitLayout = .split4
            }
        }
    }

    func toggleUltrachunkOverlayFromControl() {
        hotasUltrachunkOverlayEnabled.toggle()
        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        let enabled = hotasUltrachunkOverlayEnabled

        if !enabled {
            ultrachunkDSPState = .neutral
            ultrachunkGranularity = 0
            ultrachunkIntensity = 0
        }

        recordSoundManipulationFocus(
            lane: enabled ? "ULTRACHUNK OVERLAY ON" : "ULTRACHUNK OVERLAY OFF",
            value: enabled ? 1 : 0,
            controlIDHint: "fx:ultrachunk_overlay"
        )

        pushStatus(StatusLineEvent(
            message: enabled ? "ULTRACHUNK overlay enabled" : "ULTRACHUNK overlay disabled",
            severity: .info,
            timestamp: Date()
        ))
        refreshProgramAudioState(nowMs: nowMs)
        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestSystem(
                stage: .applied,
                severity: .apply,
                controlID: "fx:ultrachunk_overlay",
                semanticAction: "ultrachunk_overlay_toggle",
                outcome: enabled ? "ON" : "OFF",
                detail: nil
            )
        }
    }

    func setPhoneChoirContextActiveFromControl(_ active: Bool) {
        guard hotasPhoneChoirContextActive != active else { return }
        hotasPhoneChoirContextActive = active
        recordSoundManipulationFocus(
            lane: active ? "MODE -> PHONE CHOIR" : "MODE -> NORMAL",
            value: active ? 1 : 0,
            controlIDHint: "ctx:choir"
        )

        if active {
            applySampleBankSelection(
                activeChoirSampleBank,
                domain: .choir,
                emitStatus: true,
                forceSelectionRefresh: true
            )
        } else {
            activeChoirMIDINotes.removeAll()
            resetHOTASStaticSampleAuditionState()
            applySampleBankSelection(
                activeSampleBank,
                domain: .main,
                emitStatus: true,
                forceSelectionRefresh: true
            )
        }
    }

    func setEffectsChainFromControl(chain: EffectsChainID, active: Bool, intensity: Double) {
        clearProposalStructuredLatchIfNeeded("manual FX override")
        var next = effectsChainState
        next.set(chain: chain, active: active, intensity: intensity)
        guard next != effectsChainState else { return }
        effectsChainState = next
        recordSoundManipulationFocus(
            lane: chain == .a ? "FX RHYTHM" : "FX SPACE",
            value: intensity,
            controlIDHint: chain == .a ? "btn:10" : "btn:11"
        )
        quadAudioEngine.setEffectsChainState(chain: chain, active: active, intensity: intensity)
        applyStaticMacroAudioState()
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
    }

    private func applyStaticMacroAudioState() {
        quadAudioEngine.setStaticMacroFrame(EffectsMacroFrame(
            chainAIntensity: effectsChainState.chainAIntensity,
            chainBIntensity: effectsChainState.chainBIntensity,
            articulation: staticAudioMacroState.articulation,
            timbre: staticAudioMacroState.timbre,
            textureSend: staticAudioMacroState.textureSend
        ))
        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
    }

    private func applyStaticSampleMorphSelection() {
        guard currentHOTASOutputModeID() != .dynamic else { return }
        guard !hotasPhoneChoirContextActive else { return }
        guard !hotasStaticVisualOverrideHeld else { return }

        let candidateIDs = mainBankSampleIDs(for: activeSampleBank)
        guard let resolved = sampleMorphEngine.resolveSampleID(
            morph: staticAudioMacroState.sampleMorph,
            candidateIDs: candidateIDs,
            metadata: sampleMetadataByID
        ) else {
            return
        }

        if selectedSampleID != resolved {
            selectedSampleID = resolved
        }
    }

    private func selectMainBankSampleForDynamicSelection(_ normalized: Double) {
        guard !hotasPhoneChoirContextActive else { return }
        let candidateIDs = mainBankSampleIDs(for: activeSampleBank)
        guard !candidateIDs.isEmpty else { return }
        let clamped = Self.clamp01(normalized)
        let index = Int(round(clamped * Double(max(1, candidateIDs.count - 1))))
        let safeIndex = min(max(0, index), candidateIDs.count - 1)
        let selectedID = candidateIDs[safeIndex]
        if selectedSampleID != selectedID {
            selectedSampleID = selectedID
        }
    }

    private func maybeTriggerHOTASDynamicSampleScoring(
        lane: String,
        axis: HOTASSampleSpaceAxis,
        normalizedControlValue: Double
    ) {
        guard !hotasPhoneChoirContextActive else { return }
        guard currentHOTASOutputModeID() == .dynamic else { return }
        maybeTriggerHOTASSampleSpaceAudition(
            lane: lane,
            axis: axis,
            normalizedControlValue: normalizedControlValue,
            dynamicMode: true
        )
    }

    private func maybeTriggerHOTASStaticSampleAudition(
        lane: String,
        axis: HOTASSampleSpaceAxis,
        normalizedControlValue: Double
    ) {
        guard !hotasPhoneChoirContextActive else { return }
        guard currentHOTASOutputModeID() != .dynamic else { return }
        guard !hotasStaticVisualOverrideHeld else { return }
        maybeTriggerHOTASSampleSpaceAudition(
            lane: lane,
            axis: axis,
            normalizedControlValue: normalizedControlValue,
            dynamicMode: false
        )
    }

    private func maybeTriggerHOTASSampleSpaceAudition(
        lane: String,
        axis: HOTASSampleSpaceAxis,
        normalizedControlValue: Double,
        dynamicMode: Bool
    ) {
        guard ensureScoringEngineReady(operation: dynamicMode ? "HOTAS dynamic scoring" : "HOTAS sample audition") else {
            maybeEmitHOTASStaticAuditionStatus(
                dynamicMode
                    ? "HOTAS scoring blocked: engine is stopped"
                    : "HOTAS sample audition blocked: engine is stopped",
                severity: .warn
            )
            return
        }

        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        let (controlFrame, axisDelta) = updateUltrachunkControlFrame(
            axis: axis,
            normalizedControlValue: normalizedControlValue,
            nowMs: nowMs
        )
        guard axisDelta >= 0.006 || controlFrame.speed >= 0.018 else { return }

        let atlas = ultrachunkSampleAtlas(for: activeSampleBank)
        guard !atlas.isEmpty else {
            maybeEmitHOTASStaticAuditionStatus(
                dynamicMode
                    ? "HOTAS scoring blocked: load sample pack first"
                    : "HOTAS sample audition blocked: load sample pack first",
                severity: .warn
            )
            return
        }

        let chainA = effectsChainState.chainAActive ? effectsChainState.chainAIntensity : 0
        let chainB = effectsChainState.chainBActive ? effectsChainState.chainBIntensity : 0

        let ultrachunkOverlayEnabled = hotasUltrachunkOverlayEnabled
        let computedGranularity = ultrachunkGranularity(for: controlFrame.speed)
        let computedIntensity = ultrachunkIntensity(for: controlFrame.speed)
        let granularity = ultrachunkOverlayEnabled ? computedGranularity : 0
        let intensity = ultrachunkOverlayEnabled ? computedIntensity : 0
        ultrachunkGranularity = granularity
        ultrachunkIntensity = intensity
        let density = ConductorHarnessViewModel.clamp01(granularity + (chainA * 0.46))
        let minIntervalMs = max(18, 176 - (density * 142) - (chainA * 54))
        guard nowMs - hotasStaticSampleAuditionLastAtMs >= minIntervalMs else { return }

        let selection = selectUltrachunkSamples(from: atlas, frame: controlFrame, intensity: intensity)
        guard let primaryURL = samplePackEntries[selection.primary.sampleID] else { return }

        let sameSample = selection.primary.sampleID == hotasStaticSampleAuditionLastSampleID
        if sameSample, axisDelta < 0.03, controlFrame.speed < 0.08 {
            return
        }

        selectedSampleID = selection.primary.sampleID
        ultrachunkPrimarySampleID = selection.primary.sampleID
        ultrachunkSecondarySampleID = selection.secondary?.sampleID

        let dspState = ultrachunkOverlayEnabled
            ? deriveUltrachunkDSPState(
                twist: controlFrame.twist,
                intensity: intensity,
                spaceBoost: chainB
            )
            : .neutral
        ultrachunkDSPState = dspState
        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestTrace(id: "trace:ultrachunk_speed", value: controlFrame.speed)
            await hudTelemetryStore.ingestTrace(id: "trace:ultrachunk_granularity", value: granularity)
            await hudTelemetryStore.ingestTrace(id: "trace:ultrachunk_intensity", value: intensity)
            await hudTelemetryStore.ingestTrace(id: "trace:ultrachunk_twist", value: controlFrame.twist)
            await hudTelemetryStore.ingestTrace(
                id: "trace:ultrachunk_lane",
                value: dspState.twistLane == .spectral ? 1 : (dspState.twistLane == .crusher ? 0 : 0.5)
            )
        }

        let baseGain: Double = dynamicMode
            ? (0.18 + (performerProceduralState.cutCadence * 0.18) + (performerProceduralState.fade * 0.12))
            : (0.16 + (staticAudioMacroState.articulation * 0.2) + (staticAudioMacroState.textureSend * 0.18))
        let movementGain = min(0.34, controlFrame.speed * 0.42)
        let gain = min(0.95, max(0.08, baseGain + movementGain + (chainA * 0.08)))

        let forward = ConductorHarnessViewModel.remap01(controlFrame.y, min: 0.5, max: 1)
        let back = ConductorHarnessViewModel.remap01(1 - controlFrame.y, min: 0.5, max: 1)
        let localityTilt = (controlFrame.x - 0.5) * 2

        let baseChunkWindow = (1 - granularity) * hotasUltrachunkQualityProfile.maxChunkWindowMs
        let chunkWindowMs = max(
            hotasUltrachunkQualityProfile.minChunkWindowMs,
            min(
                hotasUltrachunkQualityProfile.maxChunkWindowMs,
                baseChunkWindow + (forward * 220) - (back * 70)
            )
        )
        let jitterMs = min(300, 8 + (intensity * 124) + (chainA * 84))
        let releaseMs = min(1_300, 90 + (forward * 460) + ((1 - granularity) * 120))
        let baseRate = 1 + (localityTilt * 0.22) - (forward * 0.1) + (back * 0.08)
        let densityRate = 1 + ((density - 0.5) * 0.3)
        let recipe = UltrachunkVoiceRecipe(
            sampleID: selection.primary.sampleID,
            startNormalized: hotasSampleSpaceX,
            chunkWindowMs: chunkWindowMs,
            jitterMs: jitterMs,
            rate: max(0.22, min(2.4, baseRate * densityRate)),
            gain: gain,
            releaseMs: releaseMs,
            density: density
        )

        let dryGain = max(0.06, min(0.74, gain * (0.34 + (chainA * 0.18))))
        try? quadAudioEngine.triggerSample(url: primaryURL, gain: dryGain)

        if ultrachunkOverlayEnabled {
            do {
                try quadAudioEngine.triggerUltrachunkVoice(
                    url: primaryURL,
                    recipe: recipe,
                    dsp: dspState,
                    qualityProfile: hotasUltrachunkQualityProfile
                )

                if let secondary = selection.secondary,
                   let secondaryURL = samplePackEntries[secondary.sampleID] {
                    let secondaryGain = min(0.54, max(0.06, gain * (0.38 + (chainB * 0.34))))
                    let secondaryRecipe = UltrachunkVoiceRecipe(
                        sampleID: secondary.sampleID,
                        startNormalized: ConductorHarnessViewModel.clamp01((hotasSampleSpaceX * 0.72) + 0.14),
                        chunkWindowMs: min(1_200, chunkWindowMs * (1.18 + (forward * 0.34))),
                        jitterMs: min(420, jitterMs * 1.3),
                        rate: max(0.14, min(2.2, recipe.rate * (0.92 + (chainB * 0.2)))),
                        gain: secondaryGain,
                        releaseMs: min(2_000, releaseMs * (1.1 + (chainB * 0.35))),
                        density: min(1, density + (chainB * 0.22))
                    )
                    try quadAudioEngine.triggerUltrachunkVoice(
                        url: secondaryURL,
                        recipe: secondaryRecipe,
                        dsp: dspState,
                        qualityProfile: hotasUltrachunkQualityProfile
                    )
                }
                hotasUltrachunkLastRenderAtMs = nowMs
            } catch {
                if nowMs - hotasStaticSampleAuditionLastStatusAtMs >= 900 {
                    hotasStaticSampleAuditionLastStatusAtMs = nowMs
                    pushStatus(StatusLineEvent(
                        message: "Ultrachunk failed: \(error.localizedDescription)",
                        severity: .error,
                        timestamp: Date()
                    ))
                }
            }
        }

        maybeTriggerHOTASPaulstretchMorphFromXY(
            primaryURL: primaryURL,
            secondaryURL: selection.secondary.flatMap { samplePackEntries[$0.sampleID] },
            frame: controlFrame,
            axis: axis,
            axisDelta: axisDelta,
            dynamicMode: dynamicMode,
            nowMs: nowMs
        )
        triggerHOTASEffectsAccentsLegacy(
            selectedID: selection.primary.sampleID,
            candidateIDs: atlas.map(\.sampleID),
            baseGain: dryGain,
            nowMs: nowMs
        )
        triggerHOTASLegacyStretchLayerIfNeeded(
            sampleURL: primaryURL,
            axisDelta: axisDelta,
            dynamicMode: dynamicMode,
            nowMs: nowMs
        )

        hotasStaticSampleAuditionLastAtMs = nowMs
        hotasStaticSampleAuditionLastValueByLane[lane] = normalizedControlValue
        hotasStaticSampleAuditionLastSampleID = selection.primary.sampleID
        refreshProgramAudioState(nowMs: nowMs)

        if nowMs - hotasStaticSampleAuditionLastStatusAtMs >= 1_100 || !sameSample {
            hotasStaticSampleAuditionLastStatusAtMs = nowMs
            let layerLabel = ultrachunkOverlayEnabled ? "ULTRACHUNK" : "HOTAS SOUND"
            pushStatus(StatusLineEvent(
                message: "\(layerLabel) \(selection.primary.sampleID) g\(String(format: "%.2f", granularity)) i\(String(format: "%.2f", intensity)) \(dspState.twistLane.rawValue.uppercased())",
                severity: .info,
                timestamp: Date()
            ))
        }
    }

    private func updateHOTASSampleSpace(
        axis: HOTASSampleSpaceAxis,
        normalizedControlValue: Double
    ) -> Double {
        let clamped = Self.clamp01(normalizedControlValue)
        switch axis {
        case .x:
            let delta = clamped - hotasSampleSpaceX
            hotasSampleSpaceX = clamped
            return delta
        case .y:
            let delta = clamped - hotasSampleSpaceY
            hotasSampleSpaceY = clamped
            return delta
        case .z:
            let delta = clamped - hotasSampleSpaceZ
            hotasSampleSpaceZ = clamped
            return delta
        }
    }

    private func updateUltrachunkControlFrame(
        axis: HOTASSampleSpaceAxis,
        normalizedControlValue: Double,
        nowMs: TimeInterval
    ) -> (UltrachunkControlFrame, Double) {
        let signedAxisDelta = updateHOTASSampleSpace(axis: axis, normalizedControlValue: normalizedControlValue)
        let axisDelta = abs(signedAxisDelta)
        let lastAt = hotasUltrachunkLastFrameAtMs == 0 ? nowMs - 16 : hotasUltrachunkLastFrameAtMs
        let dtSeconds = max(0.008, (nowMs - lastAt) / 1_000)
        let instantaneousSpeed = ConductorHarnessViewModel.clamp01((axisDelta / dtSeconds) * 0.2)
        let smoothedSpeed = max(instantaneousSpeed, hotasUltrachunkLastFrame.speed * 0.82)
        let frame = UltrachunkControlFrame(
            x: hotasSampleSpaceX,
            y: hotasSampleSpaceY,
            twist: hotasSampleSpaceZ,
            speed: smoothedSpeed,
            timestamp: nowMs
        )
        hotasUltrachunkLastFrameAtMs = nowMs
        hotasUltrachunkLastFrame = frame
        ultrachunkControlFrame = frame
        return (frame, axisDelta)
    }

    private func ultrachunkGranularity(for speed: Double) -> Double {
        UltrachunkMapping.granularity(forSpeed: speed)
    }

    private func ultrachunkIntensity(for speed: Double) -> Double {
        UltrachunkMapping.intensity(forSpeed: speed)
    }

    private func deriveUltrachunkDSPState(
        twist: Double,
        intensity: Double,
        spaceBoost: Double
    ) -> UltrachunkDSPState {
        UltrachunkMapping.twistDSPState(
            twistNormalized: twist,
            intensity: intensity,
            spaceBoost: spaceBoost
        )
    }

    private func ultrachunkSampleAtlas(for bank: Int) -> [SampleAtlasEntry] {
        var orderedIDs: [String] = []
        var seen: Set<String> = []

        func appendID(_ id: String) {
            guard samplePackEntries[id] != nil else { return }
            if seen.insert(id).inserted {
                orderedIDs.append(id)
            }
        }

        for id in mainBankSampleIDs(for: bank) {
            appendID(id)
        }

        let bankPrefix = "main_b\(min(3, max(1, bank)))_"
        for id in samplePackEntries.keys
            .filter({ $0.lowercased().hasPrefix(bankPrefix.lowercased()) })
            .sorted() {
            appendID(id)
        }

        if orderedIDs.isEmpty {
            for id in samplePackEntries.keys.sorted() {
                appendID(id)
            }
        }

        guard !orderedIDs.isEmpty else { return [] }
        let regionCount = max(4, min(12, Int((Double(orderedIDs.count) / 6).rounded())))
        return orderedIDs.enumerated().map { index, sampleID in
            let region = Int((Double(index) / Double(max(1, orderedIDs.count - 1)) * Double(regionCount - 1)).rounded())
            let depthClass = classifySampleDepth(sampleID: sampleID)
            return SampleAtlasEntry(
                sampleID: sampleID,
                region: region,
                depthClass: depthClass,
                isLongTexture: depthClass == .texture
            )
        }
    }

    private func classifySampleDepth(sampleID: String) -> SampleDepthClass {
        let loweredID = sampleID.lowercased()
        let loweredName = samplePackEntries[sampleID]?.lastPathComponent.lowercased() ?? loweredID
        let token = loweredID + " " + loweredName
        if token.contains("long")
            || token.contains("paul")
            || token.contains("stretch")
            || token.contains("texture")
            || token.contains("drone")
            || token.contains("ambient")
            || token.contains("wash") {
            return .texture
        }
        if token.contains("kick")
            || token.contains("snare")
            || token.contains("perc")
            || token.contains("stab")
            || token.contains("hit")
            || token.contains("pluck") {
            return .transient
        }
        if let renderClass = sampleMetadataByID[sampleID]?.renderClass {
            switch renderClass {
            case .texture:
                return .texture
            case .percussion:
                return .transient
            default:
                break
            }
        }
        return .balanced
    }

    private func selectUltrachunkSamples(
        from atlas: [SampleAtlasEntry],
        frame: UltrachunkControlFrame,
        intensity: Double
    ) -> (primary: SampleAtlasEntry, secondary: SampleAtlasEntry?) {
        let regionCount = max(1, (atlas.map(\.region).max() ?? 0) + 1)
        let targetRegion = Int((frame.x * Double(max(1, regionCount - 1))).rounded())
        let forward = ConductorHarnessViewModel.remap01(frame.y, min: 0.5, max: 1)
        let back = ConductorHarnessViewModel.remap01(1 - frame.y, min: 0.5, max: 1)
        let preferTexture = forward >= back

        let scored = atlas.map { entry -> (entry: SampleAtlasEntry, score: Double) in
            let regionDistance = abs(Double(entry.region - targetRegion)) / Double(max(1, regionCount - 1))
            let depthPenalty: Double = switch entry.depthClass {
            case .texture:
                preferTexture ? 0 : (0.52 + (back * 0.24))
            case .transient:
                preferTexture ? (0.52 + (forward * 0.24)) : 0
            case .balanced:
                0.22
            }
            let longPenalty = preferTexture
                ? (entry.isLongTexture ? 0 : (0.12 + (forward * 0.2)))
                : (entry.isLongTexture ? (0.18 + (back * 0.16)) : 0)
            let score = (regionDistance * 0.68) + depthPenalty + longPenalty
            return (entry, score)
        }
        .sorted {
            if abs($0.score - $1.score) > 0.0001 {
                return $0.score < $1.score
            }
            return $0.entry.sampleID < $1.entry.sampleID
        }

        let primary = scored.first!.entry
        let secondaryThreshold = 0.16 + (intensity * 0.28)
        let secondary = scored
            .dropFirst()
            .first(where: { candidate in
                candidate.entry.sampleID != primary.sampleID
                    && candidate.score <= (scored.first!.score + secondaryThreshold)
            })?
            .entry

        return (primary: primary, secondary: secondary)
    }

    private func resetHOTASStaticSampleAuditionState() {
        hotasStaticSampleAuditionLastAtMs = 0
        hotasStaticSampleAuditionLastValueByLane.removeAll()
        hotasStaticSampleAuditionLastSampleID = nil
        hotasStaticSampleAuditionLastStatusAtMs = 0
        hotasSampleSpaceX = 0.5
        hotasSampleSpaceY = 0.5
        hotasSampleSpaceZ = 0.5
        hotasSampleSpaceDrift = 0
        hotasLastRhythmAccentAtMs = 0
        hotasLastSpaceAccentAtMs = 0
        hotasLastPaulstretchAtMs = 0
        hotasLastPaulstretchMorphAtMs = 0
        hotasUltrachunkLastFrameAtMs = 0
        hotasUltrachunkLastRenderAtMs = 0
        hotasUltrachunkLastFrame = .neutral
        ultrachunkControlFrame = .neutral
        ultrachunkDSPState = .neutral
        ultrachunkGranularity = 0
        ultrachunkIntensity = 0
        ultrachunkPrimarySampleID = nil
        ultrachunkSecondarySampleID = nil
    }

    private func triggerHOTASEffectsAccentsLegacy(
        selectedID: String,
        candidateIDs: [String],
        baseGain: Double,
        nowMs: TimeInterval
    ) {
        if effectsChainState.chainAActive, effectsChainState.chainAIntensity > 0.08 {
            if nowMs - hotasLastRhythmAccentAtMs >= 140,
               let sampleURL = samplePackEntries[selectedID] {
                hotasLastRhythmAccentAtMs = nowMs
                let intensity = effectsChainState.chainAIntensity
                let accents = max(1, Int((intensity * 2.2).rounded()))
                let spacingSeconds = max(0.035, 0.08 - (intensity * 0.045))
                for step in 1 ... accents {
                    let accentGain = min(0.82, max(0.10, baseGain * (0.65 - (0.12 * Double(step - 1)))))
                    DispatchQueue.main.asyncAfter(deadline: .now() + (spacingSeconds * Double(step))) { [weak self] in
                        guard let self else { return }
                        try? self.quadAudioEngine.triggerSample(url: sampleURL, gain: accentGain)
                    }
                }
            }
        }

        if effectsChainState.chainBActive,
           effectsChainState.chainBIntensity > 0.08,
           nowMs - hotasLastSpaceAccentAtMs >= 220,
           let sourceIndex = candidateIDs.firstIndex(of: selectedID) {
            hotasLastSpaceAccentAtMs = nowMs
            let intensity = effectsChainState.chainBIntensity
            let spread = max(1, Int((Double(candidateIDs.count) * (0.04 + intensity * 0.12)).rounded()))
            let direction = hotasSampleSpaceZ >= 0.5 ? 1 : -1
            let neighborIndex = min(max(0, sourceIndex + (direction * spread)), candidateIDs.count - 1)
            let neighborID = candidateIDs[neighborIndex]
            if neighborID != selectedID,
               let neighborURL = samplePackEntries[neighborID] {
                let accentGain = min(0.78, max(0.10, baseGain * (0.48 + intensity * 0.30)))
                let delay = max(0.04, 0.12 - (intensity * 0.05))
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    try? self.quadAudioEngine.triggerSample(url: neighborURL, gain: accentGain)
                }
            }
        }
    }

    private func triggerHOTASLegacyStretchLayerIfNeeded(
        sampleURL: URL,
        axisDelta: Double,
        dynamicMode: Bool,
        nowMs: TimeInterval
    ) {
        let spaceInfluence = effectsChainState.chainBActive ? effectsChainState.chainBIntensity : 0
        let textureInfluence = dynamicMode
            ? performerProceduralState.fade
            : staticAudioMacroState.textureSend
        let movementInfluence = min(1, axisDelta * 3.4)
        let impetus = max(spaceInfluence, max(textureInfluence, movementInfluence))
        guard impetus >= 0.20 else { return }

        let cooldownMs = max(180, 520 - (impetus * 300))
        guard nowMs - hotasLastPaulstretchAtMs >= cooldownMs else { return }
        hotasLastPaulstretchAtMs = nowMs

        let rate = max(0.06, min(0.34, 0.32 - (impetus * 0.24)))
        let gain = max(0.08, min(0.38, 0.09 + (impetus * 0.21)))

        do {
            try quadAudioEngine.triggerPaulstretchedSample(
                url: sampleURL,
                gain: gain,
                rate: rate
            )
        } catch {
            // Additive only; dry/ultrachunk paths are already active.
        }
    }

    private func maybeTriggerHOTASPaulstretchMorphFromXY(
        primaryURL: URL,
        secondaryURL: URL?,
        frame: UltrachunkControlFrame,
        axis: HOTASSampleSpaceAxis,
        axisDelta: Double,
        dynamicMode: Bool,
        nowMs: TimeInterval
    ) {
        guard axis == .x || axis == .y else { return }

        let movement = ConductorHarnessViewModel.clamp01((axisDelta * 8.5) + (frame.speed * 0.72))
        let textureBias = dynamicMode ? performerProceduralState.fade : staticAudioMacroState.textureSend
        let spaceBias = effectsChainState.chainBActive ? effectsChainState.chainBIntensity : 0
        let impetus = max(movement, max(textureBias, spaceBias))
        guard impetus >= 0.14 else { return }

        let cooldownMs = max(115, 420 - (impetus * 260))
        guard nowMs - hotasLastPaulstretchMorphAtMs >= cooldownMs else { return }
        hotasLastPaulstretchMorphAtMs = nowMs

        let forward = ConductorHarnessViewModel.remap01(frame.y, min: 0.5, max: 1)
        let back = ConductorHarnessViewModel.remap01(1 - frame.y, min: 0.5, max: 1)
        let stretchRate = max(0.05, min(0.32, 0.30 - (impetus * 0.16) - (forward * 0.08) + (back * 0.04)))
        let baseGain = max(0.07, min(0.44, 0.10 + (impetus * 0.28) + (forward * 0.08)))

        do {
            try quadAudioEngine.triggerPaulstretchedSample(
                url: primaryURL,
                gain: baseGain,
                rate: stretchRate
            )

            guard let secondaryURL else { return }
            let xEdgeWeight = abs(frame.x - 0.5) * 2
            let secondaryMix = ConductorHarnessViewModel.clamp01(0.26 + (xEdgeWeight * 0.52) + (movement * 0.24))
            let secondaryGain = max(0.05, min(0.38, baseGain * secondaryMix))
            let secondaryRate = max(0.05, min(0.34, stretchRate * (0.92 + (forward * 0.14) + (xEdgeWeight * 0.08))))
            let delay = max(0.02, 0.06 - (impetus * 0.03))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                try? self.quadAudioEngine.triggerPaulstretchedSample(
                    url: secondaryURL,
                    gain: secondaryGain,
                    rate: secondaryRate
                )
            }
        } catch {
            if nowMs - hotasStaticSampleAuditionLastStatusAtMs >= 900 {
                hotasStaticSampleAuditionLastStatusAtMs = nowMs
                pushStatus(StatusLineEvent(
                    message: "Paulstretch morph failed: \(error.localizedDescription)",
                    severity: .error,
                    timestamp: Date()
                ))
            }
        }
    }

    private func maybeEmitHOTASStaticAuditionStatus(
        _ message: String,
        severity: StatusLineSeverity,
        minIntervalMs: TimeInterval = 900
    ) {
        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        guard nowMs - hotasStaticSampleAuditionLastStatusAtMs >= minIntervalMs else { return }
        hotasStaticSampleAuditionLastStatusAtMs = nowMs
        pushStatus(StatusLineEvent(
            message: message,
            severity: severity,
            timestamp: Date()
        ))
    }

    @discardableResult
    private func ensureScoringEngineReady(operation: String) -> Bool {
        guard engineRunning else { return false }
        if quadAudioEngine.isRunning {
            return true
        }

        do {
            let route = try quadAudioEngine.start()
            applyRouteStatus(route, emitStatus: true)
            pushStatus(StatusLineEvent(
                message: "\(operation): audio engine recovered",
                severity: .info,
                timestamp: Date()
            ))
            return true
        } catch {
            engineRunning = false
            resetAudioRouteStatus()
            pushStatus(StatusLineEvent(
                message: "\(operation) failed: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
            return false
        }
    }

    @discardableResult
    func acceptActiveProposalFromControl() -> MLProposalDecision {
        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        let accepted = cognitiveProposalEngine.acceptActiveProposal(nowMs: nowMs)
        lastMLProposalDecision = accepted.decision
        activeMLProposalCountdownSeconds = nil

        guard let proposal = accepted.proposal else {
            pushStatus(StatusLineEvent(
                message: "ML accept blocked: no active proposal",
                severity: .warn,
                timestamp: Date()
            ))
            Task { [hudTelemetryStore] in
                await hudTelemetryStore.ingestSystem(
                    stage: .applied,
                    severity: .block,
                    controlID: "ml:proposal",
                    semanticAction: "proposal_accept",
                    outcome: "BLOCKED",
                    detail: "No active proposal"
                )
            }
            activeMLProposal = nil
            refreshProgramAudioState(nowMs: nowMs)
            return .blocked
        }

        switch accepted.decision {
        case .accepted:
            cognitiveProposalEngine.observeAction(
                label: "proposal_accept_\(proposal.lane.rawValue)",
                timestampMs: nowMs
            )
            let outcome = applyAcceptedProposal(proposal)
            let message = outcome ?? proposal.expectedEffect
            handleProposalLifecycleEvent(CognitiveProposalLifecycleEvent(
                proposal: proposal,
                decision: .accepted,
                message: message
            ))
            activeMLProposal = nil
            refreshProgramAudioState(nowMs: nowMs)
            return .accepted

        case .expired:
            handleProposalLifecycleEvent(CognitiveProposalLifecycleEvent(
                proposal: proposal,
                decision: .expired,
                message: "Acceptance window expired"
            ))
            activeMLProposal = nil
            refreshProgramAudioState(nowMs: nowMs)
            return .expired

        case .rejected:
            handleProposalLifecycleEvent(CognitiveProposalLifecycleEvent(
                proposal: proposal,
                decision: .rejected,
                message: "Proposal rejected"
            ))
            activeMLProposal = nil
            refreshProgramAudioState(nowMs: nowMs)
            return .rejected

        case .blocked:
            handleProposalLifecycleEvent(CognitiveProposalLifecycleEvent(
                proposal: proposal,
                decision: .blocked,
                message: "Acceptance blocked"
            ))
            activeMLProposal = nil
            refreshProgramAudioState(nowMs: nowMs)
            return .blocked
        }
    }

    private func applyAcceptedProposal(_ proposal: MLProposal) -> String? {
        switch proposal.lane {
        case .audio:
            guard let payload = proposal.audio else {
                return "Audio proposal missing payload"
            }

            guard engineRunning else {
                pushStatus(StatusLineEvent(
                    message: "ML AUDIO accept blocked: engine is stopped",
                    severity: .warn,
                    timestamp: Date()
                ))
                return "Blocked: engine stopped"
            }

            guard outputRouteReady else {
                pushStatus(StatusLineEvent(
                    message: "ML AUDIO accept blocked: route not ready",
                    severity: .warn,
                    timestamp: Date()
                ))
                return "Blocked: route not ready"
            }

            if let bank = payload.suggestedBank {
                applySampleBankSelection(bank, domain: .main, emitStatus: false)
            }
            if let chainA = payload.chainAIntensityTarget {
                setEffectsChainFromControl(chain: .a, active: chainA > 0.05, intensity: chainA)
            }
            if let chainB = payload.chainBIntensityTarget {
                setEffectsChainFromControl(chain: .b, active: chainB > 0.05, intensity: chainB)
            }

            if let sampleID = payload.suggestedSampleID,
               samplePackEntries[sampleID] != nil {
                selectedSampleID = sampleID
            }

            switch payload.kind {
            case .textureNudge:
                triggerSamplePlayback()
                proposalStructuredLatchActive = false
                return "Audio nudge fired"

            case .structuredLatch:
                proposalStructuredLatchActive = true
                triggerSamplePlayback()
                if let target = payload.densityTarget, target > 0.45 {
                    quadAudioEngine.startAmbientNoise(gain: 0.07)
                }
                return "Structured latch armed"
            }

        case .visualText:
            guard let payload = proposal.visualText else {
                return "Visual/text proposal missing payload"
            }
            updatePerformerProceduralState { state in
                if let value = payload.dynamicBinSelection {
                    state.dynamicBinSelection = value
                }
                if let transition = payload.transitionMode {
                    state.transitionMode = transition
                }
                if let compositor = payload.compositorPreset {
                    state.compositorPreset = compositor
                }
                if let splitLayout = payload.splitLayout {
                    state.splitLayout = splitLayout
                }
                if let fade = payload.fade {
                    state.fade = fade
                }
                if let probability = payload.textProbability {
                    state.textProbability = probability
                }
                if let blend = payload.strictLooseBlend {
                    state.strictLooseBlend = blend
                }
            }
            return "Visual/text modulation applied"
        }
    }

    private func applySampleBankSelection(
        _ bank: Int,
        domain: SampleBankDomain,
        emitStatus: Bool,
        forceSelectionRefresh: Bool = false
    ) {
        let clampedBank = min(3, max(1, bank))
        let previousBank: Int
        switch domain {
        case .main:
            previousBank = activeSampleBank
            activeSampleBank = clampedBank
        case .choir:
            previousBank = activeChoirSampleBank
            activeChoirSampleBank = clampedBank
        }

        let changed = previousBank != clampedBank
        guard changed || forceSelectionRefresh else { return }

        let preferredIDs: [String]
        switch domain {
        case .main:
            preferredIDs = mainBankSampleIDs(for: clampedBank)
        case .choir:
            preferredIDs = hotasProfile.sampleBanks.sampleIDs(for: clampedBank, domain: domain)
        }
        if let firstExisting = preferredIDs.first(where: { samplePackEntries[$0] != nil }) {
            selectedSampleID = firstExisting
        }
        if domain == .main {
            applyStaticSampleMorphSelection()
            updateEffectsPresetForActiveBank()
            publishPushPadLabelsForActiveMainBank()
        }

        recordSoundManipulationFocus(
            lane: domain == .choir ? "BANK SELECT CHOIR" : "BANK SELECT MAIN",
            value: Double(clampedBank) / 3.0,
            controlIDHint: domain == .choir ? "bank:choir" : "bank:main"
        )

        refreshProgramAudioState(nowMs: ConductorHarnessViewModel.nowMilliseconds())
        guard emitStatus else { return }
        let domainLabel = domain == .choir ? "Choir" : "Main"
        pushStatus(StatusLineEvent(
            message: "\(domainLabel) sample bank selected: \(clampedBank)",
            severity: .info,
            timestamp: Date()
        ))
    }

    private func updateEffectsPresetForActiveBank() {
        let candidateIDs = mainBankSampleIDs(for: activeSampleBank)
        let renderClass = candidateIDs
            .compactMap { sampleMetadataByID[$0]?.renderClass }
            .first ?? .misc
        activeEffectsPreset = EffectsChainPreset(
            chainAName: "Rhythm",
            chainBName: "Space",
            bankID: activeSampleBank,
            renderClass: renderClass
        )
    }

    private func updatePerformerProceduralState(_ mutate: (inout ProgramProceduralState) -> Void) {
        var next = performerProceduralState
        mutate(&next)
        syncDerivedProceduralStateFields(&next)

        guard next != performerProceduralState else { return }

        next.epoch = performerProceduralState.epoch + 1
        next.updatedAt = Date().timeIntervalSince1970 * 1000
        performerProceduralState = next
        programProceduralState = next
        publishProceduralState()
    }

    private func syncDerivedProceduralStateFields(_ state: inout ProgramProceduralState) {
        state.dynamicBinManifest = dynamicBinManifest
        state.performerVector = vector
        state.textProbability = Self.clamp01(state.textProbability)
        state.strictLooseBlend = Self.clamp01(state.strictLooseBlend)
        state.visualVariance = Self.clamp01(state.visualVariance)
        state.fade = Self.clamp01(state.fade)
        state.cutCadence = Self.clamp01(state.cutCadence)
        state.dynamicBinSelection = Self.clamp01(state.dynamicBinSelection)

        if dynamicBinManifest.isEmpty {
            state.dynamicBinIndex = 0
            state.dynamicBinClipId = nil
        } else {
            let maxIndex = dynamicBinManifest.count - 1
            let index = Int((state.dynamicBinSelection * Double(maxIndex)).rounded())
            let safeIndex = min(max(0, index), maxIndex)
            state.dynamicBinIndex = safeIndex
            state.dynamicBinClipId = dynamicBinManifest[safeIndex].id
        }
        state.updateBlend()
    }

    private func publishProceduralState(force: Bool = false) {
        var payload = performerProceduralState
        syncDerivedProceduralStateFields(&payload)
        let linkReady = websocket.state == .online || websocket.state == .degraded
        if !force, !linkReady {
            return
        }
        if !force, let last = lastSentProceduralState, last == payload {
            return
        }
        lastSentProceduralState = payload

        Task {
            do {
                try await websocket.sendEnvelope(kind: "procedural_state", data: payload)
            } catch {
                await MainActor.run {
                    self.lastLinkError = error.localizedDescription
                    self.pushStatus(StatusLineEvent(
                        message: "Procedural state dispatch failed: \(error.localizedDescription)",
                        severity: .warn,
                        timestamp: Date()
                    ))
                }
            }
        }
    }

    private func resolveModelBundleURL(from selectedURL: URL) -> URL? {
        if selectedURL.pathExtension.lowercased() == "mlmodelc" {
            return selectedURL
        }

        let nested = CoreMLModelLocator.discoverCompiledModels(in: [selectedURL])
        return nested.first?.url
    }

    private func rebuildDynamicBinManifest() {
        var manifest: [DynamicBinClip] = []

        for lane in showFixedLanes {
            manifest.append(DynamicBinClip(
                id: lane.id,
                mediaRef: lane.mediaURL.path,
                tags: ["dynamic", "lane", lane.id],
                weight: 1.0,
                scopes: ["main", "dynamic"]
            ))
        }

        for (state, url) in sceneMediaURLs.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            manifest.append(DynamicBinClip(
                id: "scene-\(state.rawValue)",
                mediaRef: url.path,
                tags: ["dynamic", "scene", state.rawValue],
                weight: 0.8,
                scopes: ["dynamic"]
            ))
        }

        if let interstitialMediaURL {
            manifest.append(DynamicBinClip(
                id: "interstitial",
                mediaRef: interstitialMediaURL.path,
                tags: ["dynamic", "interstitial"],
                weight: 0.6,
                scopes: ["dynamic", "fallback"]
            ))
        }

        if manifest == dynamicBinManifest {
            return
        }

        dynamicBinManifest = manifest
        updatePerformerProceduralState { state in
            state.dynamicBinManifest = manifest
        }
    }

    private func updatePreviewForCurrentMode() {
        let cue = latestCue ?? CueCommand(cueId: "\(state.rawValue):0", showState: state, logicalTime: 0, action: .jump)
        updatePreview(for: cue)
    }

    private func updatePreview(for cue: CueCommand, outputProfile: OutputProfile? = nil) {
        let profile = outputProfile ?? resolveOutputProfile(for: cue.showState)
        effectiveOutputMode = profile.mode
        previewScene = cue.showState
        previewPlayer.isMuted = true
        previewPlayer.volume = 0

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
            previewPlayer.replaceCurrentItem(with: makeLowLatencyPreviewItem(url: mediaURL))
        }

        let seekSeconds = profile.usesInterstitialMedia ? 0 : max(0, cue.logicalTime)
        if shouldSeekPreview(
            replacingItem: replacingPreviewItem,
            targetSeconds: seekSeconds
        ) {
            let seekTime = CMTime(seconds: seekSeconds, preferredTimescale: 600)
            let seekTolerance = CMTime(seconds: 0.02, preferredTimescale: 600)
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
                let loopTolerance = CMTime(seconds: 0.01, preferredTimescale: 600)
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

    private func configurePreviewPlayerForPerformanceMode() {
        previewPlayer.automaticallyWaitsToMinimizeStalling = false
        previewPlayer.allowsExternalPlayback = false
        previewPlayer.preventsDisplaySleepDuringVideoPlayback = false
        previewPlayer.isMuted = true
        previewPlayer.volume = 0
    }

    private func makeLowLatencyPreviewItem(url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        return item
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
        let timelineLaneId = outputProfile.showFixedLaneId.flatMap { laneId in
            timelineStepPlan(for: laneId) != nil ? laneId : nil
        }
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

            if let timelineLaneId {
                let now = Date()
                self.timelineStepPlaybackWindows[timelineLaneId] = DateInterval(start: now, duration: duration)
            }

            self.cancelSequenceWork()
            self.scheduleSequenceStep(after: duration) { [weak self] in
                guard let self else { return }
                guard self.latestCue?.cueId == sourceCueId else { return }
                guard self.committedOutputMode == .static else { return }

                if let timelineLaneId,
                   let activeWindow = self.timelineStepPlaybackWindows[timelineLaneId] {
                    let finishedWindow = DateInterval(
                        start: activeWindow.start,
                        end: max(Date(), activeWindow.end)
                    )
                    self.timelineStepPlaybackWindows[timelineLaneId] = finishedWindow
                }

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
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
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
        let wasArmed = isLatchArmed
        let previousExpiresAt = latchExpiresAt

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

        syncLatchExpiryTimer(with: snapshot)

        if canFireGO != snapshot.canFire {
            canFireGO = snapshot.canFire
        }

        let nextSummary = snapshot.summary
        if latchSummary != nextSummary {
            latchSummary = nextSummary
        }

        // Countdown rendering is local to the countdown view (TimelineView),
        // so we only refresh this fallback value when latch boundaries change.
        if wasArmed != snapshot.isArmed || previousExpiresAt != snapshot.expiresAt {
            latchCountdownSeconds = snapshot.countdownSeconds(at: now)
        }
        if lastLatchStatus != snapshot.status {
            lastLatchStatus = snapshot.status
            pushStatus(snapshot.status)
        }
    }

    private func syncLatchExpiryTimer(with snapshot: OutputLatchSnapshot) {
        guard let latchId = snapshot.latchId,
              let expiresAt = snapshot.expiresAt else {
            cancelLatchExpiryTimer()
            return
        }

        if scheduledLatchExpiryID == latchId,
           let scheduledLatchExpiryAt,
           abs(scheduledLatchExpiryAt.timeIntervalSince(expiresAt)) < 0.001 {
            return
        }

        cancelLatchExpiryTimer()
        scheduledLatchExpiryID = latchId
        scheduledLatchExpiryAt = expiresAt

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleLatchExpiryDeadline(expectedLatchID: latchId)
            }
        }
        latchExpiryTimer = timer
        timer.resume()
    }

    private func cancelLatchExpiryTimer() {
        latchExpiryTimer?.setEventHandler {}
        latchExpiryTimer?.cancel()
        latchExpiryTimer = nil
        scheduledLatchExpiryID = nil
        scheduledLatchExpiryAt = nil
    }

    private func handleLatchExpiryDeadline(expectedLatchID: String) {
        guard latchController.snapshot.latchId == expectedLatchID else { return }
        guard latchController.snapshot.expiresAt != nil else { return }
        let now = Date().addingTimeInterval(0.001)
        let snapshot = latchController.tick(now: now)
        syncLatchState(snapshot, now: now)
    }

    private func applyModelHealth(_ report: ModelHealthReport) {
        modelHealthLevel = report.level
        modelHealthSummary = report.summary
        modelChecks = report.checks
        modelRuntimeFailures = report.runtimeFailureCount
    }

    // MARK: - HOTAS controls

    var hotasProfileBindings: [ControlBinding] {
        hotasProfile.bindings.sorted { lhs, rhs in
            lhs.role.rawValue < rhs.role.rawValue
        }
    }

    func hotasBinding(for role: ControlRole) -> ControlBinding? {
        hotasProfile.firstBinding(for: role)
    }

    func hotasBindings(for role: ControlRole) -> [ControlBinding] {
        hotasProfile.bindings
            .filter { $0.role == role }
            .sorted { lhs, rhs in
                lhs.controlID.localizedCaseInsensitiveCompare(rhs.controlID) == .orderedAscending
            }
    }

    func updateHOTASInputMode(_ mode: ControlInputMode) {
        hotasInputMode = mode
        hotasProfile.inputMode = mode
        persistControlProfileDocument()
        refreshHOTASActivation()
    }

    func updateHOTASStaticVideoOverride(_ enabled: Bool) {
        guard hotasStaticVideoOverrideEnabled != enabled else { return }
        hotasStaticVideoOverrideEnabled = enabled
        persistControlProfileDocument()
    }

    private func resetHOTASCaptureState() {
        hotasCaptureRole = nil
        hotasCaptureExpectedKinds = Set(ControlSignalKind.allCases)
        hotasPendingCaptureRole = nil
        hotasCaptureAxisCandidateControlID = nil
        hotasCaptureAxisCandidateSamples = 0
        hotasCaptureAxisCandidateStrength = 0
        hotasCaptureAxisCandidateUpdatedAtMs = 0
        hotasCaptureArmedAtMs = 0
        hotasCaptureBaselineByControlKey.removeAll()
    }

    func beginHOTASTraining() {
        hotasTrainingBackupProfile = hotasProfile
        hotasTrainingActive = true
        resetHOTASCaptureState()
        hotasObservedByControlKey.removeAll()
        hotasObservedSignals = []
        hotasLastSignal = nil
        hotasLastSignalSummary = "Training active. Move a control to begin capture."
        refreshHOTASActivation()
    }

    func ensureHOTASTrainingSession() {
        if !hotasTrainingActive {
            beginHOTASTraining()
        }
    }

    func captureHOTASBinding(for role: ControlRole) {
        guard hotasTrainingActive else { return }
        hotasCaptureRole = role
        hotasCaptureExpectedKinds = expectedCaptureKinds(for: role)
        hotasPendingCaptureRole = role
        hotasCaptureAxisCandidateControlID = nil
        hotasCaptureAxisCandidateSamples = 0
        hotasCaptureAxisCandidateStrength = 0
        hotasCaptureAxisCandidateUpdatedAtMs = 0
        hotasCaptureArmedAtMs = ConductorHarnessViewModel.nowMilliseconds()
        hotasCaptureBaselineByControlKey = hotasObservedByControlKey
        let expected = hotasCaptureExpectedKinds
            .map(\.rawValue)
            .sorted()
            .joined(separator: "/")
        hotasLastSignalSummary = "Capturing \(role.rawValue) (\(expected))... actuate control now"
    }

    func clearHOTASBinding(for role: ControlRole) {
        hotasProfile.bindings.removeAll { $0.role == role }
        publishHOTASProfileValidation()
    }

    func clearAllHOTASBindings() {
        hotasProfile.bindings.removeAll()
        resetHOTASCaptureState()
        hotasLastSignalSummary = "Cleared all HOTAS bindings"
        publishHOTASProfileValidation()
    }

    func assignHOTASBinding(
        role: ControlRole,
        controlID: String,
        kind: ControlSignalKind,
        sourceKind: ControlSourceKind = .hotas,
        sourceDeviceID: String? = nil,
        logicalDevice: HOTASLogicalDevice? = nil
    ) {
        var calibration = hotasProfile.firstBinding(for: role)?.calibration ?? .default
        if role == .rightStickY, hotasProfile.firstBinding(for: role) == nil {
            calibration = CalibrationSpec(
                minimum: 0,
                maximum: 1,
                center: 0.5,
                deadzone: 0.03,
                hysteresis: 0.05,
                inverted: true
            )
        }

        let resolvedLogical: HOTASLogicalDevice? = {
            if sourceKind == .hotas {
                return logicalDevice ?? role.preferredHOTASLogicalDevice ?? .unspecified
            }
            return logicalDevice
        }()

        let resolvedSourceDeviceID: String? = sourceDeviceID

        let binding = ControlBinding(
            role: role,
            controlID: controlID,
            sourceKind: sourceKind,
            sourceDeviceID: resolvedSourceDeviceID,
            logicalDevice: resolvedLogical,
            kind: kind,
            calibration: calibration
        )
        hotasProfile.setBinding(binding)
        publishHOTASProfileValidation()
        hotasLastSignalSummary = "Mapped \(role.rawValue) -> \(controlID)"
    }

    func assignHOTASBinding(role: ControlRole, from signal: ControlSignal) {
        let logical: HOTASLogicalDevice? = {
            guard signal.sourceKind == .hotas else { return nil }
            return role.preferredHOTASLogicalDevice
                ?? HOTASLogicalDeviceMatcher.classify(sourceDeviceID: signal.sourceDeviceID, controlID: signal.controlID)
        }()
        assignHOTASBinding(
            role: role,
            controlID: signal.controlID,
            kind: signal.kind,
            sourceKind: signal.sourceKind,
            sourceDeviceID: signal.sourceDeviceID,
            logicalDevice: logical
        )
    }

    func updateHOTASCalibration(for role: ControlRole, calibration: CalibrationSpec) {
        guard let existing = hotasProfile.firstBinding(for: role) else { return }
        let updated = ControlBinding(
            role: existing.role,
            controlID: existing.controlID,
            sourceKind: existing.sourceKind,
            sourceDeviceID: existing.sourceDeviceID,
            logicalDevice: existing.logicalDevice,
            kind: existing.kind,
            calibration: calibration,
            required: existing.required
        )
        hotasProfile.setBinding(updated)
        publishHOTASProfileValidation()
    }

    func applyHOTASStrictLiveDefaults() {
        hotasProfile = .defaultX56StrictLive
        hotasProfile.enabled = false
        hotasControlsEnabled = false
        hotasInputMode = hotasProfile.inputMode
        hotasLastSignalSummary = "Applied X56 Strict Live defaults"
        persistControlProfileDocument()
        publishHOTASProfileValidation()
        refreshHOTASActivation()
    }

    func saveHOTASDraft() {
        hotasProfile.inputMode = hotasInputMode
        hotasProfile.enabled = false
        hotasControlsEnabled = false
        persistControlProfileDocument()
        publishHOTASProfileValidation()
        refreshHOTASActivation()
        pushStatus(StatusLineEvent(
            message: "HOTAS draft saved",
            severity: .info,
            timestamp: Date()
        ))
    }

    func cancelHOTASTraining() {
        if let backup = hotasTrainingBackupProfile {
            hotasProfile = backup
            hotasInputMode = backup.inputMode
        }
        hotasTrainingBackupProfile = nil
        hotasTrainingActive = false
        resetHOTASCaptureState()
        hotasLastSignalSummary = "HOTAS training cancelled"
        publishHOTASProfileValidation()
        refreshHOTASActivation()
    }

    func finishHOTASTrainingForLiveControl() {
        guard hotasTrainingActive else { return }
        hotasTrainingBackupProfile = nil
        hotasTrainingActive = false
        resetHOTASCaptureState()
        hotasLastSignalSummary = hotasControlsEnabled
            ? "HOTAS training ended. Live routing active."
            : "HOTAS training ended."
        publishHOTASProfileValidation()
        refreshHOTASActivation()
    }

    func saveAndArmHOTASProfile() {
        hotasProfile.inputMode = hotasInputMode
        hotasProfile.enabled = true
        hotasControlsEnabled = true
        hotasTrainingActive = false
        resetHOTASCaptureState()
        hotasTrainingBackupProfile = nil

        let missing = hotasProfile.missingRequiredRoles()
        let conflicts = hotasConflicts(for: hotasProfile)
        if missing.isEmpty, conflicts.isEmpty {
            hotasLastKnownGoodProfile = hotasProfile
            pushStatus(StatusLineEvent(
                message: "HOTAS profile armed",
                severity: .success,
                timestamp: Date()
            ))
        } else {
            hotasControlsEnabled = false
            hotasProfile.enabled = false
            pushStatus(StatusLineEvent(
                message: "HOTAS profile invalid: missing \(missing.count), conflicts \(conflicts.count)",
                severity: .warn,
                timestamp: Date()
            ))
        }

        persistControlProfileDocument()
        publishHOTASProfileValidation()
        refreshHOTASActivation()
    }

    func disableHOTASControls() {
        hotasControlsEnabled = false
        hotasProfile.enabled = false
        hotasTrainingActive = false
        resetHOTASCaptureState()
        persistControlProfileDocument()
        refreshHOTASActivation()
        pushStatus(StatusLineEvent(
            message: "HOTAS controls disabled",
            severity: .warn,
            timestamp: Date()
        ))
    }

    func revertHOTASToLastKnownGood() {
        guard let hotasLastKnownGoodProfile else {
            pushStatus(StatusLineEvent(
                message: "HOTAS revert unavailable: no last-known-good profile",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }
        hotasProfile = hotasLastKnownGoodProfile
        hotasInputMode = hotasLastKnownGoodProfile.inputMode
        hotasControlsEnabled = hotasLastKnownGoodProfile.enabled
        hotasTrainingActive = false
        resetHOTASCaptureState()
        persistControlProfileDocument()
        publishHOTASProfileValidation()
        refreshHOTASActivation()
        pushStatus(StatusLineEvent(
            message: "HOTAS profile reverted to last-known-good",
            severity: .info,
            timestamp: Date()
        ))
    }

    func availableHOTASDevices() -> [HOTASDeviceDescriptor] {
        IOHIDHOTASControlSignalSource.availableDevices()
    }

    private func hotasConflicts(for profile: ControlProfile) -> [String] {
        hotasConflictSummary(for: profile).messages
    }

    private func hotasConflictSummary(for profile: ControlProfile) -> (messages: [String], roles: Set<ControlRole>) {
        var grouped: [String: [ControlRole]] = [:]
        for binding in profile.bindings {
            let key = "\(binding.sourceKind?.rawValue ?? "any"):\(binding.sourceDeviceID ?? binding.logicalDevice?.rawValue ?? "any-device"):\(binding.controlID)"
            grouped[key, default: []].append(binding.role)
        }

        var conflictRoles = Set<ControlRole>()
        let messages = grouped.compactMap { entry -> String? in
            let (key, roles) = entry
            guard roles.count > 1 else { return nil }
            roles.forEach { conflictRoles.insert($0) }
            let labels = roles.map(\.rawValue).sorted().joined(separator: ", ")
            return "\(key) -> \(labels)"
        }
        .sorted()
        return (messages, conflictRoles)
    }

    private func migrateControlProfileForProposalSupport(_ profile: inout ControlProfile) -> Bool {
        var changed = false

        let cueRoles: Set<ControlRole> = [.leftCueToggleUp, .leftCueToggleDown, .leftCueToggleCenter]
        let beforeCueCount = profile.bindings.count
        profile.bindings.removeAll { binding in
            binding.sourceKind == .hotas && cueRoles.contains(binding.role)
        }
        if profile.bindings.count != beforeCueCount {
            changed = true
        }

        if profile.firstBinding(for: .rightAcceptButton) == nil {
            profile.setBinding(ControlBinding(
                role: .rightAcceptButton,
                controlID: "btn:1",
                sourceKind: .hotas,
                kind: .button
            ))
            changed = true
        }

        if profile.firstBinding(for: .leftStaticVisualClutch) == nil {
            profile.setBinding(ControlBinding(
                role: .leftStaticVisualClutch,
                controlID: "btn:12",
                sourceKind: .hotas,
                kind: .button
            ))
            changed = true
        }

        let modeRotaryBindings = profile.bindings.filter {
            $0.role == .leftModeRotary && $0.sourceKind == .hotas
        }
        let hasDiscreteModeRotary = modeRotaryBindings.contains { $0.kind == .button }
        let usesLegacyDialModeRotary = modeRotaryBindings.contains {
            HOTASLogicalDeviceMatcher.normalizedControlID($0.controlID) == "gd:dial"
        }
        if usesLegacyDialModeRotary, !hasDiscreteModeRotary {
            profile.bindings.removeAll { $0.role == .leftModeRotary && $0.sourceKind == .hotas }
            profile.setBinding(ControlBinding(role: .leftModeRotary, controlID: "btn:34", sourceKind: .hotas, kind: .button))
            profile.setBinding(ControlBinding(role: .leftModeRotary, controlID: "btn:35", sourceKind: .hotas, kind: .button))
            profile.setBinding(ControlBinding(role: .leftModeRotary, controlID: "btn:36", sourceKind: .hotas, kind: .button))
            changed = true
        }

        if let legacyRotaryIncreaseIndex = profile.bindings.firstIndex(where: {
            $0.role == .leftRotary1Increase && $0.sourceKind == .hotas
        }) {
            profile.bindings.remove(at: legacyRotaryIncreaseIndex)
            changed = true
        }

        let hotasButtonRoles: [ControlRole] = [
            .rightAcceptButton,
            .rightTakeButton,
            .rightTrigger1,
            .rightTrigger2,
            .ultrachunkOverlayToggle,
            .leftStaticVisualClutch
        ]

        func controlID(for role: ControlRole) -> String? {
            profile.bindings.first(where: { $0.role == role && $0.sourceKind == .hotas })?.controlID
        }

        if controlID(for: .rightAcceptButton) == "btn:1",
           controlID(for: .rightTakeButton) == "btn:1",
           let index = profile.bindings.firstIndex(where: { $0.role == .rightTakeButton && $0.sourceKind == .hotas }) {
            profile.bindings[index].controlID = "btn:2"
            changed = true
        }

        var usedByRole: [ControlRole: String] = [:]
        for role in hotasButtonRoles {
            if let controlID = controlID(for: role) {
                usedByRole[role] = controlID
            }
        }

        let usedIDs = Set(usedByRole.values)
        let fallbackIDs = ["btn:2", "btn:10", "btn:11", "btn:12", "btn:13", "btn:14", "btn:15", "btn:16"]

        func firstAvailable(excluding role: ControlRole) -> String {
            let used = Set(
                usedByRole
                    .filter { $0.key != role }
                    .map(\.value)
            )
            for candidate in fallbackIDs {
                if !used.contains(candidate) {
                    return candidate
                }
            }
            return "btn:31"
        }

        for role in hotasButtonRoles {
            guard let controlID = usedByRole[role] else { continue }
            let colliding = usedByRole.filter { $0.key != role && $0.value == controlID }
            guard !colliding.isEmpty else { continue }
            guard let index = profile.bindings.firstIndex(where: { $0.role == role && $0.sourceKind == .hotas }) else {
                continue
            }
            let reassigned = firstAvailable(excluding: role)
            profile.bindings[index].controlID = reassigned
            usedByRole[role] = reassigned
            changed = true
        }

        if !changed, usedIDs.contains("btn:1"), controlID(for: .rightAcceptButton) != "btn:1",
           let index = profile.bindings.firstIndex(where: { $0.role == .rightAcceptButton && $0.sourceKind == .hotas }) {
            profile.bindings[index].controlID = firstAvailable(excluding: .rightAcceptButton)
            changed = true
        }

        for index in profile.bindings.indices {
            guard profile.bindings[index].sourceKind == .hotas else {
                continue
            }

            if profile.bindings[index].logicalDevice == nil {
                if let preferred = profile.bindings[index].role.preferredHOTASLogicalDevice {
                    profile.bindings[index].logicalDevice = preferred
                    changed = true
                } else {
                    let classified = HOTASLogicalDeviceMatcher.classify(
                        sourceDeviceID: profile.bindings[index].sourceDeviceID ?? "",
                        controlID: profile.bindings[index].controlID
                    )
                    if classified != .unspecified {
                        profile.bindings[index].logicalDevice = classified
                        changed = true
                    }
                }
            }

        }

        return changed
    }

    private func publishHOTASProfileValidation() {
        hotasProfileName = hotasProfile.name
        hotasMissingRequiredRoles = hotasProfile.missingRequiredRoles()
        let conflictSummary = hotasConflictSummary(for: hotasProfile)
        hotasBindingConflicts = conflictSummary.messages
        hotasConflictRoles = conflictSummary.roles
        hotasControlsEnabled = hotasProfile.enabled
        hotasInputMode = hotasProfile.inputMode
    }

    private func refreshHOTASActivation() {
        publishHOTASProfileValidation()
        let shouldRun = hotasTrainingActive || (hotasControlsEnabled && hotasMissingRequiredRoles.isEmpty && hotasBindingConflicts.isEmpty)
        if shouldRun {
            startHOTASInputPipeline()
        } else {
            stopHOTASInputPipeline()
        }
    }

    private func startHOTASInputPipeline() {
        if hotasInputMultiplexer != nil {
            return
        }

        let mode = hotasTrainingActive ? hotasInputMode : hotasProfile.inputMode
        var sources: [ControlSignalSource] = []

        if mode.includesHOTAS {
            sources.append(IOHIDHOTASControlSignalSource())
        }
        if mode.includesMIDI, !selectedMIDIInputID.isEmpty {
            sources.append(CoreMIDIControlSignalSource(sourceID: selectedMIDIInputID))
        }

        guard !sources.isEmpty else {
            hotasInputActive = false
            hotasInputStatus = "HOTAS waiting for sources"
            return
        }

        let multiplexer = InputMultiplexer(sources: sources)
        hotasMapper = ControlProfileMapper(profile: hotasProfile)
        multiplexer.start { [weak self] signal in
            Task { @MainActor in
                self?.handleHOTASSignal(signal)
            }
        }
        hotasInputMultiplexer = multiplexer
        hotasInputActive = true
        hotasInputStatus = "HOTAS IN: \(mode.rawValue.uppercased())"
    }

    private func stopHOTASInputPipeline() {
        hotasInputMultiplexer?.stop()
        hotasInputMultiplexer = nil
        hotasMapper = nil
        hotasInputActive = false
        hotasInputStatus = hotasTrainingActive ? "HOTAS TRAINING PAUSED" : "HOTAS OFF"
    }

    private func recordHOTASSignalObservation(_ signal: ControlSignal) {
        let key = "\(signal.sourceDeviceID):\(signal.controlID)"
        hotasObservedByControlKey[key] = signal

        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        hotasObservedByControlKey = hotasObservedByControlKey.filter { _, observed in
            let observedMs = ConductorHarnessViewModel.normalizedMilliseconds(observed.timestamp)
            return (nowMs - observedMs) <= 7_500
        }

        guard shouldPublishHOTASMapperObservation(signal: signal, nowMs: nowMs) else {
            return
        }
        hotasLastObservationPublishAtMs = nowMs
        hotasLastSignal = signal
        hotasObservedSignals = hotasObservedByControlKey.values
            .sorted { lhs, rhs in
                ConductorHarnessViewModel.normalizedMilliseconds(lhs.timestamp)
                    > ConductorHarnessViewModel.normalizedMilliseconds(rhs.timestamp)
            }
            .prefix(24)
            .map { $0 }
    }

    private func handleHOTASSignal(_ signal: ControlSignal) {
        recordHOTASSignalObservation(signal)
        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        if shouldPublishHOTASSummary(signal: signal, nowMs: nowMs) {
            hotasLastSummaryPublishAtMs = nowMs
            hotasLastSignalSummary = "\(signal.sourceKind.rawValue.uppercased()) \(signal.sourceDeviceID) \(signal.controlID) \(String(format: "%.2f", signal.normalizedValue)) \(signal.phase.rawValue.uppercased())"
        }
        if !hotasTrainingActive {
            Task { [hudTelemetryStore] in
                await hudTelemetryStore.ingestRaw(signal: signal)
            }
        }

        if let role = hotasCaptureRole, hotasTrainingActive {
            guard signal.kind != .note else { return }
            let signalMs = ConductorHarnessViewModel.normalizedMilliseconds(signal.timestamp)
            guard signalMs >= hotasCaptureArmedAtMs + 24 else { return }

            let expectedKinds = hotasCaptureExpectedKinds
            let resolvedKind = inferredCaptureKind(for: role, signal: signal, expectedKinds: expectedKinds)
            let expectsDiscrete = expectedKinds.contains(.button) || expectedKinds.contains(.hat)
            let axisDiscreteMagnitude = abs(signal.normalizedValue - 0.5)
            let axisLooksDiscrete = signal.normalizedValue <= 0.2 || signal.normalizedValue >= 0.8
            let axisCanRepresentDiscrete = resolvedKind == .axis
                && expectsDiscrete
                && (axisDiscreteMagnitude >= 0.35 || axisLooksDiscrete)
            let captureKind: ControlSignalKind = {
                if expectedKinds.contains(resolvedKind) {
                    return resolvedKind
                }
                if axisCanRepresentDiscrete {
                    return expectedKinds.contains(.button) ? .button : .hat
                }
                return resolvedKind
            }()

            guard expectedKinds.contains(captureKind) else { return }

            let captureKey = "\(signal.sourceDeviceID):\(signal.controlID)"
            let baseline = hotasCaptureBaselineByControlKey[captureKey]

            if captureKind == .axis {
                guard signal.phase == .changed else { return }
                let baselineValue = baseline?.normalizedValue ?? 0.5
                let movement = abs(signal.normalizedValue - baselineValue)
                let strength = max(movement, abs(signal.normalizedValue - 0.5))
                guard strength >= 0.12 else { return }
            } else {
                let baselineActive: Bool = {
                    guard let baseline else { return false }
                    if signal.kind == .axis || resolvedKind == .axis {
                        let baselineMagnitude = abs(baseline.normalizedValue - 0.5)
                        return baselineMagnitude >= 0.35 || baseline.normalizedValue <= 0.2 || baseline.normalizedValue >= 0.8
                    }
                    return baseline.rawValue > 0
                }()
                let discreteActuated = signal.phase == .began
                    || ((signal.phase == .changed && signal.rawValue > 0) && !baselineActive)
                    || (axisCanRepresentDiscrete && !baselineActive)
                guard discreteActuated else { return }
            }
            assignHOTASBinding(
                role: role,
                controlID: signal.controlID,
                kind: captureKind,
                sourceKind: signal.sourceKind,
                sourceDeviceID: signal.sourceDeviceID,
                logicalDevice: role.preferredHOTASLogicalDevice
            )
            resetHOTASCaptureState()
            let logical = hotasProfile.firstBinding(for: role)?.logicalDevice?.rawValue ?? "device"
            hotasLastSignalSummary = "Captured \(role.rawValue) -> \(logical):\(signal.controlID)"
            return
        }

        guard hotasControlsEnabled, !hotasTrainingActive else { return }
        guard hotasMissingRequiredRoles.isEmpty else { return }

        if signal.sourceKind == .midi, signal.kind == .note {
            handleMIDINoteControlSignal(signal)
            return
        }

        if hotasMapper == nil || hotasMapper?.profile != hotasProfile {
            hotasMapper = ControlProfileMapper(profile: hotasProfile)
        }
        guard let hotasMapper else { return }

        let actions = hotasMapper.map(
            signal: signal,
            laneIDs: hotasLaneIDs(),
            context: hotasRuntimeContext()
        )
        if actions.isEmpty {
            maybeRouteFallbackHOTASStickAxis(signal)
        }
        for action in actions {
            routeHOTASControlAction(action, signal: signal)
        }
    }

    private func maybeRouteFallbackHOTASStickAxis(_ signal: ControlSignal) {
        guard signal.sourceKind == .hotas else { return }
        guard signal.kind == .axis, signal.phase == .changed else { return }
        let logical = HOTASLogicalDeviceMatcher.classify(
            sourceDeviceID: signal.sourceDeviceID,
            controlID: signal.controlID
        )
        guard logical == .x56Stick else { return }

        let normalizedID = HOTASLogicalDeviceMatcher.normalizedControlID(signal.controlID)
        let axis: HOTASSampleSpaceAxis
        let lane: String

        switch normalizedID {
        case "gd:x":
            axis = .x
            lane = "SRC X (fallback)"
        case "gd:y":
            axis = .y
            lane = "CUT Y (fallback)"
        case "gd:rz", "gd:slider", "gd:rx", "gd:ry":
            axis = .z
            lane = "COMP Z (fallback)"
        default:
            return
        }

        if hotasPhoneChoirContextActive {
            switch axis {
            case .x:
                setChoirFieldSpreadFromControl(signal.normalizedValue)
            case .y:
                setChoirFieldDepthFromControl(signal.normalizedValue)
            case .z:
                setChoirFieldDetuneFromControl(signal.normalizedValue)
            }
            return
        }

        if currentHOTASOutputModeID() == .dynamic {
            maybeTriggerHOTASDynamicSampleScoring(
                lane: lane,
                axis: axis,
                normalizedControlValue: signal.normalizedValue
            )
        } else {
            maybeTriggerHOTASStaticSampleAudition(
                lane: lane,
                axis: axis,
                normalizedControlValue: signal.normalizedValue
            )
        }

        recordSoundManipulationFocus(
            lane: lane,
            value: signal.normalizedValue,
            controlIDHint: normalizedID,
            sourceHint: "HOTAS"
        )
    }

    private func shouldPublishHOTASMapperObservation(signal: ControlSignal, nowMs: TimeInterval) -> Bool {
        if signal.kind != .axis || signal.phase != .changed {
            return true
        }
        if let last = hotasLastSignal,
           last.controlID == signal.controlID,
           last.sourceDeviceID == signal.sourceDeviceID,
           abs(last.normalizedValue - signal.normalizedValue) >= 0.08 {
            return true
        }
        return (nowMs - hotasLastObservationPublishAtMs) >= 180
    }

    private func shouldPublishHOTASSummary(signal: ControlSignal, nowMs: TimeInterval) -> Bool {
        if signal.kind != .axis || signal.phase != .changed {
            return true
        }
        if abs(signal.normalizedValue - 0.5) >= 0.2 {
            return (nowMs - hotasLastSummaryPublishAtMs) >= 140
        }
        return (nowMs - hotasLastSummaryPublishAtMs) >= 320
    }

    private func expectedCaptureKinds(for role: ControlRole) -> Set<ControlSignalKind> {
        role.captureKinds
    }

    private func inferredCaptureKind(
        for role: ControlRole,
        signal: ControlSignal,
        expectedKinds: Set<ControlSignalKind>
    ) -> ControlSignalKind {
        _ = role
        if signal.kind != .unknown {
            return signal.kind
        }
        if expectedKinds.contains(.axis), signal.phase == .changed {
            return .axis
        }
        if expectedKinds.contains(.button), signal.phase == .began || signal.phase == .ended {
            return .button
        }
        if expectedKinds.contains(.hat) {
            return .hat
        }
        if expectedKinds.contains(.button) {
            return .button
        }
        if expectedKinds.contains(.axis) {
            return .axis
        }
        return signal.kind
    }

    private func routeHOTASControlAction(_ action: ControlAction, signal: ControlSignal) {
        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestMapped(signal: signal, action: action)
        }
        cognitiveProposalEngine.observeAction(
            label: proposalActionLabel(for: action),
            timestampMs: ConductorHarnessViewModel.normalizedMilliseconds(signal.timestamp)
        )

        routedHOTASActionContext = RoutedHOTASActionContext(
            signal: signal,
            action: action,
            emittedAppliedEventFromStatus: false
        )
        let result = controlActionRouter.route(action)

        if let context = routedHOTASActionContext,
           !context.emittedAppliedEventFromStatus {
            let severity: HUDEventSeverity
            let outcome: String
            let blockReason: String?
            switch result {
            case .applied:
                severity = .apply
                outcome = "ROUTED"
                blockReason = nil
            case .blocked(let reason):
                severity = .block
                outcome = "BLOCKED"
                blockReason = reason
            }
            Task { [hudTelemetryStore] in
                await hudTelemetryStore.ingestApplied(
                    signal: signal,
                    action: action,
                    severity: severity,
                    outcome: outcome,
                    blockReason: blockReason,
                    detail: nil
                )
            }
        }
        routedHOTASActionContext = nil
    }

    private func handlePushDeckEvent(_ event: PushDeckEventPayload) {
        let sourceID = event.sourceId.lowercased()
        recordPushControllerSeen(sourceID)
        pushLastSignalSummary = pushDeckEventSummary(event)

        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestSystem(
                stage: .raw,
                severity: .info,
                controlID: "push:\(sourceID)",
                semanticAction: event.controlKind.rawValue,
                outcome: "OBSERVED",
                detail: pushDeckEventSummary(event)
            )
        }

        if !pushControlEnabled, trustedPushControllerIDSet.isEmpty {
            pushControlEnabled = true
            persistControlProfileDocument()
            pushStatus(StatusLineEvent(
                message: "Push lane auto-enabled for first controller",
                severity: .success,
                timestamp: Date()
            ))
        }

        guard pushControlEnabled else {
            Task { [hudTelemetryStore] in
                await hudTelemetryStore.ingestSystem(
                    stage: .applied,
                    severity: .block,
                    controlID: "push:\(sourceID)",
                    semanticAction: event.controlKind.rawValue,
                    outcome: "BLOCKED",
                    detail: "Push lane disabled"
                )
            }
            return
        }

        if !trustedPushControllerIDSet.contains(sourceID) {
            trustedPushControllerIDSet.insert(sourceID)
            pushTrustedControllerIDs = trustedPushControllerIDSet.sorted()
            persistControlProfileDocument()
            pushStatus(StatusLineEvent(
                message: "Push auto-trusted controller: \(sourceID.prefix(8))…",
                severity: .success,
                timestamp: Date()
            ))
        }

        let route = pushDeckEventRouter.resolve(
            event: event,
            fallbackMode: pushFallbackModeContext()
        )

        if let ignoredReason = route.ignoredReason, route.intents.isEmpty {
            Task { [hudTelemetryStore] in
                await hudTelemetryStore.ingestSystem(
                    stage: .applied,
                    severity: .block,
                    controlID: "push:\(sourceID)",
                    semanticAction: event.controlKind.rawValue,
                    outcome: "IGNORED",
                    detail: ignoredReason
                )
            }
            return
        }

        for intent in route.intents {
            switch intent {
            case .controlAction(let action):
                routePushControlAction(action, sourceID: sourceID)
            case .pad(let padIntent):
                routePushPadIntent(padIntent, sourceID: sourceID)
            case .mlParam(let mlParam):
                routePushMLParam(mlParam, sourceID: sourceID)
            }
        }
    }

    private func routePushControlAction(_ action: ControlAction, sourceID: String) {
        guard !isPushCommitClassAction(action) else {
            Task { [hudTelemetryStore] in
                await hudTelemetryStore.ingestSystem(
                    stage: .applied,
                    severity: .block,
                    controlID: "push:\(sourceID)",
                    semanticAction: "commit_blocked",
                    outcome: "BLOCKED",
                    detail: "Push lane cannot fire commit-class actions"
                )
            }
            return
        }

        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestMapped(signal: nil, action: action)
        }

        cognitiveProposalEngine.observeAction(
            label: proposalActionLabel(for: action),
            timestampMs: ConductorHarnessViewModel.nowMilliseconds()
        )

        let result = controlActionRouter.route(action)
        let severity: HUDEventSeverity
        let outcome: String
        let blockReason: String?
        switch result {
        case .applied:
            severity = .apply
            outcome = "ROUTED"
            blockReason = nil
        case .blocked(let reason):
            severity = .block
            outcome = "BLOCKED"
            blockReason = reason
        }
        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestApplied(
                signal: nil,
                action: action,
                severity: severity,
                outcome: outcome,
                blockReason: blockReason,
                detail: "push:\(sourceID)"
            )
        }
    }

    private func routePushMLParam(_ mlParam: PushDeckMLParamControl, sourceID: String) {
        switch mlParam.key {
        case .phonePadEchoProbability:
            let clamped = min(0.2, max(0, mlParam.value))
            guard abs(pushPhonePadEchoProbability - clamped) > 0.000_5 else { return }
            pushPhonePadEchoProbability = clamped

            let percent = Int((clamped / 0.2) * 20)
            let now = Date().timeIntervalSince1970
            if now - pushLastPadEchoStatusAt > 0.7 {
                pushLastPadEchoStatusAt = now
                pushStatus(StatusLineEvent(
                    message: "Push phone echo probability set to \(percent)%",
                    severity: .info,
                    timestamp: Date()
                ))
            }

            Task { [hudTelemetryStore] in
                await hudTelemetryStore.ingestSystem(
                    stage: .applied,
                    severity: .apply,
                    controlID: "push:\(sourceID)",
                    semanticAction: "ml_phone_pad_echo_probability",
                    outcome: "APPLIED",
                    detail: "\(percent)%"
                )
            }
        }
    }

    private func routePushPadIntent(_ intent: PushDeckPadIntent, sourceID: String) {
        let detail = "slot \(intent.slot) \(intent.mode.rawValue) \(intent.phase.rawValue)"
        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestSystem(
                stage: .mapped,
                severity: .act,
                controlID: "push:\(sourceID)",
                semanticAction: "pad_\(intent.phase.rawValue)",
                outcome: "MAPPED",
                detail: detail
            )
        }

        if intent.timingMode == .quantized, intent.phase == .down {
            scheduleQuantizedPushPadIntent(intent, sourceID: sourceID)
            return
        }

        executePushPadIntent(intent, sourceID: sourceID)
    }

    private func scheduleQuantizedPushPadIntent(_ intent: PushDeckPadIntent, sourceID: String) {
        let intervalMs = min(500, max(20, intent.quantIntervalMs ?? 140))
        let nowMs = ConductorHarnessViewModel.nowMilliseconds()
        let nextTickMs = ceil(nowMs / Double(intervalMs)) * Double(intervalMs)
        let delay = max(0, (nextTickMs - nowMs) / 1000)
        let key = "push:\(sourceID):\(intent.mode.rawValue):\(intent.slot)"

        pushQuantizedPadWorkItems[key]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pushQuantizedPadWorkItems.removeValue(forKey: key)
            self.executePushPadIntent(intent, sourceID: sourceID)
        }
        pushQuantizedPadWorkItems[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func executePushPadIntent(_ intent: PushDeckPadIntent, sourceID: String) {
        switch intent.mode {
        case .dynamic:
            guard intent.phase == .down else { return }
            cognitiveProposalEngine.observeAction(
                label: "dynamic_pad",
                timestampMs: ConductorHarnessViewModel.nowMilliseconds()
            )
            triggerPushBankedSample(slot: intent.slot, velocity: intent.velocity, mode: .dynamic, sourceID: sourceID)
        case .static:
            guard intent.phase == .down else { return }
            cognitiveProposalEngine.observeAction(
                label: "static_pad",
                timestampMs: ConductorHarnessViewModel.nowMilliseconds()
            )
            triggerPushBankedSample(slot: intent.slot, velocity: intent.velocity, mode: .static, sourceID: sourceID)
        case .choir:
            let note = mapChoirPushPadNote(row: intent.row, column: intent.column)
            switch intent.phase {
            case .down:
                pushActiveChoirPadNotes[intent.slot] = note
                cognitiveProposalEngine.observeAction(
                    label: "choir_note_on",
                    timestampMs: ConductorHarnessViewModel.nowMilliseconds()
                )
                triggerPhoneChoirNoteOn(note: note, velocity: max(0.12, intent.velocity))
            case .up:
                let resolved = pushActiveChoirPadNotes.removeValue(forKey: intent.slot) ?? note
                cognitiveProposalEngine.observeAction(
                    label: "choir_note_off",
                    timestampMs: ConductorHarnessViewModel.nowMilliseconds()
                )
                triggerPhoneChoirNoteOff(note: resolved)
            }
        case .auto:
            return
        }

        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestSystem(
                stage: .applied,
                severity: .apply,
                controlID: "push:\(sourceID)",
                semanticAction: "pad_\(intent.phase.rawValue)",
                outcome: "APPLIED",
                detail: "slot \(intent.slot) \(intent.mode.rawValue)"
            )
        }
    }

    private func triggerPushBankedSample(slot: Int, velocity: Double, mode: PushDeckModeContext, sourceID: String) {
        guard ensureScoringEngineReady(operation: "Push sample") else {
            pushStatus(StatusLineEvent(
                message: "Push sample blocked: engine is stopped",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let candidateIDs = mainBankSampleIDs(for: activeSampleBank)

        guard !candidateIDs.isEmpty else {
            pushStatus(StatusLineEvent(
                message: "Push sample blocked: load sample pack first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let safeIndex = ((slot % candidateIDs.count) + candidateIDs.count) % candidateIDs.count
        let selectedID = candidateIDs[safeIndex]
        selectedSampleID = selectedID
        guard let sampleURL = samplePackEntries[selectedID] else { return }

        let gain = min(0.9, max(0.18, 0.18 + (max(0.05, velocity) * 0.55)))
        do {
            try quadAudioEngine.triggerSample(url: sampleURL, gain: gain)
            recordSoundManipulationFocus(
                lane: "PUSH PAD SLOT \(slot)",
                value: gain,
                controlIDHint: "push:pad:\(slot)",
                sourceHint: "PUSH"
            )
            if mode == .dynamic {
                let normalized = Double(safeIndex) / Double(max(1, candidateIDs.count - 1))
                setDynamicBinSelectionFromControl(normalized)
            }
            maybeDispatchPushPadEchoToPhone(sampleID: selectedID, gain: gain, sourceID: sourceID)
        } catch {
            pushStatus(StatusLineEvent(
                message: "Push sample failed: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
        }
    }

    private func maybeDispatchPushPadEchoToPhone(sampleID: String, gain: Double, sourceID: String) {
        let probability = min(0.2, max(0, pushPhonePadEchoProbability))
        guard probability > 0 else { return }
        guard phoneAudioGateCommitted else { return }
        guard !phoneAudioAvailableDevices.isEmpty else { return }
        guard isLinkHealthy else { return }
        guard Double.random(in: 0 ... 1) <= probability else { return }

        let command = makePhoneCommand(
            kind: .sampleTrigger,
            sampleId: sampleID,
            gain: min(0.34, max(0.08, gain * 0.88))
        )
        dispatchPhoneAudioCommand(command, label: "PUSH PHONE ECHO")

        Task { [hudTelemetryStore] in
            await hudTelemetryStore.ingestSystem(
                stage: .applied,
                severity: .apply,
                controlID: "push:\(sourceID)",
                semanticAction: "phone_pad_echo_dispatch",
                outcome: "APPLIED",
                detail: sampleID
            )
        }
    }

    private func mapChoirPushPadNote(row: Int, column: Int) -> Int {
        let safeRow = min(7, max(0, row))
        let safeColumn = min(7, max(0, column))
        let noteWithinGrid = ((7 - safeRow) * 8) + safeColumn
        let bankOffset = (activeChoirSampleBank - 1) * 12
        return min(127, max(0, 36 + noteWithinGrid + bankOffset))
    }

    private func pushFallbackModeContext() -> PushDeckModeContext {
        if hotasPhoneChoirContextActive {
            return .choir
        }
        switch currentHOTASOutputModeID() {
        case .dynamic:
            return .dynamic
        case .static:
            return .static
        case .off:
            return .static
        }
    }

    private func pushDeckEventSummary(_ event: PushDeckEventPayload) -> String {
        switch event.controlKind {
        case .macro:
            let lane = event.macro?.lane ?? 0
            let value = event.macro?.value ?? 0
            return "PUSH \(event.sourceId) M\(lane) \(String(format: "%.2f", value))"
        case .longStrip:
            let value = event.longStrip?.value ?? 0
            return "PUSH \(event.sourceId) LONG \(String(format: "%.2f", value))"
        case .bankSelect:
            let domain = event.bank?.domain.rawValue ?? "main"
            let bank = event.bank?.bank ?? 1
            return "PUSH \(event.sourceId) BANK \(domain.uppercased()) \(bank)"
        case .mlParam:
            let key = event.mlParam?.key.rawValue ?? "param"
            let value = event.mlParam?.value ?? 0
            let percent = Int((value / 0.2) * 20)
            return "PUSH \(event.sourceId) ML \(key) \(percent)%"
        case .padDown, .padUp:
            let slot = event.pad?.slot ?? -1
            let velocity = event.pad?.velocity ?? 0
            return "PUSH \(event.sourceId) PAD \(slot) \(String(format: "%.2f", velocity))"
        }
    }

    private func recordPushControllerSeen(_ sourceID: String) {
        let normalized = sourceID.lowercased()
        guard !normalized.isEmpty else { return }
        if let existingIndex = pushRecentControllerIDs.firstIndex(of: normalized) {
            pushRecentControllerIDs.remove(at: existingIndex)
        }
        pushRecentControllerIDs.insert(normalized, at: 0)
        if pushRecentControllerIDs.count > 8 {
            pushRecentControllerIDs.removeLast(pushRecentControllerIDs.count - 8)
        }
    }

    private func cancelPendingPushQuantizedPadWork() {
        for work in pushQuantizedPadWorkItems.values {
            work.cancel()
        }
        pushQuantizedPadWorkItems.removeAll()
        pushActiveChoirPadNotes.removeAll()
    }

    private func isPushCommitClassAction(_ action: ControlAction) -> Bool {
        switch action {
        case .contextualTake,
             .startEngine,
             .stopEngine,
             .setMasterArm,
             .phoneGateTake,
             .phoneGateGo,
             .phoneGateSafe:
            return true
        default:
            return false
        }
    }

    private func handleMIDINoteControlSignal(_ signal: ControlSignal) {
        guard let note = midiNoteNumber(from: signal.controlID) else { return }
        let velocity = min(1, max(0, signal.normalizedValue))

        if hotasPhoneChoirContextActive {
            switch signal.phase {
            case .began:
                let mappedNote = mapChoirMIDINote(note)
                activeChoirMIDINotes[note] = mappedNote
                cognitiveProposalEngine.observeAction(
                    label: "choir_note_on",
                    timestampMs: ConductorHarnessViewModel.normalizedMilliseconds(signal.timestamp)
                )
                triggerPhoneChoirNoteOn(note: mappedNote, velocity: max(velocity, 0.12))
            case .ended:
                let mappedNote = activeChoirMIDINotes.removeValue(forKey: note) ?? mapChoirMIDINote(note)
                cognitiveProposalEngine.observeAction(
                    label: "choir_note_off",
                    timestampMs: ConductorHarnessViewModel.normalizedMilliseconds(signal.timestamp)
                )
                triggerPhoneChoirNoteOff(note: mappedNote)
            case .changed:
                break
            }
            return
        }

        guard currentHOTASOutputModeID() == .dynamic else { return }
        guard signal.phase == .began else { return }
        cognitiveProposalEngine.observeAction(
            label: "dynamic_pad",
            timestampMs: ConductorHarnessViewModel.normalizedMilliseconds(signal.timestamp)
        )
        triggerDynamicSamplePad(note: note, velocity: max(velocity, 0.12))
    }

    private func midiNoteNumber(from controlID: String) -> Int? {
        guard controlID.hasPrefix("midi:note:") else { return nil }
        let raw = controlID.replacingOccurrences(of: "midi:note:", with: "")
        guard let parsed = Int(raw) else { return nil }
        return min(127, max(0, parsed))
    }

    private func mapChoirMIDINote(_ note: Int) -> Int {
        let bankOffset = (activeChoirSampleBank - 1) * 12
        return min(127, max(0, note + bankOffset))
    }

    private func triggerDynamicSamplePad(note: Int, velocity: Double) {
        guard ensureScoringEngineReady(operation: "PAD sample") else {
            pushStatus(StatusLineEvent(
                message: "PAD sample blocked: engine is stopped",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let candidateIDs = mainBankSampleIDs(for: activeSampleBank)

        guard !candidateIDs.isEmpty else {
            pushStatus(StatusLineEvent(
                message: "PAD sample blocked: load sample pack first",
                severity: .warn,
                timestamp: Date()
            ))
            return
        }

        let safeIndex = ((note % candidateIDs.count) + candidateIDs.count) % candidateIDs.count
        let selectedID = candidateIDs[safeIndex]
        selectedSampleID = selectedID
        guard let sampleURL = samplePackEntries[selectedID] else { return }

        let gain = min(0.9, max(0.18, 0.18 + (velocity * 0.55)))
        do {
            try quadAudioEngine.triggerSample(url: sampleURL, gain: gain)
            recordSoundManipulationFocus(
                lane: "MIDI PAD NOTE \(note)",
                value: gain,
                controlIDHint: "midi:note:\(note)",
                sourceHint: "MIDI"
            )
        } catch {
            pushStatus(StatusLineEvent(
                message: "PAD sample failed: \(error.localizedDescription)",
                severity: .error,
                timestamp: Date()
            ))
        }
    }

    private func hotasLaneIDs() -> [String] {
        var laneIDs = hotasProfile.staticLaneOrder
        let loadedLaneIDs = showFixedLanes.map(\.id)
        laneIDs.append(contentsOf: loadedLaneIDs.filter { !laneIDs.contains($0) })
        return laneIDs
    }

    private func hotasRuntimeContext() -> ControlRuntimeContext {
        ControlRuntimeContext(
            activeOutputMode: currentHOTASOutputModeID(),
            phoneChoirModeActive: hotasPhoneChoirContextActive,
            allowStaticVideoOverride: hotasStaticVideoOverrideEnabled,
            staticVisualClutchActive: hotasStaticVisualOverrideHeld
        )
    }

    private func currentHOTASOutputModeID() -> FlightOutputModeID {
        if let pendingOutputMode {
            return Self.flightModeID(for: pendingOutputMode)
        }
        return Self.flightModeID(for: committedOutputMode)
    }

    private static func flightModeID(for mode: FlightOutputMode) -> FlightOutputModeID {
        switch mode {
        case .off:
            return .off
        case .dynamic:
            return .dynamic
        case .static:
            return .static
        }
    }

    private func loadControlProfileDocument() {
        let url = ControlProfileDocument.preferredFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            hotasProfile = .defaultX56StrictLive
            hotasInputMode = hotasProfile.inputMode
            hotasControlsEnabled = hotasProfile.enabled
            hotasLastKnownGoodProfile = nil
            hotasStaticVideoOverrideEnabled = true
            pushControlEnabled = false
            trustedPushControllerIDSet = []
            pushTrustedControllerIDs = []
            publishHOTASProfileValidation()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let document = try decoder.decode(ControlProfileDocument.self, from: data)
            var migratedActive = document.activeProfile
            let activeChanged = migrateControlProfileForProposalSupport(&migratedActive)
            hotasProfile = migratedActive
            hotasInputMode = migratedActive.inputMode
            hotasControlsEnabled = migratedActive.enabled

            if var lastKnownGood = document.lastKnownGoodProfile {
                _ = migrateControlProfileForProposalSupport(&lastKnownGood)
                hotasLastKnownGoodProfile = lastKnownGood
            } else {
                hotasLastKnownGoodProfile = nil
            }
            hotasStaticVideoOverrideEnabled = document.hotasStaticVideoOverrideEnabled
            pushControlEnabled = document.pushControlEnabled
            trustedPushControllerIDSet = Set(document.trustedPushControllerIDs.map { $0.lowercased() })
            pushTrustedControllerIDs = trustedPushControllerIDSet.sorted()
            publishHOTASProfileValidation()
            if activeChanged {
                persistControlProfileDocument()
            }
            if hotasMissingRequiredRoles.isEmpty, hotasBindingConflicts.isEmpty, hotasControlsEnabled {
                pushStatus(StatusLineEvent(
                    message: "Loaded HOTAS profile: \(hotasProfile.name)",
                    severity: .info,
                    timestamp: Date()
                ))
            } else if !hotasMissingRequiredRoles.isEmpty || !hotasBindingConflicts.isEmpty {
                hotasControlsEnabled = false
                hotasProfile.enabled = false
                pushStatus(StatusLineEvent(
                    message: "HOTAS profile invalid; controls held SAFE",
                    severity: .warn,
                    timestamp: Date()
                ))
            }
        } catch {
            hotasProfile = .defaultX56StrictLive
            hotasInputMode = hotasProfile.inputMode
            hotasControlsEnabled = false
            hotasLastKnownGoodProfile = nil
            hotasStaticVideoOverrideEnabled = true
            pushControlEnabled = false
            trustedPushControllerIDSet = []
            pushTrustedControllerIDs = []
            publishHOTASProfileValidation()
            pushStatus(StatusLineEvent(
                message: "HOTAS profile load failed: \(error.localizedDescription)",
                severity: .warn,
                timestamp: Date()
            ))
        }
    }

    private func persistControlProfileDocument() {
        let destinationURL = ControlProfileDocument.preferredFileURL()
        let document = ControlProfileDocument(
            version: 2,
            activeProfile: hotasProfile,
            lastKnownGoodProfile: hotasLastKnownGoodProfile,
            hotasStaticVideoOverrideEnabled: hotasStaticVideoOverrideEnabled,
            pushControlEnabled: pushControlEnabled,
            trustedPushControllerIDs: trustedPushControllerIDSet.sorted()
        )

        do {
            let directoryURL = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: destinationURL, options: .atomic)
            pushStatus(StatusLineEvent(
                message: "Saved HOTAS profile: \(destinationURL.path)",
                severity: .info,
                timestamp: Date()
            ))
        } catch {
            pushStatus(StatusLineEvent(
                message: "HOTAS profile save failed: \(error.localizedDescription)",
                severity: .warn,
                timestamp: Date()
            ))
        }
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
            _ = autoloadPushCompanionSampleBanksIfNeeded()
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
                if let resolved = try? resolveSamplePackEntries(from: manifestURL) {
                    samplePackEntries = resolved.entries
                    sampleMetadataByID = resolved.metadata
                    sampleLabelByID = resolved.labels
                    if let firstID = resolved.entries.keys.sorted().first {
                        selectedSampleID = firstID
                    }
                    updateEffectsPresetForActiveBank()
                    applyStaticSampleMorphSelection()
                    publishPushPadLabelsForActiveMainBank(force: true)
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
            rebuildDynamicBinManifest()

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
            if samplePackEntries.isEmpty {
                _ = autoloadPushCompanionSampleBanksIfNeeded()
            }
        } catch {
            pushStatus(StatusLineEvent(
                message: "Media manifest load failed: \(error.localizedDescription)",
                severity: .warn,
                timestamp: Date()
            ))
            _ = autoloadPushCompanionSampleBanksIfNeeded()
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
            if isLatchArmed {
                return
            }
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
            if let zones = payload["zoneOccupancy"] as? [String: Any] {
                var normalized: [String: Int] = [:]
                for (key, value) in zones {
                    if let intValue = value as? Int {
                        normalized[key] = intValue
                    } else if let doubleValue = value as? Double {
                        normalized[key] = Int(doubleValue)
                    }
                }
                if phoneAudioZoneOccupancy != normalized {
                    phoneAudioZoneOccupancy = normalized
                }
            }
            if let failover = payload["failoverCount"] as? Int {
                phoneAudioFailoverCount = failover
            } else if let failover = payload["failoverCount"] as? Double {
                phoneAudioFailoverCount = Int(failover)
            }
            if let health = payload["deviceHealth"] as? [String: Any] {
                var normalized: [String: HarnessPhoneAudioPoolStatePayload.DeviceHealth] = [:]
                for (hashedId, raw) in health {
                    guard let map = raw as? [String: Any] else { continue }
                    let rtt = map["rttMs"] as? Double ?? (map["rttMs"] as? Int).map(Double.init) ?? 0
                    let drift = map["driftMs"] as? Double ?? (map["driftMs"] as? Int).map(Double.init) ?? 0
                    let ack = map["ackReliability"] as? Double ?? (map["ackReliability"] as? Int).map(Double.init) ?? 1
                    let lastSeen = map["lastSeenAt"] as? Double ?? (map["lastSeenAt"] as? Int).map(Double.init) ?? 0
                    normalized[hashedId] = HarnessPhoneAudioPoolStatePayload.DeviceHealth(
                        rttMs: rtt,
                        driftMs: drift,
                        ackReliability: ack,
                        lastSeenAt: lastSeen
                    )
                }
                if phoneAudioDeviceHealth != normalized {
                    phoneAudioDeviceHealth = normalized
                }
            }
            return
        }

        if kind == "procedural_state",
           let payload = json["data"] {
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let decoded = try? JSONDecoder().decode(ProgramProceduralState.self, from: data) {
                programProceduralState = decoded
            }
            return
        }

        if kind == "push_deck_event",
           let payload = json["data"],
           let data = try? JSONSerialization.data(withJSONObject: payload),
           let decoded = try? JSONDecoder().decode(PushDeckEventPayload.self, from: data) {
            handlePushDeckEvent(decoded)
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
