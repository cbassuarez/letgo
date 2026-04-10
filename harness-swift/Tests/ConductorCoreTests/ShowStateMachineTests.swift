import ConductorCore
import Foundation
import XCTest

final class ShowStateMachineTests: XCTestCase {
    func testDeterministicCueIDsForFixedTimes() throws {
        let machine = ShowStateMachine()
        let t0 = Date(timeIntervalSince1970: 1_000)

        let first = try machine.apply(action: .start, at: t0)
        let second = try machine.apply(action: .jump, at: t0.addingTimeInterval(4), targetState: .introduction)

        XCTAssertEqual(first.cueId, "preshow:0")
        XCTAssertEqual(second.cueId, "introduction:4000")
    }

    func testMainAddsFixedAndDynamicFlags() throws {
        let machine = ShowStateMachine()
        let t0 = Date(timeIntervalSince1970: 1_000)

        _ = try machine.apply(action: .start, at: t0)
        _ = try machine.apply(action: .jump, at: t0.addingTimeInterval(2), targetState: .introduction)
        let mainCue = try machine.apply(action: .jump, at: t0.addingTimeInterval(3), targetState: .main)

        XCTAssertEqual(mainCue.payload["showFixed"], "true")
        XCTAssertEqual(mainCue.payload["showDynamic"], "true")
    }

    func testStartIsIdempotentWhenAlreadyInPreshow() throws {
        let machine = ShowStateMachine()
        let t0 = Date(timeIntervalSince1970: 1_000)

        let first = try machine.apply(action: .start, at: t0)
        let second = try machine.apply(action: .start, at: t0.addingTimeInterval(2))

        XCTAssertEqual(first.showState, .preshow)
        XCTAssertEqual(second.showState, .preshow)
        XCTAssertEqual(second.cueId, "preshow:2000")
    }
}
