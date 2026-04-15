import ConductorCore
import Foundation

enum HUDStatusTokenLevel: Equatable {
    case nominal
    case caution
    case critical
    case accent
}

struct HUDStatusToken: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let level: HUDStatusTokenLevel
}

struct HUDProposalWidget: Equatable {
    let laneLabel: String
    let confidenceText: String
    let rationale: String
    let expectedEffect: String
    let countdownText: String
    let acceptHint: String
}

struct VufineHUDSnapshot: Equatable {
    struct Input: Equatable {
        let showState: ShowState
        let previewScene: ShowState
        let effectiveOutputMode: EffectiveOutputMode
        let committedOutputMode: FlightOutputMode
        let pendingOutputMode: FlightOutputMode?
        let activeStaticLaneId: String?
        let pendingLaneId: String?

        let connectionStatus: String
        let retryInSeconds: Int?
        let lastLinkError: String?
        let engineRunning: Bool
        let audioRouteSummary: String

        let masterArmKey: MasterArmKeyState
        let isLatchArmed: Bool
        let canFireGO: Bool
        let latchSummary: String
        let latchCountdownSeconds: Double?

        let midiInputStatus: String
        let hotasInputStatus: String
        let pushControlEnabled: Bool
        let pushTrustedControllerCount: Int
        let pushLastSignalSummary: String

        let phoneAudioGateArmed: Bool
        let phoneAudioGateCommitted: Bool
        let phonePoolCount: Int
        let phoneVoiceCount: Int
        let phoneZoneOccupancy: [String: Int]
        let phoneFailoverCount: Int
        let phoneUnhealthyDeviceCount: Int

        let activeSampleBank: Int
        let activeChoirSampleBank: Int
        let hotasPhoneChoirContextActive: Bool
        let hotasStaticVisualOverrideHeld: Bool
        let effectsChainState: EffectsChainState
        let activeEffectsPreset: EffectsChainPreset
        let programProceduralState: ProgramProceduralState
        let ultrachunkControlFrame: UltrachunkControlFrame
        let ultrachunkDSPState: UltrachunkDSPState
        let ultrachunkGranularity: Double
        let ultrachunkIntensity: Double
        let ultrachunkPrimarySampleID: String?
        let ultrachunkSecondarySampleID: String?
        let hotasUltrachunkOverlayEnabled: Bool

        let vector: ParamVector
        let latestAudioFeatures: QuadAudioFeatures

        let statusTime: String
        let statusSeverity: StatusLineSeverity
        let statusMessage: String
        let hudTelemetryFrame: HUDTelemetryFrame
        let stateDevelopmentMetrics: StateDevelopmentMetrics
        let activeProposal: MLProposal?
        let activeProposalCountdownSeconds: Double?
        let programAudioState: ProgramAudioState
    }

    let stateLine: String
    let transportLine: String
    let linkLine: String
    let safetyLine: String
    let inputsLine: String
    let phoneLine: String
    let bankLine: String
    let effectsLine: String
    let ultrachunkLine: String
    let controlRoleLine: String
    let proceduralLine: String
    let textBlendLine: String
    let vectorLine: String
    let audioLine: String
    let proposalLine: String
    let audioStateLine: String
    let statusLine: String

    let safetyTokens: [HUDStatusToken]
    let modeTokens: [HUDStatusToken]
    let dynamicGauges: [HUDGaugeDescriptor]
    let proposalWidget: HUDProposalWidget?
    let actionFeed: [HUDActionEvent]
    let systemHealthLines: [String]

