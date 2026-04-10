import ConductorCore
import Foundation
import XCTest

final class OutputLatchControllerTests: XCTestCase {
    func testStaticRequiresLaneBeforeFire() {
        var latch = OutputLatchController(timeoutSeconds: 8, now: Date(timeIntervalSince1970: 100))
        _ = latch.armMode("static", now: Date(timeIntervalSince1970: 101))

        let fire = latch.fire(now: Date(timeIntervalSince1970: 102))
        XCTAssertNil(fire)
        XCTAssertEqual(latch.snapshot.status.severity, .error)
        XCTAssertEqual(latch.snapshot.status.message, "Blocked: lane arm required")
    }

    func testArmedTimesOutAfterWindow() {
        var latch = OutputLatchController(timeoutSeconds: 8, now: Date(timeIntervalSince1970: 100))
        _ = latch.armMode("dynamic", now: Date(timeIntervalSince1970: 101))

        _ = latch.tick(now: Date(timeIntervalSince1970: 110))

        XCTAssertFalse(latch.snapshot.isArmed)
        XCTAssertEqual(latch.snapshot.status.severity, .warn)
        XCTAssertEqual(latch.snapshot.status.message, "Arm timeout")
    }

    func testStaticFireIncludesLaneAndClearsLatch() {
        var latch = OutputLatchController(timeoutSeconds: 8, now: Date(timeIntervalSince1970: 100))
        _ = latch.armMode("static", now: Date(timeIntervalSince1970: 101))
        _ = latch.armLane("main-01", now: Date(timeIntervalSince1970: 102))

        let fire = latch.fire(now: Date(timeIntervalSince1970: 103))

        XCTAssertEqual(fire?.mode, "static")
        XCTAssertEqual(fire?.laneId, "main-01")
        XCTAssertNotNil(fire?.latchId)
        XCTAssertFalse(latch.snapshot.isArmed)
        XCTAssertEqual(latch.snapshot.status.severity, .success)
    }
}
