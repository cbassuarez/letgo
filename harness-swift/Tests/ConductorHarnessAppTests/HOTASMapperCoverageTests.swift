@testable import ConductorHarnessApp
import ConductorCore
import XCTest

final class HOTASMapperCoverageTests: XCTestCase {
    func testHotspotCoverageMatchesMapperRoles() {
        let hotspotRoles = Set(HOTASHotspotDescriptor.all.map(\.role))
        XCTAssertEqual(hotspotRoles, Set(ControlRole.mapperRoles))
    }

    func testHotspotKindSupportMatchesRoleCaptureKinds() {
        for hotspot in HOTASHotspotDescriptor.all {
            XCTAssertEqual(hotspot.supportedKinds, hotspot.role.captureKinds, "Kind mismatch for \(hotspot.role.rawValue)")
        }
    }
}
