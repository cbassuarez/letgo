@testable import ConductorHarnessApp
import ConductorCore
import XCTest

final class PushDeckEventRouterTests: XCTestCase {
    private let router = PushDeckEventRouter()

    func testMacroLaneMappingHonorsModeContexts() {
        let dynamicEvent = PushDeckEventPayload(
            eventId: "evt-dyn",
            sourceId: "controller",
            controlKind: .macro,
            modeContext: .dynamic,
            timingMode: .immediate,
            macro: PushDeckMacroControl(lane: 1, value: 0.72),
            issuedAt: 1
        )
        let dynamic = router.resolve(event: dynamicEvent, fallbackMode: .static)
        XCTAssertEqual(dynamic.intents, [.controlAction(.setDynamicBinSelection(0.72))])

        let staticEvent = PushDeckEventPayload(
            eventId: "evt-static",
            sourceId: "controller",
            controlKind: .macro,
            modeContext: .static,
            timingMode: .immediate,
            macro: PushDeckMacroControl(lane: 2, value: 0.42),
            issuedAt: 1
        )
        let staticResult = router.resolve(event: staticEvent, fallbackMode: .dynamic)
        XCTAssertEqual(staticResult.intents, [.controlAction(.setStaticArticulation(0.42))])

        let choirEvent = PushDeckEventPayload(
            eventId: "evt-choir",
            sourceId: "controller",
            controlKind: .macro,
            modeContext: .choir,
            timingMode: .immediate,
            macro: PushDeckMacroControl(lane: 3, value: 0.33),
            issuedAt: 1
        )
        let choirResult = router.resolve(event: choirEvent, fallbackMode: .dynamic)
        XCTAssertEqual(choirResult.intents, [.controlAction(.setChoirFieldDetune(0.33))])
    }

    func testMacroLaneSevenMapsToEffectsChainA() {
        let event = PushDeckEventPayload(
            eventId: "evt-fx",
            sourceId: "controller",
            controlKind: .macro,
            modeContext: .dynamic,
            timingMode: .immediate,
            macro: PushDeckMacroControl(lane: 7, value: 0.64),
            issuedAt: 1
        )

        let result = router.resolve(event: event, fallbackMode: .dynamic)
        XCTAssertEqual(
            result.intents,
            [.controlAction(.setEffectsChain(chain: .a, active: true, intensity: 0.64))]
        )
    }

    func testBankSelectMapsToSampleBankAction() {
        let event = PushDeckEventPayload(
            eventId: "evt-bank",
            sourceId: "controller",
            controlKind: .bankSelect,
            modeContext: .auto,
            timingMode: .immediate,
            bank: PushDeckBankControl(domain: .choir, bank: 3),
            issuedAt: 1
        )

        let result = router.resolve(event: event, fallbackMode: .static)
        XCTAssertEqual(result.intents, [.controlAction(.setSampleBank(3, domain: .choir))])
    }

    func testPadAutoModeUsesFallbackContext() {
        let event = PushDeckEventPayload(
            eventId: "evt-pad",
            sourceId: "controller",
            controlKind: .padDown,
            modeContext: .auto,
            timingMode: .quantized,
            quantIntervalMs: 140,
            pad: PushDeckPadControl(row: 6, column: 1, slot: 49, pressure: 0.7, velocity: 0.66),
            issuedAt: 1
        )

        let result = router.resolve(event: event, fallbackMode: .choir)
        XCTAssertEqual(result.ignoredReason, nil)
        guard case .pad(let intent)? = result.intents.first else {
            return XCTFail("Expected pad intent")
        }
        XCTAssertEqual(intent.mode, .choir)
        XCTAssertEqual(intent.phase, .down)
        XCTAssertEqual(intent.slot, 49)
        XCTAssertEqual(intent.timingMode, .quantized)
        XCTAssertEqual(intent.quantIntervalMs, 140)
    }

    func testMissingMacroPayloadIsIgnored() {
        let event = PushDeckEventPayload(
            eventId: "evt-invalid",
            sourceId: "controller",
            controlKind: .macro,
            modeContext: .dynamic,
            timingMode: .immediate,
            issuedAt: 1
        )

        let result = router.resolve(event: event, fallbackMode: .dynamic)
        XCTAssertTrue(result.intents.isEmpty)
        XCTAssertEqual(result.ignoredReason, "macro payload missing")
    }

    func testMLParamRoutesPhonePadEchoProbability() {
        let event = PushDeckEventPayload(
            eventId: "evt-ml-param",
            sourceId: "controller",
            controlKind: .mlParam,
            modeContext: .auto,
            timingMode: .immediate,
            mlParam: PushDeckMLParamControl(key: .phonePadEchoProbability, value: 0.18),
            issuedAt: 1
        )

        let result = router.resolve(event: event, fallbackMode: .dynamic)
        XCTAssertEqual(
            result.intents,
            [.mlParam(PushDeckMLParamControl(key: .phonePadEchoProbability, value: 0.18))]
        )
    }

    func testLongStripRoutesToDedicatedTextureSendAction() {
        let event = PushDeckEventPayload(
            eventId: "evt-long-strip",
            sourceId: "controller",
            controlKind: .longStrip,
            modeContext: .auto,
            timingMode: .immediate,
            longStrip: PushDeckLongStripControl(value: 0.61),
            issuedAt: 1
        )

        let result = router.resolve(event: event, fallbackMode: .dynamic)
        XCTAssertEqual(result.intents, [.controlAction(.setStaticTextureSend(0.61))])
    }
}
