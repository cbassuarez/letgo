import ConductorCore
import Foundation

struct CognitiveProposalContext {
    let nowMs: TimeInterval
    let engineRunning: Bool
    let outputRouteReady: Bool
    let linkHealthy: Bool
    let isLatchArmed: Bool
    let masterArmArmed: Bool
    let pendingOutputModeArmed: Bool
    let activeSampleBank: Int
    let activeChoirSampleBank: Int
    let selectedSampleID: String?
    let effectsState: EffectsChainState
    let proceduralState: ProgramProceduralState
    let latestAudioFeatures: QuadAudioFeatures
}

struct CognitiveProposalLifecycleEvent {
    let proposal: MLProposal
    let decision: MLProposalDecision
    let message: String
}

struct CognitiveProposalTickResult {
    let metrics: StateDevelopmentMetrics
    let activeProposal: MLProposal?
    let lifecycleEvent: CognitiveProposalLifecycleEvent?
}

final class CognitiveProposalEngine {
    private struct TimedAction {
        let timestampMs: TimeInterval
        let label: String
    }

    private var audioHistory: [QuadAudioFeatures] = []
    private var actionHistory: [TimedAction] = []
    private var activeProposal: MLProposal?
    private var lastProposalDecisionAtMs: TimeInterval = 0
    private var lastLane: ProposalLane = .visualText
    private var proposalSequence: Int = 0

    private let audioHistoryCapacity = 56
    private let actionHistoryWindowMs: TimeInterval = 8_000
    private let proposalRefractoryMs: TimeInterval = 3_600
    private let interventionThreshold = 0.5

    func reset(nowMs: TimeInterval) {
        audioHistory.removeAll(keepingCapacity: true)
        actionHistory.removeAll(keepingCapacity: true)
        activeProposal = nil
        lastProposalDecisionAtMs = nowMs
    }

    func observeAudioFeatures(_ features: QuadAudioFeatures) {
        audioHistory.append(features)
        if audioHistory.count > audioHistoryCapacity {
            audioHistory.removeFirst(audioHistory.count - audioHistoryCapacity)
        }
    }

    func observeAction(label: String, timestampMs: TimeInterval) {
        actionHistory.append(TimedAction(timestampMs: timestampMs, label: label))
        pruneActionHistory(nowMs: timestampMs)
    }

    func tick(context: CognitiveProposalContext) -> CognitiveProposalTickResult {
        observeAudioFeatures(context.latestAudioFeatures)
        pruneActionHistory(nowMs: context.nowMs)

        let metrics = computeMetrics(context: context)

        if let active = activeProposal,
           context.nowMs >= active.expiresAt {
            activeProposal = nil
            lastProposalDecisionAtMs = context.nowMs
            return CognitiveProposalTickResult(
                metrics: metrics,
                activeProposal: nil,
                lifecycleEvent: CognitiveProposalLifecycleEvent(
                    proposal: active,
                    decision: .expired,
                    message: "Proposal expired"
                )
            )
        }

        if let activeProposal {
            return CognitiveProposalTickResult(
                metrics: metrics,
                activeProposal: activeProposal,
                lifecycleEvent: nil
            )
        }

        guard context.nowMs - lastProposalDecisionAtMs >= proposalRefractoryMs else {
            return CognitiveProposalTickResult(
                metrics: metrics,
                activeProposal: nil,
                lifecycleEvent: nil
            )
        }

        let candidate = buildCandidate(context: context, metrics: metrics)
        guard let candidate else {
            return CognitiveProposalTickResult(
                metrics: metrics,
                activeProposal: nil,
                lifecycleEvent: nil
            )
        }

        activeProposal = candidate
        return CognitiveProposalTickResult(
            metrics: metrics,
            activeProposal: candidate,
            lifecycleEvent: CognitiveProposalLifecycleEvent(
                proposal: candidate,
                decision: .rejected,
                message: "Proposal staged"
            )
        )
    }

    func acceptActiveProposal(nowMs: TimeInterval) -> (decision: MLProposalDecision, proposal: MLProposal?) {
        guard let proposal = activeProposal else {
            return (.blocked, nil)
        }

        guard nowMs < proposal.expiresAt else {
            activeProposal = nil
            lastProposalDecisionAtMs = nowMs
            return (.expired, proposal)
        }

        activeProposal = nil
        lastProposalDecisionAtMs = nowMs
        return (.accepted, proposal)
    }

    func rejectActiveProposal(nowMs: TimeInterval) {
        guard activeProposal != nil else { return }
        activeProposal = nil
        lastProposalDecisionAtMs = nowMs
    }

