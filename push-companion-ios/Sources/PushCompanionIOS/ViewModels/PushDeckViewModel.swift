import Foundation
import SwiftUI

@MainActor
final class PushDeckViewModel: ObservableObject {
    @Published private(set) var selectedMode: PushDeckModeContext = .auto
    @Published private(set) var engineReadout: String = "OFF"
    @Published var timingMode: PushDeckTimingMode = .immediate
    @Published var quantIntervalMs: Int = 140
    @Published var mainBank: Int = 1
    @Published var choirBank: Int = 1
    @Published private(set) var highlightSelectionEnabled = false
    @Published var macroValues: [Double] = Array(repeating: 0.5, count: 8)
    @Published private(set) var longSoundsStripValue: Double = 0.5
    @Published private(set) var longSoundsStripY: Double = 0.5
    @Published private(set) var longSoundsVariantLabel: String = "BASE"
    @Published private(set) var longSoundsVariantIndex: Int = 0
    @Published private(set) var longSoundsVariantCount: Int = 1
    @Published private(set) var longSoundsLatched: Bool = false
    @Published private(set) var actionRail: [DeckActionRailEntry] = []
    @Published private(set) var activePadSlots: Set<Int> = []
    @Published private(set) var padFileNameOverrides: [Int: String] = [:]
    @Published private(set) var dynamicPadFileNames: [String] = []
    @Published private(set) var highlightedPadsByBank: [String: [Int: Int]] = [:]
    @Published private(set) var actionFlashEvent: DeckActionFlashEvent?
    @Published private(set) var proposalCardState: ProposalCardState?
    @Published var settingsState: PushDeckSettingsState
    @Published var notesPresentationState = PushNotesPresentationState(isPresented: false)
    @Published private(set) var phonePadEchoProbability: Double {
        didSet {
            defaults.set(phonePadEchoProbability, forKey: phonePadEchoProbabilityKey)
        }
    }
    @Published var notesText: String {
        didSet {
            defaults.set(notesText, forKey: notesKey)
        }
    }

    let sessionStore: PushSessionStore
    let socketClient: PushDeckWebSocketClient

    private let defaults: UserDefaults
    private let notesKey = "push_companion.notes"
    private let handednessKey = "push_companion.handedness"
    private let prefersHighContrastKey = "push_companion.prefers_high_contrast"
    private let padHighlightsKey = "push_companion.pad_highlights.v1"
    private let phonePadEchoProbabilityKey = "push_companion.phone_pad_echo_probability"
    private let railLimit = 180
    private var activeTouchToPad: [Int: Int] = [:]
    private var throttledMacroAtByLane: [Int: TimeInterval] = [:]
    private var throttledLongStripAt: TimeInterval = 0
    private var flashClearTask: Task<Void, Never>?
    private var proposalExpiryTask: Task<Void, Never>?
    private let padAuditionEngine = PushPadAuditionEngine()
    private let longStripAuditionEngine = PushLongStripAuditionEngine()
    private var longStripGestureActive = false
    private let bundledMainPadLabelsByBank: [Int: [Int: String]]
    private let ignoredInboundKinds: Set<String> = [
        "sync",
        "show_snapshot",
        "procedural_state",
        "audio_features",
        "audience_vector",
        "lighting_state",
        "param_vector",
        "push_pad_labels"
    ]

    init(
        defaults: UserDefaults = .standard,
        sessionStore: PushSessionStore? = nil,
        socketClient: PushDeckWebSocketClient? = nil
    ) {
        self.defaults = defaults
        self.sessionStore = sessionStore ?? PushSessionStore(defaults: defaults)
        self.socketClient = socketClient ?? PushDeckWebSocketClient()
        self.notesText = defaults.string(forKey: notesKey) ?? ""
        self.bundledMainPadLabelsByBank = PushDeckViewModel.loadBundledMainPadLabels()
        self.phonePadEchoProbability = Self.clampPhonePadEchoProbability(
            defaults.object(forKey: phonePadEchoProbabilityKey) as? Double ?? 0
        )

        let handednessRaw = defaults.string(forKey: handednessKey)
        let handedness = DeckHandedness(rawValue: handednessRaw ?? "") ?? .right
        let prefersHighContrast = defaults.object(forKey: prefersHighContrastKey) as? Bool ?? true
        self.settingsState = PushDeckSettingsState(
            hostDraft: self.sessionStore.backendHost,
            mirrorHandedness: handedness,
            prefersHighContrast: prefersHighContrast
        )
        if let savedData = defaults.data(forKey: padHighlightsKey),
           let decoded = try? JSONDecoder().decode([String: [Int: Int]].self, from: savedData) {
            self.highlightedPadsByBank = decoded
        }

        self.socketClient.onEnvelope = { [weak self] envelope in
            self?.ingestServerEnvelope(envelope)
        }
    }

