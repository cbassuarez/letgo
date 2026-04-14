@testable import ConductorHarnessApp
import ConductorCore
import XCTest

final class CognitiveProposalEngineTests: XCTestCase {
    func testStagesProposalWhenDevelopmentNeedIsHigh() {
        let engine = CognitiveProposalEngine()
        var now: TimeInterval = 10_000
        var staged = false

        for index in 0 ..< 24 {
            now += 120
            engine.observeAction(label: "dynamic_pad", timestampMs: now)
            let feature = QuadAudioFeatures(
                rms: 0.54 + (Double(index % 3) * 0.01),
                spectralCentroid: 0.48,
                flux: 0.52 + (Double(index % 2) * 0.02),
                transientDensity: 0.63,
                updatedAt: now
            )
            let tick = engine.tick(context: context(nowMs: now, features: feature))
            if tick.activeProposal != nil {
                staged = true
                break
            }
        }

        if !staged {
            now += 150
            let result = engine.tick(context: context(
                nowMs: now,
                features: QuadAudioFeatures(
                    rms: 0.62,
                    spectralCentroid: 0.46,
                    flux: 0.57,
                    transientDensity: 0.68,
                    updatedAt: now
                )
            ))
            staged = result.activeProposal != nil
            XCTAssertGreaterThan(result.metrics.interventionNeedScore, 0.5)
        }

        XCTAssertTrue(staged)
    }

    func testAcceptActiveProposalReturnsAcceptedDecision() {
        let engine = CognitiveProposalEngine()
        var now: TimeInterval = 20_000

        for _ in 0 ..< 18 {
            now += 150
            engine.observeAction(label: "dynamic_pad", timestampMs: now)
            _ = engine.tick(context: context(
                nowMs: now,
                features: QuadAudioFeatures(
                    rms: 0.6,
                    spectralCentroid: 0.45,
                    flux: 0.58,
                    transientDensity: 0.66,
                    updatedAt: now
                )
            ))
        }

        let accepted = engine.acceptActiveProposal(nowMs: now + 100)
        XCTAssertEqual(accepted.decision, .accepted)
        XCTAssertNotNil(accepted.proposal)
    }

    func testProposalExpiresWhenNotAcceptedInWindow() {
        let engine = CognitiveProposalEngine()
        var now: TimeInterval = 30_000

        for _ in 0 ..< 18 {
            now += 160
            engine.observeAction(label: "dynamic_pad", timestampMs: now)
            _ = engine.tick(context: context(
                nowMs: now,
                features: QuadAudioFeatures(
                    rms: 0.57,
                    spectralCentroid: 0.44,
                    flux: 0.55,
                    transientDensity: 0.64,
                    updatedAt: now
                )
            ))
        }

        let first = engine.tick(context: context(
            nowMs: now + 2_500,
            features: QuadAudioFeatures(
                rms: 0.55,
                spectralCentroid: 0.44,
                flux: 0.53,
                transientDensity: 0.61,
                updatedAt: now + 2_500
            )
        ))

        XCTAssertNil(first.activeProposal)
        XCTAssertEqual(first.lifecycleEvent?.decision, .expired)
    }

    private func context(
        nowMs: TimeInterval,
        features: QuadAudioFeatures
    ) -> CognitiveProposalContext {
        CognitiveProposalContext(
            nowMs: nowMs,
            engineRunning: true,
            outputRouteReady: true,
            linkHealthy: true,
            isLatchArmed: false,
            masterArmArmed: true,
            pendingOutputModeArmed: false,
            activeSampleBank: 1,
            activeChoirSampleBank: 1,
            selectedSampleID: "sample-a",
            effectsState: EffectsChainState(
                chainAActive: false,
                chainAIntensity: 0,
                chainBActive: false,
                chainBIntensity: 0
            ),
            proceduralState: ProgramProceduralState.default(seed: 99),
            latestAudioFeatures: features
        )
    }
}
