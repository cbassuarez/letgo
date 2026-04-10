import ConductorCore
import XCTest

final class WebSocketConductorClientTests: XCTestCase {
    func testRetryDelayIsBoundedAndCapped() {
        let first = WebSocketConductorClient.retryDelaySeconds(attempt: 1, jitterSource: 0.0)
        let later = WebSocketConductorClient.retryDelaySeconds(attempt: 10, jitterSource: 1.0)

        XCTAssertGreaterThanOrEqual(first, 1.0)
        XCTAssertLessThanOrEqual(first, 30.0)
        XCTAssertGreaterThanOrEqual(later, 1.0)
        XCTAssertLessThanOrEqual(later, 30.0)
    }

    func testSilenceThresholdTransitions() {
        XCTAssertEqual(WebSocketConductorClient.stateForSilence(elapsedSeconds: 5), .online)
        XCTAssertEqual(WebSocketConductorClient.stateForSilence(elapsedSeconds: 21), .degraded)
        XCTAssertEqual(WebSocketConductorClient.stateForSilence(elapsedSeconds: 31), .offline)
    }
}