    var handedness: DeckHandedness {
        settingsState.mirrorHandedness
    }

    func connect() {
        guard let url = sessionStore.websocketURL else {
            appendRail("No backend URL configured", severity: .error)
            emitFlash("No backend URL configured", severity: .error)
            return
        }
        socketClient.connect(url: url)
        sendPhonePadEchoProbabilityEvent(includeInRail: false)
        appendRail("CONNECT \(url.host() ?? "backend")", severity: .act)
        emitFlash("CONNECT", severity: .act)
    }

    func reconnect() {
        socketClient.reconnect()
        appendRail("RECONNECT", severity: .act)
        emitFlash("RECONNECT", severity: .act)
    }

    func disconnect() {
        socketClient.disconnect()
        appendRail("DISCONNECT", severity: .act)
        emitFlash("DISCONNECT", severity: .act)
    }

    func applyHostDraft() {
        sessionStore.updateBackendHost(settingsState.hostDraft)
        settingsState.hostDraft = sessionStore.backendHost
        appendRail("HOST \(sessionStore.backendHost)", severity: .act)
        emitFlash("HOST UPDATED", severity: .act)
        connect()
    }

    func toggleHighContrast() {
        settingsState.prefersHighContrast.toggle()
        defaults.set(settingsState.prefersHighContrast, forKey: prefersHighContrastKey)
        appendRail(
            settingsState.prefersHighContrast ? "CONTRAST HIGH" : "CONTRAST NORMAL",
            severity: .info
        )
    }

    func toggleHandedness() {
        setHandedness(settingsState.mirrorHandedness == .left ? .right : .left)
    }

    func setHandedness(_ handedness: DeckHandedness) {
        guard settingsState.mirrorHandedness != handedness else { return }
        settingsState.mirrorHandedness = handedness
        defaults.set(handedness.rawValue, forKey: handednessKey)
        appendRail("HAND \(handedness.rawValue.uppercased())", severity: .act)
        emitFlash("\(handedness.rawValue.uppercased()) HAND", severity: .act)
    }

    func toggleHighlightSelection() {
        highlightSelectionEnabled.toggle()
        appendRail(
            highlightSelectionEnabled ? "HIGHLIGHT SELECT ON" : "HIGHLIGHT SELECT OFF",
            severity: .act
        )
    }

    func padHighlightColor(for slot: Int) -> Color? {
        guard (0..<64).contains(slot) else { return nil }
        let key = activeHighlightBankKey()
        guard let step = highlightedPadsByBank[key]?[slot], step > 0 else {
            return nil
        }
        let paletteIndex = (step - 1) % Self.highlightPalette.count
        return Self.highlightPalette[paletteIndex]
    }

    func setTimingMode(_ mode: PushDeckTimingMode) {
        guard timingMode != mode else { return }
        timingMode = mode
        appendRail("TIMING \(mode.rawValue.uppercased())", severity: .act)
        emitFlash("TIMING \(mode.rawValue.uppercased())", severity: .act)
    }

    func setQuantIntervalMs(_ value: Int) {
        let clamped = min(500, max(20, value))
        guard quantIntervalMs != clamped else { return }
        quantIntervalMs = clamped
        appendRail("QUANT \(clamped)ms", severity: .act)
    }

    func setMainBank(_ bank: Int) {
        let clamped = min(3, max(1, bank))
        guard mainBank != clamped else { return }
        mainBank = clamped
        if longStripGestureActive {
            if let snapshot = longStripAuditionEngine.scrub(
                bank: clamped,
                x: longSoundsStripValue,
                y: longSoundsStripY
            ) {
                applyLongStripSnapshot(snapshot)
            }
        }
        sendBankSelect(domain: .main, bank: clamped)
        emitFlash("MAIN B\(clamped)", severity: .apply)
    }

    func setChoirBank(_ bank: Int) {
        let clamped = min(3, max(1, bank))
        guard choirBank != clamped else { return }
        choirBank = clamped
        sendBankSelect(domain: .choir, bank: clamped)
        emitFlash("CHOIR B\(clamped)", severity: .apply)
    }