    private func computeMetrics(context: CognitiveProposalContext) -> StateDevelopmentMetrics {
        let history = audioHistory
        let fluxSeries = history.map(\.flux)
        let centroidSeries = history.map(\.spectralCentroid)

        let repeatability = computeRepeatability(fluxSeries: fluxSeries)
        let intensityTrend = computeIntensityTrend(history: history)
        let noveltySaturation = computeNoveltySaturation(centroidSeries: centroidSeries)
        let headroom = computeHeadroom(context: context)
        let safetyContext = computeSafetyContext(context: context)

        let sdi = clamp01(
            (repeatability * 0.37)
                + (intensityTrend * 0.28)
                + (noveltySaturation * 0.35)
        )
        let interventionNeed = clamp01(sdi * ((headroom * 0.65) + 0.35) * safetyContext)

        return StateDevelopmentMetrics(
            repeatability: repeatability,
            intensityTrend: intensityTrend,
            noveltySaturation: noveltySaturation,
            headroom: headroom,
            safetyContext: safetyContext,
            stateDevelopmentIndex: sdi,
            interventionNeedScore: interventionNeed,
            updatedAt: context.nowMs
        )
    }

    private func buildCandidate(context: CognitiveProposalContext, metrics: StateDevelopmentMetrics) -> MLProposal? {
        guard metrics.interventionNeedScore >= interventionThreshold else {
            return nil
        }

        let audioScore = clamp01(
            metrics.interventionNeedScore
                * (0.60 + (metrics.repeatability * 0.24) + (metrics.headroom * 0.16))
        )
        let visualScore = clamp01(
            metrics.interventionNeedScore
                * (0.56 + (metrics.intensityTrend * 0.22) + ((1 - metrics.noveltySaturation) * 0.08) + (context.proceduralState.visualVariance * 0.14))
        )

        guard audioScore >= interventionThreshold || visualScore >= interventionThreshold else {
            return nil
        }

        let selectedLane = selectLane(audioScore: audioScore, visualScore: visualScore)
        proposalSequence += 1
        let id = "ml-proposal-\(proposalSequence)-\(Int(context.nowMs.rounded()))"

        switch selectedLane {
        case .audio:
            let confidence = audioScore
            let kind: AudioProposalKind = confidence >= 0.78 ? .structuredLatch : .textureNudge
            let suggestedBank: Int
            if metrics.noveltySaturation > 0.68 {
                suggestedBank = (context.activeSampleBank % 3) + 1
            } else {
                suggestedBank = context.activeSampleBank
            }

            let chainA = clamp01((context.latestAudioFeatures.flux * 0.38) + (metrics.repeatability * 0.34))
            let chainB = clamp01((context.latestAudioFeatures.transientDensity * 0.46) + (metrics.intensityTrend * 0.28))
            let densityTarget = clamp01((context.latestAudioFeatures.transientDensity * 0.55) + (metrics.repeatability * 0.45))

            let rationale = String(
                format: "Pattern stable %.2f · intensity %.2f · novelty saturation %.2f · headroom %.2f",
                metrics.repeatability,
                metrics.intensityTrend,
                metrics.noveltySaturation,
                metrics.headroom
            )
            let expected: String = kind == .structuredLatch
                ? "Latchable texture scene to extend current groove"
                : "Short texture nudge to punctuate the current phrase"

            return MLProposal(
                id: id,
                lane: .audio,
                confidence: confidence,
                rationale: rationale,
                expectedEffect: expected,
                timeoutMs: 2_100,
                createdAt: context.nowMs,
                audio: MLProposalPayloadAudio(
                    kind: kind,
                    suggestedBank: suggestedBank,
                    suggestedSampleID: context.selectedSampleID,
                    chainAIntensityTarget: chainA,
                    chainBIntensityTarget: chainB,
                    densityTarget: densityTarget,
                    latchSuggested: kind == .structuredLatch
                )
            )

        case .visualText:
            let confidence = visualScore
            let directionSeed = (proposalSequence + Int(context.proceduralState.epoch)) % 3
            let direction: Double = directionSeed == 0 ? -1 : 1
            let clipSelection = clamp01(context.proceduralState.dynamicBinSelection + (0.14 * direction))

            let transition: TransitionMode
            switch context.proceduralState.transitionMode {
            case .cut:
                transition = .crossfade
            case .crossfade:
                transition = .fade
            case .fade:
                transition = .stutter
            case .stutter:
                transition = .cut
            }

            let compositor: CompositorPreset
            switch context.proceduralState.compositorPreset {
            case .blend:
                compositor = .screen
            case .screen:
                compositor = .multiply
            case .multiply:
                compositor = .mask
            case .mask:
                compositor = .pip
            case .pip:
                compositor = .stutter
            case .stutter:
                compositor = .blend
            }

            let split: SplitLayout
            switch context.proceduralState.splitLayout {
            case .none:
                split = .split2
            case .split2:
                split = .split3
            case .split3:
                split = .split4
            case .split4:
                split = .pip
            case .pip:
                split = .none
            }

            let nextTextProbability = clamp01(
                context.proceduralState.textProbability
                    + (0.10 * (1 - context.proceduralState.textProbability))
            )
            let nextStrictLoose = clamp01(
                (context.proceduralState.strictLooseBlend * 0.82)
                    + (0.18 * 0.48)
            )

            let rationale = String(
                format: "Visual/text variance opening %.2f with intervention %.2f",
                context.proceduralState.visualVariance,
                metrics.interventionNeedScore
            )

            return MLProposal(
                id: id,
                lane: .visualText,
                confidence: confidence,
                rationale: rationale,
                expectedEffect: "Compositor + text pressure shift for contrast without commit jumps",
                timeoutMs: 2_100,
                createdAt: context.nowMs,
                visualText: MLProposalPayloadVisualText(
                    dynamicBinSelection: clipSelection,
                    transitionMode: transition,
                    compositorPreset: compositor,
                    splitLayout: split,
                    fade: clamp01(context.proceduralState.fade + 0.12),
                    textProbability: nextTextProbability,
                    strictLooseBlend: nextStrictLoose
                )
            )
        }
    }

