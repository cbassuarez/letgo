import Collections
import ConductorCore
import Foundation

enum HUDEventStage: String, CaseIterable, Codable, Sendable {
    case raw
    case mapped
    case applied
}

enum HUDEventSeverity: String, CaseIterable, Codable, Sendable {
    case info = "INFO"
    case act = "ACT"
    case apply = "APPLY"
    case block = "BLOCK"
    case error = "ERROR"
}

struct HUDActionEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    var timestamp: TimeInterval
    var sourceKind: ControlSourceKind?
    var controlID: String
    var semanticAction: String?
    var value: Double?
    var phase: ControlSignalPhase?
    var stage: HUDEventStage
    var severity: HUDEventSeverity
    var outcome: String
    var blockReason: String?
    var detail: String?

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        sourceKind: ControlSourceKind?,
        controlID: String,
        semanticAction: String?,
        value: Double?,
        phase: ControlSignalPhase?,
        stage: HUDEventStage,
        severity: HUDEventSeverity,
        outcome: String,
        blockReason: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceKind = sourceKind
        self.controlID = controlID
        self.semanticAction = semanticAction
        self.value = value
        self.phase = phase
        self.stage = stage
        self.severity = severity
        self.outcome = outcome
        self.blockReason = blockReason
        self.detail = detail
    }
}

struct HUDControlTrace: Identifiable, Equatable, Sendable {
    let id: String
    let values: [Double]
    let latest: Double
    let updatedAt: TimeInterval
}

struct HUDTelemetryFrame: Equatable, Sendable {
    var events: [HUDActionEvent]
    var traces: [HUDControlTrace]

    static let empty = HUDTelemetryFrame(events: [], traces: [])

    func trace(for id: String) -> HUDControlTrace? {
        traces.first(where: { $0.id == id })
    }
}

actor HUDTelemetryStore {
    private let eventCapacity: Int
    private let tracePointCapacity: Int

    private var events: Deque<HUDActionEvent> = []
    private var traces: [String: Deque<Double>] = [:]
    private var traceUpdatedAt: [String: TimeInterval] = [:]

    init(eventCapacity: Int = 640, tracePointCapacity: Int = 72) {
        self.eventCapacity = max(64, eventCapacity)
        self.tracePointCapacity = max(8, tracePointCapacity)
    }

    func ingestRaw(signal: ControlSignal) {
        let timestamp = normalizedTimestamp(signal.timestamp)
        if signal.kind == .axis || signal.kind == .hat {
            appendTrace(id: signal.controlID, value: signal.normalizedValue, timestamp: timestamp)
        }

        let event = HUDActionEvent(
            timestamp: timestamp,
            sourceKind: signal.sourceKind,
            controlID: signal.controlID,
            semanticAction: nil,
            value: signal.normalizedValue,
            phase: signal.phase,
            stage: .raw,
            severity: .info,
            outcome: signal.phase.rawValue.uppercased(),
            detail: "\(signal.kind.rawValue.uppercased()) \(signal.rawValue)"
        )
        appendEvent(event)
    }

    func ingestMapped(signal: ControlSignal?, action: ControlAction) {
        let timestamp = normalizedTimestamp(signal?.timestamp)
        let event = HUDActionEvent(
            timestamp: timestamp,
            sourceKind: signal?.sourceKind,
            controlID: signal?.controlID ?? "mapper",
            semanticAction: action.hudActionLabel,
            value: action.hudPrimaryValue,
            phase: signal?.phase,
            stage: .mapped,
            severity: .act,
            outcome: "MAPPED"
        )
        appendEvent(event)

        if let value = action.hudPrimaryValue,
           let traceID = action.hudTraceID {
            appendTrace(id: traceID, value: value, timestamp: timestamp)
        }
    }

    func ingestApplied(
        signal: ControlSignal?,
        action: ControlAction?,
        severity: HUDEventSeverity,
        outcome: String,
        blockReason: String? = nil,
        detail: String? = nil
    ) {
        let timestamp = normalizedTimestamp(signal?.timestamp)
        let event = HUDActionEvent(
            timestamp: timestamp,
            sourceKind: signal?.sourceKind,
            controlID: signal?.controlID ?? "router",
            semanticAction: action?.hudActionLabel,
            value: action?.hudPrimaryValue,
            phase: signal?.phase,
            stage: .applied,
            severity: severity,
            outcome: outcome,
            blockReason: blockReason,
            detail: detail
        )
        appendEvent(event)
    }

    func ingestSystem(
        stage: HUDEventStage,
        severity: HUDEventSeverity,
        controlID: String,
        semanticAction: String?,
        outcome: String,
        detail: String?,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        let event = HUDActionEvent(
            timestamp: normalizedTimestamp(timestamp),
            sourceKind: nil,
            controlID: controlID,
            semanticAction: semanticAction,
            value: nil,
            phase: nil,
            stage: stage,
            severity: severity,
            outcome: outcome,
            blockReason: nil,
            detail: detail
        )
        appendEvent(event)
    }

    func ingestTrace(
        id: String,
        value: Double,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        appendTrace(
            id: id,
            value: value,
            timestamp: normalizedTimestamp(timestamp)
        )
    }

    func snapshot(maxEvents: Int = 140) -> HUDTelemetryFrame {
        let boundedEvents = Array(Array(events.suffix(max(1, maxEvents))).reversed())
        let boundedTraces: [HUDControlTrace] = traceUpdatedAt
            .sorted { $0.value > $1.value }
            .map { key, updatedAt in
                let values = Array(traces[key] ?? [])
                return HUDControlTrace(
                    id: key,
                    values: values,
                    latest: values.last ?? 0,
                    updatedAt: updatedAt
                )
            }
        return HUDTelemetryFrame(events: boundedEvents, traces: boundedTraces)
    }

    private func appendTrace(id: String, value: Double, timestamp: TimeInterval) {
        let clamped = min(1, max(0, value))
        var deque = traces[id] ?? Deque<Double>()
        deque.append(clamped)
        if deque.count > tracePointCapacity {
            deque.removeFirst(deque.count - tracePointCapacity)
        }
        traces[id] = deque
        traceUpdatedAt[id] = timestamp
    }

    private func appendEvent(_ event: HUDActionEvent) {
        if var last = events.last, shouldCoalesce(last: last, next: event) {
            last.timestamp = event.timestamp
            last.value = event.value
            last.phase = event.phase
            last.outcome = event.outcome
            last.detail = event.detail
            events[events.count - 1] = last
            return
        }

        events.append(event)
        if events.count > eventCapacity {
            events.removeFirst(events.count - eventCapacity)
        }
    }

    private func shouldCoalesce(last: HUDActionEvent, next: HUDActionEvent) -> Bool {
        guard last.stage == next.stage,
              last.controlID == next.controlID,
              last.semanticAction == next.semanticAction,
              last.blockReason == nil,
              next.blockReason == nil else {
            return false
        }

        guard last.stage != .applied else {
            return false
        }

        return abs(last.timestamp - next.timestamp) < 0.08
    }

    private func normalizedTimestamp(_ timestamp: TimeInterval?) -> TimeInterval {
        guard let timestamp else {
            return Date().timeIntervalSince1970
        }
        return timestamp > 100_000 ? timestamp / 1000 : timestamp
    }
}