    func setMacroValue(lane: Int, value: Double) {
        guard lane >= 1, lane <= 8 else { return }
        let clamped = min(1, max(0, value))
        macroValues[lane - 1] = clamped

        let now = Date().timeIntervalSince1970
        let throttleWindow: TimeInterval = 1.0 / 35.0
        if now - (throttledMacroAtByLane[lane] ?? 0) < throttleWindow {
            return
        }
        throttledMacroAtByLane[lane] = now

        sendEvent(
            controlKind: .macro,
            macro: PushDeckMacroControl(lane: lane, value: clamped),
            detail: "M\(lane) \(String(format: "%.2f", clamped))",
            severity: .act,
            coalescingKey: "macro.\(lane)"
        )
        emitFlash("M\(lane) \(String(format: "%.2f", clamped))", severity: .act)
    }

    func setLongSoundsStripValue(_ value: Double) {
        let clamped = min(1, max(0, value))
        guard abs(longSoundsStripValue - clamped) > 0.000_5 else { return }
        longSoundsStripValue = clamped

        let now = Date().timeIntervalSince1970
        let throttleWindow: TimeInterval = 1.0 / 35.0
        if now - throttledLongStripAt < throttleWindow {
            return
        }
        throttledLongStripAt = now

        sendEvent(
            controlKind: .longStrip,
            longStrip: PushDeckLongStripControl(value: clamped),
            detail: "LONG STRIP \(String(format: "%.2f", clamped))",
            severity: .act,
            coalescingKey: "long_strip"
        )
    }

    func beginLongSoundsStripGesture(atX valueX: Double, y valueY: Double) {
        let clampedX = min(1, max(0, valueX))
        let clampedY = min(1, max(0, valueY))
        longStripGestureActive = true
        if let snapshot = longStripAuditionEngine.begin(bank: mainBank, x: clampedX, y: clampedY) {
            applyLongStripSnapshot(snapshot)
        } else {
            longSoundsStripValue = clampedX
            longSoundsStripY = clampedY
        }
        setLongSoundsStripValue(clampedX)
    }

    func updateLongSoundsStripGesture(x valueX: Double, y valueY: Double) {
        let clampedX = min(1, max(0, valueX))
        let clampedY = min(1, max(0, valueY))
        if !longStripGestureActive {
            beginLongSoundsStripGesture(atX: clampedX, y: clampedY)
            return
        }
        if let snapshot = longStripAuditionEngine.scrub(bank: mainBank, x: clampedX, y: clampedY) {
            applyLongStripSnapshot(snapshot)
        } else {
            longSoundsStripValue = clampedX
            longSoundsStripY = clampedY
        }
        setLongSoundsStripValue(clampedX)
    }

    func endLongSoundsStripGesture() {
        guard longStripGestureActive else { return }
        longStripGestureActive = false
        if let snapshot = longStripAuditionEngine.end() {
            applyLongStripSnapshot(snapshot)
        }
    }

    func toggleLongSoundsLatch() {
        let next = !longSoundsLatched
        if let snapshot = longStripAuditionEngine.setLatched(next) {
            applyLongStripSnapshot(snapshot)
        } else {
            longSoundsLatched = next
        }
        appendRail("LONG LATCH \(longSoundsLatched ? "ON" : "OFF")", severity: .act, coalescingKey: "long_latch")
        emitFlash(longSoundsLatched ? "LONG LATCH ON" : "LONG LATCH OFF", severity: .act)
    }

    func setPhonePadEchoProbability(_ value: Double) {
        let clamped = Self.clampPhonePadEchoProbability(value)
        guard abs(phonePadEchoProbability - clamped) > 0.000_5 else { return }
        phonePadEchoProbability = clamped
        sendPhonePadEchoProbabilityEvent(includeInRail: true)
    }

    func padFileName(for slot: Int) -> String {
        guard slot >= 0 else { return "sample.wav" }
        if let override = padFileNameOverrides[slot], !override.isEmpty {
            return override
        }

        switch selectedMode {
        case .dynamic:
            if !dynamicPadFileNames.isEmpty {
                return dynamicPadFileNames[slot % dynamicPadFileNames.count]
            }
            return fallbackMainPadFileName(slot: slot, bank: mainBank)
        case .static, .auto:
            return fallbackMainPadFileName(slot: slot, bank: mainBank)
        case .choir:
            return fallbackChoirPadFileName(slot: slot, bank: choirBank)
        }
    }