    private func selectLane(audioScore: Double, visualScore: Double) -> ProposalLane {
        if audioScore < interventionThreshold {
            lastLane = .visualText
            return .visualText
        }
        if visualScore < interventionThreshold {
            lastLane = .audio
            return .audio
        }

        let delta = abs(audioScore - visualScore)
        if delta < 0.1 {
            let alternated: ProposalLane = lastLane == .audio ? .visualText : .audio
            lastLane = alternated
            return alternated
        }

        let chosen: ProposalLane = audioScore >= visualScore ? .audio : .visualText
        lastLane = chosen
        return chosen
    }

    private func computeRepeatability(fluxSeries: [Double]) -> Double {
        guard fluxSeries.count >= 4 else { return 0 }

        var totalDiff: Double = 0
        var comparisons = 0
        for index in 1 ..< fluxSeries.count {
            totalDiff += abs(fluxSeries[index] - fluxSeries[index - 1])
            comparisons += 1
        }
        let meanDiff = comparisons > 0 ? totalDiff / Double(comparisons) : 1
        return clamp01(1 - (meanDiff * 2.3))
    }

    private func computeIntensityTrend(history: [QuadAudioFeatures]) -> Double {
        guard history.count >= 4 else { return 0 }
        guard let latest = history.last else { return 0 }
        let baseline = history[max(0, history.count - 10)]
        let rmsSlope = (latest.rms - baseline.rms) * 2.1
        let density = (latest.flux * 0.55) + (latest.transientDensity * 0.45)
        return clamp01(0.5 + rmsSlope + ((density - 0.5) * 0.75))
    }

    private func computeNoveltySaturation(centroidSeries: [Double]) -> Double {
        let recentActions = actionHistory.suffix(20)
        let labels = recentActions.map(\.label)
        let uniqueRatio: Double
        if labels.isEmpty {
            uniqueRatio = 1
        } else {
            uniqueRatio = Double(Set(labels).count) / Double(labels.count)
        }

        let centroidVariance: Double
        if centroidSeries.count < 4 {
            centroidVariance = 0
        } else {
            let slice = centroidSeries.suffix(16)
            let mean = slice.reduce(0, +) / Double(slice.count)
            let variance = slice.reduce(0) { partial, sample in
                let d = sample - mean
                return partial + (d * d)
            } / Double(slice.count)
            centroidVariance = variance
        }

        let repetitionPressure = clamp01(1 - uniqueRatio)
        let spectralStability = clamp01(1 - (sqrt(centroidVariance) * 4.0))
        return clamp01((repetitionPressure * 0.62) + (spectralStability * 0.38))
    }

    private func computeHeadroom(context: CognitiveProposalContext) -> Double {
        let effectPressure = max(
            context.effectsState.chainAIntensity,
            context.effectsState.chainBIntensity
        )
        return clamp01(1 - (context.latestAudioFeatures.rms * 0.94) - (effectPressure * 0.18))
    }

    private func computeSafetyContext(context: CognitiveProposalContext) -> Double {
        guard context.engineRunning, context.outputRouteReady, context.linkHealthy else {
            return 0
        }

        var score = 1.0
        if context.pendingOutputModeArmed || context.isLatchArmed {
            score *= 0.26
        }
        if !context.masterArmArmed {
            score *= 0.82
        }
        return clamp01(score)
    }

    private func pruneActionHistory(nowMs: TimeInterval) {
        let cutoff = nowMs - actionHistoryWindowMs
        if let firstKept = actionHistory.firstIndex(where: { $0.timestampMs >= cutoff }), firstKept > 0 {
            actionHistory.removeFirst(firstKept)
        } else if actionHistory.allSatisfy({ $0.timestampMs < cutoff }) {
            actionHistory.removeAll(keepingCapacity: true)
        }
    }

    private func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
