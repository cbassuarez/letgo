@testable import ConductorHarnessApp
import XCTest

@MainActor
final class InspectorPresentationStateTests: XCTestCase {
    func testPresentFromSourceUpdatesState() {
        let state = InspectorPresentationState()

        state.present(from: .vufine)

        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.source, .vufine)
        XCTAssertEqual(state.lastActiveSource, .vufine)
    }

    func testDismissClearsPresentationOnly() {
        let state = InspectorPresentationState()
        state.present(from: .fullConsole)

        state.dismiss()

        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state.lastActiveSource, .fullConsole)
    }

    func testPresentFromLastActiveSourceUsesMarkedSource() {
        let state = InspectorPresentationState()
        state.markActive(.safety)

        state.presentFromLastActiveSource()

        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.source, .safety)
    }
}