    func handleTouches(_ touches: [PushTouchPoint], in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if highlightSelectionEnabled {
            handleHighlightSelectionTouches(touches, in: size)
            return
        }

        var nextTouchMap: [Int: Int] = [:]
        var touchedSlots = Set<Int>()

        for point in touches {
            let slot = padSlot(for: point.location, in: size)
            nextTouchMap[point.id] = slot
            touchedSlots.insert(slot)

            let previousSlot = activeTouchToPad[point.id]
            if previousSlot != slot {
                if let previousSlot {
                    sendPadEvent(slot: previousSlot, phase: .padUp, pressure: 0, velocity: 0)
                    activePadSlots.remove(previousSlot)
                }
                let velocity = normalizedVelocity(force: point.force)
                sendPadEvent(slot: slot, phase: .padDown, pressure: velocity, velocity: velocity)
                activePadSlots.insert(slot)
            } else if previousSlot == slot {
                activePadSlots.insert(slot)
            }
        }

        for (touchID, slot) in activeTouchToPad where nextTouchMap[touchID] == nil {
            sendPadEvent(slot: slot, phase: .padUp, pressure: 0, velocity: 0)
            activePadSlots.remove(slot)
        }

        activeTouchToPad = nextTouchMap
        activePadSlots = touchedSlots
    }

    func endTouches() {
        for slot in activeTouchToPad.values {
            sendPadEvent(slot: slot, phase: .padUp, pressure: 0, velocity: 0)
        }
        activeTouchToPad.removeAll()
        activePadSlots.removeAll()
    }

    func presentNotes() {
        notesPresentationState.isPresented = true
    }

    func dismissNotes() {
        notesPresentationState.isPresented = false
    }

    func dismissProposal() {
        proposalCardState = nil
    }

    func macroTitle(for lane: Int) -> String {
        descriptor(for: lane).title
    }

    func macroSubtitle(for lane: Int) -> String {
        descriptor(for: lane).subtitle
    }

    func macroAccent(for lane: Int) -> Color {
        descriptor(for: lane).accent
    }

    private func descriptor(for lane: Int) -> (title: String, subtitle: String, accent: Color) {
        let mode = macroModeContext
        switch lane {
        case 1:
            switch mode {
            case .dynamic:
                return ("M1 Dynamic Bin", "Clip focus", DeckThemeTokens.accentMain)
            case .static:
                return ("M1 Sample Morph", "Static sculpt", DeckThemeTokens.accentMain)
            case .choir:
                return ("M1 Choir Spread", "Field width", DeckThemeTokens.accentMain)
            case .auto:
                return ("M1 Sample Morph", "Static sculpt", DeckThemeTokens.accentMain)
            }
        case 2:
            switch mode {
            case .dynamic:
                return ("M2 Cut Cadence", "Cut speed", DeckThemeTokens.accentMain)
            case .static:
                return ("M2 Articulation", "Gate/density", DeckThemeTokens.accentMain)
            case .choir:
                return ("M2 Choir Depth", "Distance", DeckThemeTokens.accentMain)
            case .auto:
                return ("M2 Articulation", "Gate/density", DeckThemeTokens.accentMain)
            }
        case 3:
            switch mode {
            case .dynamic:
                return ("M3 Composite", "Blend", DeckThemeTokens.accentMain)
            case .static:
                return ("M3 Timbre", "Color", DeckThemeTokens.accentMain)
            case .choir:
                return ("M3 Choir Detune", "Texture", DeckThemeTokens.accentMain)
            case .auto:
                return ("M3 Timbre", "Color", DeckThemeTokens.accentMain)
            }
        case 4:
            return ("M4 Text Prob", "Appearance", DeckThemeTokens.accentMain)
        case 5:
            return ("M5 Strict/Loose", "Text blend", DeckThemeTokens.accentMain)
        case 6:
            return ("M6 Variance", "Visual budget", DeckThemeTokens.accentMain)
        case 7:
            return ("M7 Rhythm", "Trigger A", DeckThemeTokens.accentApply)
        case 8:
            return ("M8 Space", "Trigger B", DeckThemeTokens.accentApply)
        default:
            return ("M\(lane)", "Macro", DeckThemeTokens.accentMain)
        }
    }

    private var macroModeContext: PushDeckModeContext {
        if selectedMode != .auto {
            return selectedMode
        }
        let readout = engineReadout.uppercased()
        if readout.hasPrefix("DYNAMIC") {
            return .dynamic
        }
        if readout.contains("CHOIR") {
            return .choir
        }
        return .static
    }

    private func sendPadEvent(slot: Int, phase: PushDeckControlKind, pressure: Double, velocity: Double) {
        let mode = macroModeContext
        let bank = mode == .choir ? choirBank : mainBank
        if phase == .padDown {
            padAuditionEngine.padDown(slot: slot, bank: bank, mode: mode, velocity: velocity)
        } else if phase == .padUp {
            padAuditionEngine.padUp(slot: slot)
        }

        let row = slot / 8
        let column = slot % 8
        let pad = PushDeckPadControl(
            row: row,
            column: column,
            slot: slot,
            pressure: min(1, max(0, pressure)),
            velocity: min(1, max(0, velocity))
        )
        sendEvent(
            controlKind: phase,
            pad: pad,
            detail: "PAD \(slot) \(phase.rawValue)",
            severity: .apply,
            coalescingKey: "pad.\(slot).\(phase.rawValue)",
            includeInRail: false
        )
    }

