import ConductorCore
import XCTest

final class MIDIEngineTests: XCTestCase {
    func testIngestorIgnoresNoteEventsButMapsControlChange() {
        let source = SimulatedMIDIEventSource()
        var patches: [ParamVectorPatch] = []
        let ingestor = MIDIIngestor(source: source) { patch in
            patches.append(patch)
        }

        ingestor.start()
        source.inject(.noteOn(note: 60, velocity: 100))
        source.inject(.noteOff(note: 60))
        XCTAssertTrue(patches.isEmpty)

        source.inject(MIDIEvent(controller: MIDIControlMap.audioGain.rawValue, value: 64))
        XCTAssertEqual(patches.count, 1)
        XCTAssertEqual(patches[0].audioGain ?? -1, 64.0 / 127.0, accuracy: 0.0001)
    }
}
