@testable import ConductorHarnessApp
import XCTest

final class VufineDisplayCoordinatorTests: XCTestCase {
    func testPreferredRouteUsesExternalDisplayWhenAvailable() {
        let screens = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true),
            VufineScreenDescriptor(id: "2", name: "Vufine+", frame: .zero, isPrimary: false)
        ]
        let route = VufineDisplayCoordinator.preferredRoute(for: screens)
        XCTAssertEqual(route, .external(name: "Vufine+"))
    }

    func testPreferredRouteFallsBackToPrimaryDisplay() {
        let screens = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true)
        ]
        let route = VufineDisplayCoordinator.preferredRoute(for: screens)
        XCTAssertEqual(route, .primaryFallback(name: "MacBook"))
    }

    func testPreferredRouteHandlesHotPlugTransition() {
        let withExternal = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true),
            VufineScreenDescriptor(id: "2", name: "Vufine+", frame: .zero, isPrimary: false)
        ]
        let withoutExternal = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true)
        ]

        XCTAssertEqual(
            VufineDisplayCoordinator.preferredRoute(for: withExternal),
            .external(name: "Vufine+")
        )
        XCTAssertEqual(
            VufineDisplayCoordinator.preferredRoute(for: withoutExternal),
            .primaryFallback(name: "MacBook")
        )
    }

    func testExternalDisplayPresenceDetector() {
        let withExternal = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true),
            VufineScreenDescriptor(id: "2", name: "Vufine+", frame: .zero, isPrimary: false)
        ]
        let withoutExternal = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true)
        ]

        XCTAssertTrue(VufineDisplayCoordinator.hasExternalDisplay(withExternal))
        XCTAssertFalse(VufineDisplayCoordinator.hasExternalDisplay(withoutExternal))
    }
}