    private func sendBankSelect(domain: PushDeckBankDomain, bank: Int) {
        sendEvent(
            controlKind: .bankSelect,
            bank: PushDeckBankControl(domain: domain, bank: bank),
            detail: "BANK \(domain.rawValue.uppercased()) \(bank)",
            severity: .apply,
            coalescingKey: "bank.\(domain.rawValue)"
        )
    }

    private func sendPhonePadEchoProbabilityEvent(includeInRail: Bool) {
        let clamped = Self.clampPhonePadEchoProbability(phonePadEchoProbability)
        if clamped != phonePadEchoProbability {
            phonePadEchoProbability = clamped
        }
        sendEvent(
            controlKind: .mlParam,
            mlParam: PushDeckMLParamControl(
                key: .phonePadEchoProbability,
                value: clamped
            ),
            detail: "PHONE PAD ECHO \(Int((clamped / 0.2) * 20))%",
            severity: .act,
            coalescingKey: "ml.phone_pad_echo_probability",
            includeInRail: includeInRail
        )
    }

    private func sendEvent(
        controlKind: PushDeckControlKind,
        pad: PushDeckPadControl? = nil,
        macro: PushDeckMacroControl? = nil,
        longStrip: PushDeckLongStripControl? = nil,
        bank: PushDeckBankControl? = nil,
        mlParam: PushDeckMLParamControl? = nil,
        detail: String,
        severity: DeckActionSeverity,
        coalescingKey: String? = nil,
        includeInRail: Bool = true
    ) {
        let payload = PushDeckEventPayload(
            eventId: "push-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 1000...9999))",
            sourceId: sessionStore.controllerID,
            controlKind: controlKind,
            modeContext: selectedMode,
            timingMode: timingMode,
            quantIntervalMs: timingMode == .quantized ? quantIntervalMs : nil,
            pad: pad,
            macro: macro,
            longStrip: longStrip,
            bank: bank,
            mlParam: mlParam,
            issuedAt: Date().timeIntervalSince1970 * 1000
        )
        socketClient.sendPushEvent(payload)
        if includeInRail {
            appendRail(detail, severity: severity, coalescingKey: coalescingKey)
        }
    }

    private func ingestServerEnvelope(_ envelope: String) {
        guard let data = envelope.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let kind = json["kind"] as? String else {
            appendRail("RX \(String(envelope.prefix(90)))", severity: .info)
            return
        }
        if let payload = json["data"] as? [String: Any] {
            ingestDeckStatus(kind: kind, payload: payload)
        }

        if kind == "ml_proposal" || kind == "proposal",
           let proposalData = json["data"] as? [String: Any] {
            stageProposal(from: proposalData)
            return
        }

        if kind == "ack" {
            appendRail("RX ACK", severity: .apply)
            return
        }
        if ignoredInboundKinds.contains(kind) {
            return
        }
        appendRail("RX \(kind.uppercased())", severity: .info, coalescingKey: "rx.\(kind)")
    }

    private func ingestDeckStatus(kind: String, payload: [String: Any]) {
        if let readout = engineReadout(from: payload, kind: kind), readout != engineReadout {
            engineReadout = readout
            appendRail("ENGINE \(readout)", severity: .info, coalescingKey: "status.engine")
        }

        if let mode = modeContext(from: payload, kind: kind), mode != selectedMode {
            selectedMode = mode
            appendRail("MODE \(mode.rawValue.uppercased())", severity: .info, coalescingKey: "status.mode")
        }

        if let timing = timingContext(from: payload), timing != timingMode {
            timingMode = timing
            appendRail("TIMING \(timing.rawValue.uppercased())", severity: .info, coalescingKey: "status.timing")
        }

        if let labels = extractPadLabels(from: payload), !labels.isEmpty, labels != padFileNameOverrides {
            padFileNameOverrides = labels
            appendRail("PAD LABELS \(labels.count)", severity: .info, coalescingKey: "status.pad_labels")
        }

        if kind == "procedural_state" {
            let clipNames = extractDynamicClipFileNames(from: payload)
            if !clipNames.isEmpty, clipNames != dynamicPadFileNames {
                dynamicPadFileNames = clipNames
                appendRail("DYNAMIC LABELS \(clipNames.count)", severity: .info, coalescingKey: "status.dynamic_labels")
            }
        }
    }