    static func from(input: Input) -> VufineHUDSnapshot {
        let pendingMode = input.pendingOutputMode?.uiLabel.uppercased() ?? "-"
        let lane = input.activeStaticLaneId ?? input.pendingLaneId ?? "-"
        let countdown = input.latchCountdownSeconds.map(Self.secondsString) ?? "--"
        let retry = input.retryInSeconds.map(String.init) ?? "-"
        let error = (input.lastLinkError?.isEmpty == false) ? input.lastLinkError! : "none"
        let procedural = input.programProceduralState
        let clip = procedural.dynamicBinClipId ?? "-"
        let statusToken: String
        if input.phoneAudioGateCommitted {
            statusToken = "COMMITTED"
        } else if input.phoneAudioGateArmed {
            statusToken = "ARMED"
        } else {
            statusToken = "SAFE"
        }

        let stateLine = "STATE \(input.showState.rawValue.uppercased())  SCENE \(input.previewScene.rawValue.uppercased())  MODE \(input.effectiveOutputMode.uiLabel.uppercased())"
        let transportLine = "TRANSPORT committed \(input.committedOutputMode.uiLabel.uppercased())  pending \(pendingMode)  lane \(lane)"
        let linkLine = "LINK \(input.connectionStatus.uppercased())  retry \(retry)s  err \(error)"
        let safetyLine = "SAFETY ENG \(input.engineRunning ? "RUN" : "STOP")  ARM \(input.masterArmKey == .armed ? "ARMED" : "SAFE")  LATCH \(input.isLatchArmed ? "ARMED" : "SAFE")  GO \(input.canFireGO ? "YES" : "NO")  t-\(countdown)s"
        let pushLabel = input.pushControlEnabled ? "ON" : "OFF"
        let inputsLine = "INPUTS MIDI[\(input.midiInputStatus)]  HOTAS[\(input.hotasInputStatus)]  PUSH[\(pushLabel) trusted \(input.pushTrustedControllerCount)]  ROUTE[\(input.audioRouteSummary)]"
        let dominantZone = input.phoneZoneOccupancy.sorted { $0.value > $1.value }.first?.key ?? "-"
        let phoneLine = "PHONE gate \(statusToken)  pool \(input.phonePoolCount)  voices \(input.phoneVoiceCount)  zones \(input.phoneZoneOccupancy.count)  top \(dominantZone)  failovers \(input.phoneFailoverCount)"
        let bankLine = "BANKS main \(input.activeSampleBank)  choir \(input.activeChoirSampleBank)  choirCtx \(input.hotasPhoneChoirContextActive ? "ON" : "OFF")"
        let effectsLine = "FX A \(Self.effectState(active: input.effectsChainState.chainAActive, intensity: input.effectsChainState.chainAIntensity))  B \(Self.effectState(active: input.effectsChainState.chainBActive, intensity: input.effectsChainState.chainBIntensity))"
        let ultrachunkLine = "ULTRACHUNK layer \(input.hotasUltrachunkOverlayEnabled ? "ON" : "OFF")  speed \(Self.decimal(input.ultrachunkControlFrame.speed))  gran \(Self.decimal(input.ultrachunkGranularity))  int \(Self.decimal(input.ultrachunkIntensity))  twist \(input.ultrachunkDSPState.twistLane.rawValue.uppercased())  p \(input.ultrachunkPrimarySampleID ?? "-")  s \(input.ultrachunkSecondarySampleID ?? "-")"
        let rightStickRole: String
        if input.hotasPhoneChoirContextActive {
            rightStickRole = "CHOIR FIELD"
        } else if input.effectiveOutputMode == .static {
            rightStickRole = input.hotasStaticVisualOverrideHeld ? "VISUAL OVERRIDE (CLUTCH)" : "ULTRACHUNK AUDIO"
        } else if input.effectiveOutputMode == .off {
            rightStickRole = "ULTRACHUNK AUDIO (IDLE)"
        } else {
            rightStickRole = "ULTRACHUNK AUDIO"
        }
        let controlRoleLine = "CTRL RIGHT[\(rightStickRole)]  LEFT[BANK/CUE/TRANSPORT]  CLUTCH \(input.hotasStaticVisualOverrideHeld ? "HELD" : "OFF")  UC \(input.hotasUltrachunkOverlayEnabled ? "ON" : "OFF")"
        let proceduralLine = "PROC clip \(clip)  cad \(Self.decimal(procedural.cutCadence))  tr \(procedural.transitionMode.rawValue)  comp \(procedural.compositorPreset.rawValue)  split \(procedural.splitLayout.rawValue)  fade \(Self.decimal(procedural.fade))"
        let textBlendLine = "TEXT p \(Self.decimal(procedural.textProbability))  strict \(Self.decimal(procedural.strictLooseBlend))  loose \(Self.decimal(procedural.textBlend.looseRatio))  var \(Self.decimal(procedural.visualVariance))  crowd \(Self.decimal(procedural.crowdSteeringLevel))"
        let vectorLine = "VECTOR x \(Self.decimal(input.vector.spatialX))  y \(Self.decimal(input.vector.spatialY))  z \(Self.decimal(input.vector.spatialZ))  gain \(Self.decimal(input.vector.audioGain))  comp \(Self.decimal(input.vector.compositeBias))  text \(Self.decimal(input.vector.textAmount))"
        let audioLine = "AUDIO rms \(Self.percent(input.latestAudioFeatures.rms))  flux \(Self.percent(input.latestAudioFeatures.flux))  centroid \(Self.percent(input.latestAudioFeatures.spectralCentroid))  transient \(Self.percent(input.latestAudioFeatures.transientDensity))"
        let metrics = input.stateDevelopmentMetrics
        let proposalLine = "PROPOSAL need \(Self.decimal(metrics.interventionNeedScore))  SDI \(Self.decimal(metrics.stateDevelopmentIndex))  rep \(Self.decimal(metrics.repeatability))  int \(Self.decimal(metrics.intensityTrend))  nov \(Self.decimal(metrics.noveltySaturation))"
        let audioState = input.programAudioState
        let audioStateLine = "AUDIO OPS bank M\(audioState.activeSampleBank)/C\(audioState.activeChoirSampleBank)  dens \(Self.decimal(audioState.estimatedDensity))  latch \(audioState.structuredLatchActive ? "ON" : "OFF")  proposal \(audioState.activeProposalID ?? "-")  fx[\(input.activeEffectsPreset.chainAName)/\(input.activeEffectsPreset.chainBName)]"
        let statusLine = "[\(input.statusTime)] \(input.statusSeverity.rawValue.uppercased())  \(input.statusMessage)"

        let safetyTokens: [HUDStatusToken] = [
            HUDStatusToken(id: "eng", label: "ENG", value: input.engineRunning ? "RUN" : "STOP", level: input.engineRunning ? .nominal : .critical),
            HUDStatusToken(id: "arm", label: "ARM", value: input.masterArmKey == .armed ? "ARMED" : "SAFE", level: input.masterArmKey == .armed ? .caution : .nominal),
            HUDStatusToken(id: "latch", label: "LATCH", value: input.isLatchArmed ? "ARMED" : "SAFE", level: input.isLatchArmed ? .accent : .nominal),
            HUDStatusToken(id: "go", label: "GO", value: input.canFireGO ? "YES" : "NO", level: input.canFireGO ? .nominal : .critical),
            HUDStatusToken(id: "link", label: "LINK", value: input.connectionStatus.uppercased(), level: input.connectionStatus.lowercased().contains("connected") ? .nominal : .caution),
            HUDStatusToken(id: "route", label: "ROUTE", value: input.audioRouteSummary, level: input.audioRouteSummary.lowercased().contains("fallback") ? .caution : .nominal)
        ]

        let modeTokens: [HUDStatusToken] = [
            HUDStatusToken(id: "mode", label: "MODE", value: input.effectiveOutputMode.uiLabel.uppercased(), level: .accent),
            HUDStatusToken(id: "commit", label: "COMMIT", value: input.committedOutputMode.uiLabel.uppercased(), level: .nominal),
            HUDStatusToken(id: "pending", label: "PENDING", value: pendingMode, level: pendingMode == "-" ? .nominal : .caution),
            HUDStatusToken(id: "lane", label: "LANE", value: lane, level: lane == "-" ? .nominal : .accent),
            HUDStatusToken(id: "sample", label: "BANK", value: "M\(input.activeSampleBank)/C\(input.activeChoirSampleBank)", level: .nominal)
        ]

        let gauges: [HUDGaugeDescriptor] = [
            gauge(
                id: "dynamic-bin",
                title: "SOURCE SELECT",
                unitLabel: "BIN",
                value: procedural.dynamicBinSelection,
                valueText: Self.decimal(procedural.dynamicBinSelection),
                traceID: "trace:dynamic_bin",
                frame: input.hudTelemetryFrame,
                fallback: procedural.dynamicBinSelection,
                caution: 0.72,
                warning: 0.90
            ),
            gauge(
                id: "cut-cadence",
                title: "CUT CADENCE",
                unitLabel: "RATE",
                value: procedural.cutCadence,
                valueText: Self.decimal(procedural.cutCadence),
                traceID: "trace:cut_cadence",
                frame: input.hudTelemetryFrame,
                fallback: procedural.cutCadence,
                caution: 0.68,
                warning: 0.88
            ),
            gauge(
                id: "compositor",
                title: "COMP BLEND",
                unitLabel: procedural.compositorPreset.rawValue.uppercased(),
                value: procedural.fade,
                valueText: Self.decimal(procedural.fade),
                traceID: "trace:compositor_blend",
                frame: input.hudTelemetryFrame,
                fallback: procedural.fade,
                caution: 0.70,
                warning: 0.90
            ),
            gauge(
                id: "text-prob",
                title: "TEXT PROB",
                unitLabel: "P",
                value: procedural.textProbability,
                valueText: Self.decimal(procedural.textProbability),
                traceID: "trace:text_probability",
                frame: input.hudTelemetryFrame,
                fallback: procedural.textProbability,
                caution: 0.66,
                warning: 0.86
            ),
            gauge(
                id: "strict-loose",
                title: "STRICT RATIO",
                unitLabel: "MIX",
                value: procedural.strictLooseBlend,
                valueText: Self.decimal(procedural.strictLooseBlend),
                traceID: "trace:strict_loose_blend",
                frame: input.hudTelemetryFrame,
                fallback: procedural.strictLooseBlend,
                caution: 0.78,
                warning: 0.92
            ),
            gauge(
                id: "variance",
                title: "VISUAL VAR",
                unitLabel: "BUDGET",
                value: procedural.visualVariance,
                valueText: Self.decimal(procedural.visualVariance),
                traceID: "trace:visual_variance",
                frame: input.hudTelemetryFrame,
                fallback: procedural.visualVariance,
                caution: 0.72,
                warning: 0.90
            ),
            gauge(
                id: "vector-x",
                title: "SPATIAL X",
                unitLabel: "VEC",
                value: input.vector.spatialX,
                valueText: Self.decimal(input.vector.spatialX),
                traceID: "gd:x",
                frame: input.hudTelemetryFrame,
                fallback: input.vector.spatialX,
                caution: 0.75,
                warning: 0.92
            ),
            gauge(
                id: "ultrachunk-speed",
                title: "ULTRA SPEED",
                unitLabel: "VEL",
                value: input.ultrachunkControlFrame.speed,
                valueText: Self.decimal(input.ultrachunkControlFrame.speed),
                traceID: "trace:ultrachunk_speed",
                frame: input.hudTelemetryFrame,
                fallback: input.ultrachunkControlFrame.speed,
                caution: 0.70,
                warning: 0.88
            ),
            gauge(
                id: "ultrachunk-granularity",
                title: "ULTRA GRAIN",
                unitLabel: "G",
                value: input.ultrachunkGranularity,
                valueText: Self.decimal(input.ultrachunkGranularity),
                traceID: "trace:ultrachunk_granularity",
                frame: input.hudTelemetryFrame,
                fallback: input.ultrachunkGranularity,
                caution: 0.66,
                warning: 0.86
            ),
            gauge(
                id: "ultrachunk-intensity",
                title: "ULTRA INTENS",
                unitLabel: "I",
                value: input.ultrachunkIntensity,
                valueText: Self.decimal(input.ultrachunkIntensity),
                traceID: "trace:ultrachunk_intensity",
                frame: input.hudTelemetryFrame,
                fallback: input.ultrachunkIntensity,
                caution: 0.72,
                warning: 0.9
            ),
            gauge(
                id: "static-sample-morph",
                title: "STATIC MORPH",
                unitLabel: "AUDIO",
                value: audioState.staticMacros.sampleMorph,
                valueText: Self.decimal(audioState.staticMacros.sampleMorph),
                traceID: "trace:static_sample_morph",
                frame: input.hudTelemetryFrame,
                fallback: audioState.staticMacros.sampleMorph,
                caution: 0.72,
                warning: 0.9
            ),
            gauge(
                id: "choir-spread",
                title: "CHOIR SPREAD",
                unitLabel: "FIELD",
                value: audioState.choirField.spread,
                valueText: Self.decimal(audioState.choirField.spread),
                traceID: "trace:choir_field_spread",
                frame: input.hudTelemetryFrame,
                fallback: audioState.choirField.spread,
                caution: 0.78,
                warning: 0.92
            ),
            gauge(
                id: "audio-flux",
                title: "AUDIO FLUX",
                unitLabel: "ENERGY",
                value: input.latestAudioFeatures.flux,
                valueText: Self.percent(input.latestAudioFeatures.flux),
                traceID: "audio:flux",
                frame: input.hudTelemetryFrame,
                fallback: input.latestAudioFeatures.flux,
                caution: 0.70,
                warning: 0.90
            )
        ]

        let systemHealthLines = [
            inputsLine,
            "PUSH LAST \(input.pushLastSignalSummary)",
            phoneLine,
            bankLine,
            effectsLine,
            ultrachunkLine,
            controlRoleLine,
            "CHOIR HEALTH unhealthy \(input.phoneUnhealthyDeviceCount) / \(input.phonePoolCount)",
            proposalLine,
            audioStateLine,
            statusLine
        ]

        let proposalWidget = input.activeProposal.map { proposal in
            HUDProposalWidget(
                laneLabel: proposal.lane.rawValue.replacingOccurrences(of: "_", with: "/").uppercased(),
                confidenceText: Self.decimal(proposal.confidence),
                rationale: proposal.rationale,
                expectedEffect: proposal.expectedEffect,
                countdownText: Self.secondsString(input.activeProposalCountdownSeconds ?? 0),
                acceptHint: "JOY_1 ACCEPT"
            )
        }

        return VufineHUDSnapshot(
            stateLine: stateLine,
            transportLine: transportLine,
            linkLine: linkLine,
            safetyLine: safetyLine,
            inputsLine: inputsLine,
            phoneLine: phoneLine,
            bankLine: bankLine,
            effectsLine: effectsLine,
            ultrachunkLine: ultrachunkLine,
            controlRoleLine: controlRoleLine,
            proceduralLine: proceduralLine,
            textBlendLine: textBlendLine,
            vectorLine: vectorLine,
            audioLine: audioLine,
            proposalLine: proposalLine,
            audioStateLine: audioStateLine,
            statusLine: statusLine,
            safetyTokens: safetyTokens,
            modeTokens: modeTokens,
            dynamicGauges: gauges,
            proposalWidget: proposalWidget,
            actionFeed: Array(input.hudTelemetryFrame.events.prefix(80)),
            systemHealthLines: systemHealthLines
        )
    }

