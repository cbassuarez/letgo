@testable import ConductorHarnessApp
import XCTest

final class VideoOutDisplayCoordinatorTests: XCTestCase {
    func testPreferredRouteUsesDedicatedExternalWhenVufineScreenIsReserved() {
        let screens = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true),
            VufineScreenDescriptor(id: "2", name: "Vufine+", frame: .zero, isPrimary: false),
            VufineScreenDescriptor(id: "3", name: "House HDMI", frame: .zero, isPrimary: false)
        ]

        let route = VideoOutDisplayCoordinator.preferredRoute(for: screens, avoidingScreenID: "2")
        XCTAssertEqual(route, .external(name: "House HDMI"))
    }

    func testPreferredRouteSharesExternalWhenOnlyOneExternalDisplayExists() {
        let screens = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true),
            VufineScreenDescriptor(id: "2", name: "Vufine+", frame: .zero, isPrimary: false)
        ]

        let route = VideoOutDisplayCoordinator.preferredRoute(for: screens, avoidingScreenID: "2")
        XCTAssertEqual(route, .externalShared(name: "Vufine+"))
    }

    func testPreferredRouteFallsBackToPrimaryWhenNoExternalDisplayExists() {
        let screens = [
            VufineScreenDescriptor(id: "1", name: "MacBook", frame: .zero, isPrimary: true)
        ]

        let route = VideoOutDisplayCoordinator.preferredRoute(for: screens, avoidingScreenID: nil)
        XCTAssertEqual(route, .primaryFallback(name: "MacBook"))
    }
}
