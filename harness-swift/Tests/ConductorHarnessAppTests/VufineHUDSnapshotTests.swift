@testable import ConductorHarnessApp
import ConductorCore
import XCTest

final class VufineHUDSnapshotTests: XCTestCase {
    func testExpandedCondensedSnapshotFormatting() {
        let input = VufineHUDSnapshot.Input(
            showState: .main,
            previewScene: .main,
            effectiveOutputMode: .dynamic,
            committedOutputMode: .dynamic,
            pendingOutputMode: .static,
            activeStaticLaneId: "main-01",
            pendingLaneId: "ending",
            connectionStatus: "Connected",
            retryInSeconds: 2,
            lastLinkError: "none",
            engineRunning: true,
            audioRouteSummary: "QUAD READY (4ch)",
            masterArmKey: .armed,
            isLatchArmed: true,
            canFireGO: true,
            latchSummary: "ARMED: DYNAMIC",
            latchCountdownSeconds: 3.4,
            midiInputStatus: "MIDI IN: Push",
            hotasInputStatus: "HOTAS IN: HYBRID",
            pushControlEnabled: true,
            pushTrustedControllerCount: 2,
            pushLastSignalSummary: "PUSH aabbccdd M3 0.42",
            phoneAudioGateArmed: true,
            phoneAudioGateCommitted: false,
            phonePoolCount: 12,
            phoneVoiceCount: 6,
            phoneZoneOccupancy: ["geo-field": 4, "auto-UR": 2],
            phoneFailoverCount: 1,
            phoneUnhealthyDeviceCount: 2,
            activeSampleBank: 2,
            activeChoirSampleBank: 3,
            hotasPhoneChoirContextActive: true,
            hotasStaticVisualOverrideHeld: false,
            effectsChainState: EffectsChainState(
                chainAActive: true,
                chainAIntensity: 0.72,
                chainBActive: false,
                chainBIntensity: 0.10
            ),
            activeEffectsPreset: EffectsChainPreset(chainAName: "Rhythm", chainBName: "Space", bankID: 2, renderClass: .texture),
            programProceduralState: ProgramProceduralState(
                epoch: 9,
                seed: 99,
                updatedAt: 22_000,
                dynamicBinSelection: 0.8,
                dynamicBinIndex: 2,
                dynamicBinClipId: "main-03",
                dynamicBinManifest: [
                    DynamicBinClip(id: "main-01", mediaRef: "/tmp/a.mp4"),
                    DynamicBinClip(id: "main-02", mediaRef: "/tmp/b.mp4"),
                    DynamicBinClip(id: "main-03", mediaRef: "/tmp/c.mp4")
                ],
                cutCadence: 0.42,
                transitionMode: .crossfade,
                compositorPreset: .mask,
                splitLayout: .split3,
                fade: 0.51,
                textProbability: 0.63,
                strictLooseBlend: 0.35,
                visualVariance: 0.72,
                crowdSteeringLevel: 0.26,
                performerVector: .neutral,
                audienceVector: .neutral
            ),
            vector: ParamVector.neutral.merged(ParamVectorPatch(
                textAmount: 0.55,
                compositeBias: 0.41,
                audioGain: 0.66,
                spatialX: 0.24,
                spatialY: 0.80,
                spatialZ: 0.49
            )),
            latestAudioFeatures: QuadAudioFeatures(
                rms: 0.42,
                spectralCentroid: 0.73,
                flux: 0.33,
                transientDensity: 0.57,
                updatedAt: 123_456
            ),
            statusTime: "10:22:31",
            statusSeverity: .warn,
            statusMessage: "GO blocked",
            hudTelemetryFrame: HUDTelemetryFrame(
                events: [
                    HUDActionEvent(
                        timestamp: 123,
                        sourceKind: .hotas,
                        controlID: "gd:y",
                        semanticAction: "cut_cadence",
                        value: 0.63,
                        phase: .changed,
                        stage: .mapped,
                        severity: .act,
                        outcome: "MAPPED"
                    )
                ],
                traces: [
                    HUDControlTrace(
                        id: "trace:cut_cadence",
                        values: [0.2, 0.4, 0.6],
                        latest: 0.6,
                        updatedAt: 124
                    )
                ]
            ),
            stateDevelopmentMetrics: StateDevelopmentMetrics(
                repeatability: 0.71,
                intensityTrend: 0.56,
                noveltySaturation: 0.63,
                headroom: 0.52,
                safetyContext: 0.84,
                stateDevelopmentIndex: 0.64,
                interventionNeedScore: 0.59,
                updatedAt: 123_500
            ),
            activeProposal: MLProposal(
                id: "proposal-1",
                lane: .audio,
                confidence: 0.82,
                rationale: "Pattern is steady with headroom",
                expectedEffect: "Latchable texture scene",
                timeoutMs: 2100,
                createdAt: 123_400,
                audio: MLProposalPayloadAudio(
                    kind: .structuredLatch,
                    suggestedBank: 2,
                    suggestedSampleID: "kick-loop",
                    chainAIntensityTarget: 0.48,
                    chainBIntensityTarget: 0.51,
                    densityTarget: 0.62,
                    latchSuggested: true
                )
            ),
            activeProposalCountdownSeconds: 1.7,
            programAudioState: ProgramAudioState(
                epoch: 6,
                updatedAt: 123_500,
                activeSampleBank: 2,
                activeChoirSampleBank: 3,
                choirContextActive: true,
                phoneGateCommitted: false,
                estimatedDensity: 0.58,
                effects: EffectsChainState(
                    chainAActive: true,
                    chainAIntensity: 0.72,
                    chainBActive: false,
                    chainBIntensity: 0.10
                ),
                master: QuadAudioFeatures(
                    rms: 0.42,
                    spectralCentroid: 0.73,
                    flux: 0.33,
                    transientDensity: 0.57,
                    updatedAt: 123_456
                ),
                stems: [
                    AudioStemFeatureFrame(
                        stem: .master,
                        rms: 0.42,
                        spectralCentroid: 0.73,
                        flux: 0.33,
                        transientDensity: 0.57
                    )
                ],
                activeProposalID: "proposal-1",
                structuredLatchActive: true,
                staticMacros: StaticAudioMacroState(
                    sampleMorph: 0.61,
                    articulation: 0.58,
                    timbre: 0.47,
                    textureSend: 0.39
                ),
                choirField: ChoirFieldState(spread: 0.66, depth: 0.52, detune: 0.33),
                staticVisualOverrideHeld: false
            )
        )

        let snapshot = VufineHUDSnapshot.from(input: input)
        XCTAssertTrue(snapshot.stateLine.contains("STATE MAIN"))
        XCTAssertTrue(snapshot.transportLine.contains("pending STATIC"))
        XCTAssertTrue(snapshot.safetyLine.contains("GO YES"))
        XCTAssertTrue(snapshot.inputsLine.contains("PUSH[ON trusted 2]"))
        XCTAssertTrue(snapshot.phoneLine.contains("pool 12"))
        XCTAssertTrue(snapshot.bankLine.contains("choirCtx ON"))
        XCTAssertTrue(snapshot.effectsLine.contains("A ON"))
        XCTAssertTrue(snapshot.controlRoleLine.contains("CHOIR FIELD"))
        XCTAssertTrue(snapshot.proceduralLine.contains("clip main-03"))
        XCTAssertTrue(snapshot.textBlendLine.contains("strict 0.35"))
        XCTAssertTrue(snapshot.vectorLine.contains("gain 0.66"))
        XCTAssertTrue(snapshot.audioLine.contains("centroid 73"))
        XCTAssertTrue(snapshot.proposalLine.contains("need 0.59"))
        XCTAssertTrue(snapshot.audioStateLine.contains("latch ON"))
        XCTAssertTrue(snapshot.statusLine.contains("WARN"))
        XCTAssertTrue(snapshot.statusLine.contains("GO blocked"))
        XCTAssertEqual(snapshot.dynamicGauges.count, 10)
        XCTAssertNotNil(snapshot.proposalWidget)
        XCTAssertEqual(snapshot.actionFeed.count, 1)
        XCTAssertFalse(snapshot.safetyTokens.isEmpty)
        XCTAssertFalse(snapshot.systemHealthLines.isEmpty)
    }
}
