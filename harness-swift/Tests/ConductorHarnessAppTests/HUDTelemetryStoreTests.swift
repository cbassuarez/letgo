@testable import ConductorHarnessApp
import ConductorCore
import XCTest

final class HUDTelemetryStoreTests: XCTestCase {
    func testPipelineRecordsRawMappedAppliedStages() async {
        let store = HUDTelemetryStore(eventCapacity: 32, tracePointCapacity: 8)
        let signal = ControlSignal(
            controlID: "gd:y",
            kind: .axis,
            phase: .changed,
            normalizedValue: 0.64,
            rawValue: 16384,
            timestamp: 1_000,
            sourceDeviceID: "x56",
            sourceKind: .hotas
        )

        await store.ingestRaw(signal: signal)
        await store.ingestMapped(signal: signal, action: .setCutCadence(0.64))
        await store.ingestApplied(
            signal: signal,
            action: .setCutCadence(0.64),
            severity: .apply,
            outcome: "ROUTED"
        )

        let frame = await store.snapshot(maxEvents: 8)
        XCTAssertEqual(frame.events.count, 3)
        XCTAssertEqual(frame.events.map(\.stage), [.applied, .mapped, .raw])
        XCTAssertEqual(frame.trace(for: "trace:cut_cadence")?.latest, 0.64)
    }

    func testRawStageCoalescesHighRateAxisSignals() async {
        let store = HUDTelemetryStore(eventCapacity: 32, tracePointCapacity: 8)

        let base = ControlSignal(
            controlID: "gd:x",
            kind: .axis,
            phase: .changed,
            normalizedValue: 0.2,
            rawValue: 100,
            timestamp: 500,
            sourceDeviceID: "x56",
            sourceKind: .hotas
        )
        let next = ControlSignal(
            controlID: "gd:x",
            kind: .axis,
            phase: .changed,
            normalizedValue: 0.7,
            rawValue: 200,
            timestamp: 500.02,
            sourceDeviceID: "x56",
            sourceKind: .hotas
        )

        await store.ingestRaw(signal: base)
        await store.ingestRaw(signal: next)

        let frame = await store.snapshot(maxEvents: 8)
        XCTAssertEqual(frame.events.count, 1)
        XCTAssertEqual(frame.events.first?.stage, .raw)
        XCTAssertEqual(frame.events.first?.value, 0.7)
        XCTAssertEqual(frame.trace(for: "gd:x")?.latest, 0.7)
    }
}