    private static func gauge(
        id: String,
        title: String,
        unitLabel: String,
        value: Double,
        valueText: String,
        traceID: String,
        frame: HUDTelemetryFrame,
        fallback: Double,
        caution: Double,
        warning: Double
    ) -> HUDGaugeDescriptor {
        HUDGaugeDescriptor(
            id: id,
            title: title,
            unitLabel: unitLabel,
            valueText: valueText,
            needle: HUDNeedleModel(normalizedValue: value),
            sparkline: traceValues(traceID: traceID, frame: frame, fallback: fallback),
            cautionThreshold: caution,
            warningThreshold: warning
        )
    }

    private static func traceValues(traceID: String, frame: HUDTelemetryFrame, fallback: Double) -> [Double] {
        if let values = frame.trace(for: traceID)?.values,
           !values.isEmpty {
            return values
        }
        return Array(repeating: min(1, max(0, fallback)), count: 24)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func percent(_ value: Double) -> String {
        String(Int((value * 100).rounded()))
    }

    private static func secondsString(_ seconds: Double) -> String {
        String(format: "%.1f", max(0, seconds))
    }

    private static func effectState(active: Bool, intensity: Double) -> String {
        "\(active ? "ON" : "OFF") \(String(format: "%.2f", intensity))"
    }
}

extension ConductorHarnessViewModel {
    var vufineHUDSnapshot: VufineHUDSnapshot {
        VufineHUDSnapshot.from(input: .init(
            showState: state,
            previewScene: previewScene,
            effectiveOutputMode: effectiveOutputMode,
            committedOutputMode: committedOutputMode,
            pendingOutputMode: pendingOutputMode,
            activeStaticLaneId: activeStaticLaneId,
            pendingLaneId: pendingLaneId,
            connectionStatus: connectionStatus,
            retryInSeconds: retryInSeconds,
            lastLinkError: lastLinkError,
            engineRunning: engineRunning,
            audioRouteSummary: audioRouteStatusSummary,
            masterArmKey: masterArmKey,
            isLatchArmed: isLatchArmed,
            canFireGO: canFireGO,
            latchSummary: latchSummary,
            latchCountdownSeconds: latchCountdownSeconds,
            midiInputStatus: midiInputStatus,
            hotasInputStatus: hotasInputStatus,
            pushControlEnabled: pushControlEnabled,
            pushTrustedControllerCount: pushTrustedControllerIDs.count,
            pushLastSignalSummary: pushLastSignalSummary,
            phoneAudioGateArmed: phoneAudioGateArmed,
            phoneAudioGateCommitted: phoneAudioGateCommitted,
            phonePoolCount: phoneAudioAvailableDevices.count,
            phoneVoiceCount: phoneAudioActiveVoices.count,
            phoneZoneOccupancy: phoneAudioZoneOccupancy,
            phoneFailoverCount: phoneAudioFailoverCount,
            phoneUnhealthyDeviceCount: phoneAudioDeviceHealth.values.filter { $0.ackReliability < 0.6 || $0.rttMs > 700 }.count,
            activeSampleBank: activeSampleBank,
            activeChoirSampleBank: activeChoirSampleBank,
            hotasPhoneChoirContextActive: hotasPhoneChoirContextActive,
            hotasStaticVisualOverrideHeld: hotasStaticVisualOverrideHeld,
            effectsChainState: effectsChainState,
            activeEffectsPreset: activeEffectsPreset,
            programProceduralState: programProceduralState,
            ultrachunkControlFrame: ultrachunkControlFrame,
            ultrachunkDSPState: ultrachunkDSPState,
            ultrachunkGranularity: ultrachunkGranularity,
            ultrachunkIntensity: ultrachunkIntensity,
            ultrachunkPrimarySampleID: ultrachunkPrimarySampleID,
            ultrachunkSecondarySampleID: ultrachunkSecondarySampleID,
            hotasUltrachunkOverlayEnabled: hotasUltrachunkOverlayEnabled,
            vector: vector,
            latestAudioFeatures: latestAudioFeatures,
            statusTime: statusLineTimestamp,
            statusSeverity: statusLineEvent.severity,
            statusMessage: statusLineEvent.message,
            hudTelemetryFrame: hudTelemetryFrame,
            stateDevelopmentMetrics: stateDevelopmentMetrics,
            activeProposal: activeMLProposal,
            activeProposalCountdownSeconds: activeMLProposalCountdownSeconds,
            programAudioState: programAudioState
        ))
    }
}