    private func engineReadout(from payload: [String: Any], kind: String) -> String? {
        if let raw = payload["outputMode"] as? String {
            return normalizedEngineReadout(raw, showState: payload["state"] as? String)
        }
        if let raw = payload["output_mode"] as? String {
            return normalizedEngineReadout(raw, showState: payload["state"] as? String)
        }
        if let raw = payload["engineMode"] as? String {
            return normalizedEngineReadout(raw, showState: payload["state"] as? String)
        }
        if let raw = payload["mode"] as? String, raw.lowercased() != "auto" {
            return normalizedEngineReadout(raw, showState: payload["state"] as? String)
        }

        if let showState = payload["showState"] as? String {
            return showStateEngineReadout(showState)
        }
        if kind == "show_snapshot", let showState = payload["state"] as? String {
            return showStateEngineReadout(showState)
        }
        return nil
    }

    private func showStateEngineReadout(_ showState: String) -> String {
        switch showState.lowercased() {
        case "preshow":
            return "STATIC/PRESHOW"
        case "introduction":
            return "STATIC/INTRO"
        case "ending":
            return "STATIC/ENDING"
        case "main":
            return "DYNAMIC"
        case "hold", "recovery", "aborted":
            return "INTERSTITIAL"
        case "idle":
            return "OFF"
        default:
            return showState.uppercased()
        }
    }

    private func normalizedEngineReadout(_ raw: String, showState: String?) -> String {
        switch raw.lowercased() {
        case "off", "idle", "disabled":
            return "OFF"
        case "dynamic", "main", "live":
            return "DYNAMIC"
        case "interstitial":
            return "INTERSTITIAL"
        case "static":
            if let showState {
                let mapped = showStateEngineReadout(showState)
                if mapped.hasPrefix("STATIC/") {
                    return mapped
                }
            }
            return "STATIC"
        case "auto":
            if let showState {
                return showStateEngineReadout(showState)
            }
            return "OFF"
        default:
            return raw.uppercased()
        }
    }

    private func handleHighlightSelectionTouches(_ touches: [PushTouchPoint], in size: CGSize) {
        var nextTouchMap: [Int: Int] = [:]

        for point in touches {
            let slot = padSlot(for: point.location, in: size)
            nextTouchMap[point.id] = slot
            if activeTouchToPad[point.id] == nil {
                cyclePadHighlight(slot: slot)
            }
        }

        activeTouchToPad = nextTouchMap
        activePadSlots = Set(nextTouchMap.values)
    }

    private func cyclePadHighlight(slot: Int) {
        guard (0..<64).contains(slot) else { return }
        let key = activeHighlightBankKey()
        var bankHighlights = highlightedPadsByBank[key] ?? [:]
        let current = bankHighlights[slot] ?? 0
        let next = (current + 1) % (Self.highlightPalette.count + 1)
        if next == 0 {
            bankHighlights.removeValue(forKey: slot)
        } else {
            bankHighlights[slot] = next
        }

        if bankHighlights.isEmpty {
            highlightedPadsByBank.removeValue(forKey: key)
        } else {
            highlightedPadsByBank[key] = bankHighlights
        }
        persistPadHighlights()

        let colorName = next == 0 ? "CLEAR" : Self.highlightNames[next - 1]
        appendRail(
            "HIGHLIGHT \(key.uppercased()) PAD \(slot + 1) \(colorName)",
            severity: .apply,
            coalescingKey: "highlight.\(key).\(slot)"
        )
    }

    private func activeHighlightBankKey() -> String {
        if selectedMode == .choir {
            return "choir-\(choirBank)"
        }
        return "main-\(mainBank)"
    }

    private func persistPadHighlights() {
        guard let encoded = try? JSONEncoder().encode(highlightedPadsByBank) else { return }
        defaults.set(encoded, forKey: padHighlightsKey)
    }

    private func modeContext(from payload: [String: Any], kind: String) -> PushDeckModeContext? {
        if let raw = payload["modeContext"] as? String,
           let mode = PushDeckModeContext(rawValue: raw) {
            return mode
        }
        if let raw = payload["mode"] as? String,
           let mode = PushDeckModeContext(rawValue: raw) {
            return mode
        }
        if let choirActive = payload["choirContextActive"] as? Bool, choirActive {
            return .choir
        }
        guard kind == "show_snapshot", let showState = payload["state"] as? String else {
            return nil
        }
        switch showState {
        case "main":
            return .dynamic
        case "preshow", "introduction", "ending":
            return .static
        default:
            return .auto
        }
    }

    private func timingContext(from payload: [String: Any]) -> PushDeckTimingMode? {
        if let raw = payload["timingMode"] as? String {
            return PushDeckTimingMode(rawValue: raw)
        }
        return nil
    }

