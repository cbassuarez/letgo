@testable import ConductorHarnessApp
import XCTest

@MainActor
final class PerformanceModeStateTests: XCTestCase {
    func testStartupSelectionConnectedOpensSafetyAndVufine() {
        let state = PerformanceModeState(mode: .performancePrimary)

        let transition = state.transitionForStartupSelection(hasConnectedVufine: true)
        XCTAssertEqual(transition.open, [.safetyMonitor, .vufineRealtime])
        XCTAssertTrue(transition.close.isEmpty)
        XCTAssertEqual(state.activeLayout, .safetyAndVufine)
    }

    func testStartupSelectionDisconnectedClosesVufineAndKeepsSafety() {
        let state = PerformanceModeState(mode: .performancePrimary)

        let transition = state.transitionForStartupSelection(hasConnectedVufine: false)
        XCTAssertEqual(transition.open, [.safetyMonitor])
        XCTAssertEqual(transition.close, [.vufineRealtime])
        XCTAssertEqual(state.activeLayout, .safetyOnly)
    }

    func testReopenStartupChooserTransition() {
        let state = PerformanceModeState(mode: .performancePrimary)
        let transition = state.reopenStartupChooserTransition()
        XCTAssertEqual(transition.open, [.launchGate])
        XCTAssertTrue(transition.close.isEmpty)
    }
}