struct HUDNeedleModel: Equatable, Sendable {
    let normalizedValue: Double
    let startAngleDegrees: Double
    let endAngleDegrees: Double

    init(
        normalizedValue: Double,
        startAngleDegrees: Double = -130,
        endAngleDegrees: Double = 130
    ) {
        self.normalizedValue = min(1, max(0, normalizedValue))
        self.startAngleDegrees = startAngleDegrees
        self.endAngleDegrees = endAngleDegrees
    }

    var angleDegrees: Double {
        startAngleDegrees + ((endAngleDegrees - startAngleDegrees) * normalizedValue)
    }
}

struct HUDGaugeDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let unitLabel: String
    let valueText: String
    let needle: HUDNeedleModel
    let sparkline: [Double]
    let cautionThreshold: Double
    let warningThreshold: Double
}

private extension ControlAction {
    var hudActionLabel: String {
        switch self {
        case .acceptActiveProposal:
            return "proposal_accept"
        case .startEngine:
            return "engine_start"
        case .stopEngine:
            return "engine_stop"
        case .patchVector:
            return "patch_vector"
        case .armOutputMode(let mode):
            return "arm_mode_\(mode.rawValue)"
        case .armTransportLane(let laneId):
            return "arm_lane_\(laneId)"
        case .queueTimelineStep(let laneId):
            return "queue_\(laneId)"
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
        case .setMasterArm(let isArmed):
            return isArmed ? "master_arm" : "master_safe"
        case .phoneGateTake:
            return "phone_take"
        case .phoneGateGo:
            return "phone_go"
        case .phoneGateSafe:
            return "phone_safe"
        case .togglePreviewPlayback:
            return "preview_toggle"
        case .setSampleBank(let bank, let domain):
            return "sample_bank_\(domain.rawValue)_\(bank)"
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

    var hudPrimaryValue: Double? {
        switch self {
        case .startEngine, .stopEngine:
            return nil
        case .setDynamicBinSelection(let value),
             .setCutCadence(let value),
             .setCompositorBlend(let value),
             .setStaticSampleMorph(let value),
             .setStaticArticulation(let value),
             .setStaticTimbre(let value),
             .setStaticTextureSend(let value),
             .setChoirFieldSpread(let value),
             .setChoirFieldDepth(let value),
             .setChoirFieldDetune(let value),
             .setTextProbability(let value),
             .setStrictLooseBlend(let value),
             .setVisualVariance(let value):
            return value
        case .setStaticVisualOverrideHold(let held):
            return held ? 1 : 0
        case .setEffectsChain(_, _, let intensity):
            return intensity
        case .toggleUltrachunkOverlay:
            return nil
        case .patchVector(let patch):
            if let value = patch.spatialX { return value }
            if let value = patch.audioGain { return value }
            if let value = patch.compositeBias { return value }
            if let value = patch.textAmount { return value }
            if let value = patch.spatialY { return value }
            if let value = patch.spatialZ { return value }
            return nil
        default:
            return nil
        }
    }

    var hudTraceID: String? {
        switch self {
        case .setDynamicBinSelection:
            return "trace:dynamic_bin"
        case .setCutCadence:
            return "trace:cut_cadence"
        case .setCompositorBlend:
            return "trace:compositor_blend"
        case .setStaticSampleMorph:
            return "trace:static_sample_morph"
        case .setStaticArticulation:
            return "trace:static_articulation"
        case .setStaticTimbre:
            return "trace:static_timbre"
        case .setStaticTextureSend:
            return "trace:static_texture_send"
        case .setChoirFieldSpread:
            return "trace:choir_field_spread"
        case .setChoirFieldDepth:
            return "trace:choir_field_depth"
        case .setChoirFieldDetune:
            return "trace:choir_field_detune"
        case .setStaticVisualOverrideHold:
            return "trace:static_visual_clutch"
        case .setTextProbability:
            return "trace:text_probability"
        case .setStrictLooseBlend:
            return "trace:strict_loose_blend"
        case .setVisualVariance:
            return "trace:visual_variance"
        case .patchVector:
            return "trace:vector"
        case .setEffectsChain:
            return "trace:fx"
        case .toggleUltrachunkOverlay:
            return nil
        default:
            return nil
        }
    }
}
