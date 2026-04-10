import ConductorCore
import Foundation
import XCTest

final class TextSelectionEngineTests: XCTestCase {
    func testSelectionHonorsArcAndCooldown() async {
        let engine = TextSelectionEngine()
        let cueId = "main:1000"
        let now = Date(timeIntervalSince1970: 10_000)

        let bank = [
            ScriptCandidate(
                id: "a",
                arc: .arc2,
                tags: ["confession"],
                text: "line a",
                weight: 0.7,
                cooldown: 12,
                tone: "confessional"
            ),
            ScriptCandidate(
                id: "b",
                arc: .arc3,
                tags: ["release"],
                text: "line b",
                weight: 0.9,
                cooldown: 12,
                tone: "lyrical"
            )
        ]

        let first = await engine.select(
            from: bank,
            cueId: cueId,
            arc: .arc2,
            vector: .neutral,
            now: now
        )

        XCTAssertEqual(first.selectedId, "a")

        let second = await engine.select(
            from: bank,
            cueId: cueId,
            arc: .arc2,
            vector: .neutral,
            now: now.addingTimeInterval(1)
        )

        XCTAssertNil(second.selectedId)
        XCTAssertFalse(second.rulePass)
    }
}
