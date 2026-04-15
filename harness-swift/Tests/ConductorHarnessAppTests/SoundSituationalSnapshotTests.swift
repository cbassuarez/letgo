@testable import ConductorHarnessApp
import ConductorCore
import XCTest

final class SoundSituationalSnapshotTests: XCTestCase {
    func testDeriveSoundModeTransitions() {
        let stopped = ConductorHarnessViewModel.deriveSoundMode(
            engineRunning: false,
            effectiveOutputMode: .off,
            choirContextActive: false,
            phonePoolCount: 0,
            phoneGateCommitted: false
        )
        XCTAssertEqual(stopped.primary, .normal)
        XCTAssertEqual(stopped.detail, .off)
        XCTAssertEqual(stopped.level, .nominal)

        let dynamic = ConductorHarnessViewModel.deriveSoundMode(
            engineRunning: true,
            effectiveOutputMode: .dynamic,
            choirContextActive: false,
            phonePoolCount: 0,
            phoneGateCommitted: false
        )
        XCTAssertEqual(dynamic.primary, .normal)
        XCTAssertEqual(dynamic.detail, .dynamic)
        XCTAssertEqual(dynamic.level, .nominal)

        let choirNoPool = ConductorHarnessViewModel.deriveSoundMode(
            engineRunning: true,
            effectiveOutputMode: .static,
            choirContextActive: true,
            phonePoolCount: 0,
            phoneGateCommitted: false
        )
        XCTAssertEqual(choirNoPool.primary, .phoneChoir)
        XCTAssertEqual(choirNoPool.detail, .static)
        XCTAssertEqual(choirNoPool.level, .critical)

        let choirArmedOnly = ConductorHarnessViewModel.deriveSoundMode(
            engineRunning: true,
            effectiveOutputMode: .static,
            choirContextActive: true,
            phonePoolCount: 8,
            phoneGateCommitted: false
        )
        XCTAssertEqual(choirArmedOnly.level, .caution)
    }

    func testResolveActiveSoundTargetUsesCuratedLabelThenFilenameFallback() {
        let entries: [String: URL] = [
            "main_b1_01": URL(fileURLWithPath: "/tmp/main_b1_01.wav"),
            "main_b1_02": URL(fileURLWithPath: "/tmp/main_b1_02.wav")
        ]

        let curated = ConductorHarnessViewModel.resolveActiveSoundTarget(
            selectedSampleID: "main_b1_01",
            sampleEntries: entries,
            labels: ["main_b1_01": "Curated Name"],
            choirContextActive: false,
            activeSampleBank: 1,
            activeChoirSampleBank: 2
        )
        XCTAssertEqual(curated.sampleID, "main_b1_01")
        XCTAssertEqual(curated.label, "Curated Name")
        XCTAssertEqual(curated.fileName, "main_b1_01.wav")
        XCTAssertEqual(curated.bankDomain, .main)

        let fallback = ConductorHarnessViewModel.resolveActiveSoundTarget(
            selectedSampleID: "main_b1_02",
            sampleEntries: entries,
            labels: [:],
            choirContextActive: true,
            activeSampleBank: 1,
            activeChoirSampleBank: 3
        )
        XCTAssertEqual(fallback.label, "main b1 02")
        XCTAssertEqual(fallback.bankDomain, .choir)
        XCTAssertEqual(fallback.bank, 3)
    }

    func testResolveActiveSoundTargetFallsBackWhenSelectedMissing() {
        let entries: [String: URL] = [
            "b": URL(fileURLWithPath: "/tmp/b.wav"),
            "a": URL(fileURLWithPath: "/tmp/a.wav")
        ]

        let target = ConductorHarnessViewModel.resolveActiveSoundTarget(
            selectedSampleID: "missing",
            sampleEntries: entries,
            labels: [:],
            choirContextActive: false,
            activeSampleBank: 2,
            activeChoirSampleBank: 1
        )

        XCTAssertEqual(target.sampleID, "a")
        XCTAssertEqual(target.fileName, "a.wav")
    }

    func testManipulationFreshness() {
        let focus = SoundManipulationFocus(
            source: "HOTAS",
            controlID: "gd:x",
            lane: "SAMPLE MORPH",
            normalizedValue: 0.62,
            updatedAt: 1_000
        )

        XCTAssertFalse(ConductorHarnessViewModel.isSoundManipulationStale(focus, nowMs: 1_600))
        XCTAssertTrue(ConductorHarnessViewModel.isSoundManipulationStale(focus, nowMs: 2_700))
        XCTAssertTrue(ConductorHarnessViewModel.isSoundManipulationStale(nil, nowMs: 2_700))
    }

    func testResolveRouteAndMIDIName() {
        let routes = [
            AudioRoute(id: "default-output", name: "Default", channelCount: 2),
            AudioRoute(id: "scarlett", name: "Scarlett", channelCount: 4)
        ]
        XCTAssertEqual(
            ConductorHarnessViewModel.resolveAudioRouteDisplayName(routes: routes, selectedRouteID: "scarlett"),
            "Scarlett (4ch)"
        )
        XCTAssertEqual(
            ConductorHarnessViewModel.resolveAudioRouteDisplayName(routes: routes, selectedRouteID: "missing"),
            "Default (2ch)"
        )
        XCTAssertEqual(
            ConductorHarnessViewModel.resolveAudioRouteDisplayName(routes: [AudioRoute](), selectedRouteID: "missing"),
            "NO OUTPUT ROUTES"
        )

        let midiInputs = [
            MIDIInputOption(id: "push", name: "Ableton Push"),
            MIDIInputOption(id: "keys", name: "MIDI Keys")
        ]
        XCTAssertEqual(
            ConductorHarnessViewModel.resolveMIDIInputDisplayName(inputs: midiInputs, selectedInputID: "keys"),
            "MIDI Keys"
        )
        XCTAssertEqual(
            ConductorHarnessViewModel.resolveMIDIInputDisplayName(inputs: midiInputs, selectedInputID: "missing"),
            "Ableton Push"
        )
        XCTAssertEqual(
            ConductorHarnessViewModel.resolveMIDIInputDisplayName(inputs: [MIDIInputOption](), selectedInputID: "missing"),
            "NO MIDI INPUTS"
        )
    }
}
