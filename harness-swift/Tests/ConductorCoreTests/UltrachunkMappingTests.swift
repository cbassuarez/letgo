import ConductorCore
import XCTest

final class UltrachunkMappingTests: XCTestCase {
    func testGranularityAndIntensityAreMonotonicAndBounded() {
        let speeds: [Double] = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }
        let granularities = speeds.map(UltrachunkMapping.granularity(forSpeed:))
        let intensities = speeds.map(UltrachunkMapping.intensity(forSpeed:))

        for value in granularities {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
        for value in intensities {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }

        for index in 1 ..< granularities.count {
            XCTAssertGreaterThanOrEqual(granularities[index], granularities[index - 1], "granularity should be monotonic")
            XCTAssertGreaterThanOrEqual(intensities[index], intensities[index - 1], "intensity should be monotonic")
        }
    }

    func testTwistMappingUsesBipolarLanesWithDeadband() {
        let neutral = UltrachunkMapping.twistDSPState(twistNormalized: 0.5, intensity: 0.5, spaceBoost: 0.3)
        XCTAssertEqual(neutral.twistLane, .neutral)
        XCTAssertEqual(neutral.spectralAmount, 0)
        XCTAssertEqual(neutral.crushAmount, 0)

        let spectral = UltrachunkMapping.twistDSPState(twistNormalized: 0.92, intensity: 0.6, spaceBoost: 0.8)
        XCTAssertEqual(spectral.twistLane, .spectral)
        XCTAssertGreaterThan(spectral.spectralAmount, 0.1)
        XCTAssertEqual(spectral.crushAmount, 0)
        XCTAssertEqual(spectral.downsampleFactor, 1)

        let crusher = UltrachunkMapping.twistDSPState(twistNormalized: 0.07, intensity: 0.9, spaceBoost: 0.2)
        XCTAssertEqual(crusher.twistLane, .crusher)
        XCTAssertEqual(crusher.spectralAmount, 0)
        XCTAssertGreaterThan(crusher.crushAmount, 0.1)
        XCTAssertGreaterThan(crusher.downsampleFactor, 1)
        XCTAssertLessThan(crusher.bitDepth, 16)
    }
}