    private func extractDynamicClipFileNames(from payload: [String: Any]) -> [String] {
        guard let manifest = payload["dynamicBinManifest"] as? [[String: Any]] else {
            return []
        }
        return manifest.compactMap { entry in
            if let mediaRef = entry["mediaRef"] as? String {
                return displayFileName(from: mediaRef)
            }
            if let id = entry["id"] as? String {
                return displayFileName(from: id)
            }
            return nil
        }
    }

    private func extractPadLabels(from payload: [String: Any]) -> [Int: String]? {
        if let direct = payload["padLabels"] as? [String] {
            return normalizedPadLabels(from: direct)
        }
        if let direct = payload["pad_labels"] as? [String] {
            return normalizedPadLabels(from: direct)
        }
        if let direct = payload["padFileNames"] as? [String] {
            return normalizedPadLabels(from: direct)
        }
        if let mapped = payload["padLabels"] as? [String: Any] {
            return normalizedPadLabelMap(from: mapped)
        }
        if let mapped = payload["pad_labels"] as? [String: Any] {
            return normalizedPadLabelMap(from: mapped)
        }
        return nil
    }

    private func normalizedPadLabels(from labels: [String]) -> [Int: String] {
        var mapped: [Int: String] = [:]
        for (index, value) in labels.prefix(64).enumerated() {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                mapped[index] = displayFileName(from: clean)
            }
        }
        return mapped
    }

    private func normalizedPadLabelMap(from raw: [String: Any]) -> [Int: String] {
        var mapped: [Int: String] = [:]
        for (slotRaw, value) in raw {
            guard let slot = Int(slotRaw), (0..<64).contains(slot) else { continue }
            guard let name = value as? String else { continue }
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                mapped[slot] = displayFileName(from: clean)
            }
        }
        return mapped
    }

    private func displayFileName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "sample.wav" }

        if let curated = curatedMainBankLabel(from: trimmed) {
            return curated
        }

        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            let component = url.lastPathComponent
            if !component.isEmpty {
                return curatedMainBankLabel(from: component) ?? component
            }
        }

        let pathComponent = (trimmed as NSString).lastPathComponent
        if !pathComponent.isEmpty {
            return curatedMainBankLabel(from: pathComponent) ?? pathComponent
        }
        return trimmed
    }

    private func fallbackMainPadFileName(slot: Int, bank: Int) -> String {
        if let bundled = bundledMainPadLabelsByBank[bank]?[slot] {
            return bundled
        }
        let index = slot + 1
        if bank == 1 {
            return String(format: "666 ʇ · %02d", index)
        }
        if bank == 2 {
            return String(format: "29 #Strafford APTS · %02d", index)
        }
        return String(format: "main b%d · %02d", bank, index)
    }

    private func fallbackChoirPadFileName(slot: Int, bank: Int) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let midi = 48 + slot
        let note = noteNames[midi % 12]
        let octave = (midi / 12) - 1
        return "choir_b\(bank)_\(note)\(octave).wav"
    }

    private static func loadBundledMainPadLabels() -> [Int: [Int: String]] {
        struct BundledPadMap: Decodable {
            struct Slice: Decodable {
                let slot: Int
                let label: String?
                let fileName: String?
            }
            let slices: [Slice]
        }

        var bankLabels: [Int: [Int: String]] = [:]
        let decoder = JSONDecoder()

        for bank in 1...2 {
            guard let bundleRoot = Bundle.main.resourceURL else { continue }
            let mapURL = bundleRoot
                .appendingPathComponent("Samples/main_b\(bank)")
                .appendingPathComponent("pad_map.json")
            guard let data = try? Data(contentsOf: mapURL),
                  let map = try? decoder.decode(BundledPadMap.self, from: data) else {
                continue
            }

            var labels: [Int: String] = [:]
            for slice in map.slices where (0..<64).contains(slice.slot) {
                if let label = slice.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !label.isEmpty {
                    labels[slice.slot] = label
                } else if let fileName = slice.fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !fileName.isEmpty {
                    labels[slice.slot] = fileName
                }
            }
            if !labels.isEmpty {
                bankLabels[bank] = labels
            }
        }

        return bankLabels
    }

    private func stageProposal(from proposalData: [String: Any]) {
        let laneRaw = (proposalData["lane"] as? String) ?? "unknown"
        let lane = ProposalCardState.Lane(rawValue: laneRaw) ?? .unknown
        let confidence = min(1, max(0, proposalData["confidence"] as? Double ?? 0.5))
        let rationale =
            (proposalData["rationale"] as? String)
            ?? (proposalData["reason"] as? String)
            ?? "Model sees an opportunity to add detail."
        let timeoutMs = max(2000, proposalData["timeoutMs"] as? Int ?? 9000)
        let proposalID = (proposalData["id"] as? String) ?? UUID().uuidString
        let acceptHint = (proposalData["acceptHint"] as? String) ?? "JOY_1"

        proposalCardState = ProposalCardState(
            id: proposalID,
            lane: lane,
            confidence: confidence,
            rationale: rationale,
            timeoutMs: timeoutMs,
            createdAt: Date(),
            acceptHint: acceptHint
        )

        appendRail("PROPOSAL \(lane.displayName) \(Int(confidence * 100))%", severity: .apply)
        emitFlash("\(lane.displayName) READY", severity: .apply)
        scheduleProposalExpiry(for: proposalID, timeoutMs: timeoutMs)
    }

    private func scheduleProposalExpiry(for proposalID: String, timeoutMs: Int) {
        proposalExpiryTask?.cancel()
        proposalExpiryTask = Task { [weak self] in
            let durationNs = UInt64(max(timeoutMs, 0)) * 1_000_000
            try? await Task.sleep(nanoseconds: durationNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.proposalCardState?.id == proposalID else { return }
                self.proposalCardState = nil
                self.appendRail("PROPOSAL EXPIRED", severity: .block)
            }
        }
    }

    private func appendRail(
        _ message: String,
        severity: DeckActionSeverity,
        coalescingKey: String? = nil
    ) {
        let now = Date()

        if let key = coalescingKey,
           let first = actionRail.first,
           first.coalescingKey == key,
           now.timeIntervalSince(first.timestamp) < 0.2 {
            var updated = first
            updated.timestamp = now
            updated.message = message
            updated.severity = severity
            updated.coalescedCount += 1
            actionRail[0] = updated
            return
        }

        actionRail.insert(
            DeckActionRailEntry(
                timestamp: now,
                severity: severity,
                message: message,
                coalescedCount: 1,
                coalescingKey: coalescingKey
            ),
            at: 0
        )

        if actionRail.count > railLimit {
            actionRail.removeLast(actionRail.count - railLimit)
        }
    }

    private func emitFlash(_ message: String, severity: DeckActionSeverity) {
        let event = DeckActionFlashEvent(message: message, severity: severity)
        actionFlashEvent = event

        flashClearTask?.cancel()
        flashClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.actionFlashEvent?.id == event.id else { return }
                self.actionFlashEvent = nil
            }
        }
    }

    private func padSlot(for point: CGPoint, in size: CGSize) -> Int {
        let normalizedX = min(0.999, max(0, point.x / size.width))
        let normalizedY = min(0.999, max(0, point.y / size.height))
        let column = Int(floor(normalizedX * 8))
        let row = Int(floor(normalizedY * 8))
        return (row * 8) + column
    }

    private func normalizedVelocity(force: CGFloat) -> Double {
        let value = Double(force)
        return min(1, max(0.08, value))
    }

    private static func clampPhonePadEchoProbability(_ value: Double) -> Double {
        min(0.2, max(0, value))
    }

    private func applyLongStripSnapshot(_ snapshot: PushLongStripSnapshot) {
        longSoundsStripValue = min(1, max(0, snapshot.valueX))
        longSoundsStripY = min(1, max(0, snapshot.valueY))
        longSoundsVariantIndex = snapshot.variantIndex
        longSoundsVariantCount = max(1, snapshot.variantCount)
        longSoundsVariantLabel = snapshot.variantLabel
        longSoundsLatched = snapshot.isLatched
    }

    private func curatedMainBankLabel(from candidate: String) -> String? {
        let pattern = #"^main_b([12])_(\d{1,2})(?:\.wav)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        guard let match = regex.firstMatch(in: candidate, options: [], range: range),
              match.numberOfRanges == 3,
              let bankRange = Range(match.range(at: 1), in: candidate),
              let indexRange = Range(match.range(at: 2), in: candidate),
              let bank = Int(candidate[bankRange]),
              let index = Int(candidate[indexRange]) else {
            return nil
        }
        if bank == 1 {
            return String(format: "666 ʇ · %02d", index)
        }
        return String(format: "29 #Strafford APTS · %02d", index)
    }

    private static let highlightPalette: [Color] = [
        DeckThemeTokens.accentWarn,
        DeckThemeTokens.accentApply,
        DeckThemeTokens.accentMain,
        Color(red: 0.92, green: 0.42, blue: 1.0)
    ]
    private static let highlightNames: [String] = ["AMBER", "GREEN", "BLUE", "MAGENTA"]
}
