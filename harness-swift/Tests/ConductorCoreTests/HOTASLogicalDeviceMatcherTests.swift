import ConductorCore
import XCTest

final class HOTASLogicalDeviceMatcherTests: XCTestCase {
    func testClassifiesStickAndThrottleAxes() {
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.classify(sourceDeviceID: "x56-any", controlID: "gd:x"),
            .x56Stick
        )
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.classify(sourceDeviceID: "x56-any", controlID: "gd:wheel"),
            .x56Throttle
        )
    }

    func testClassifiesButtonRanges() {
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.classify(sourceDeviceID: "x56-any", controlID: "btn:2"),
            .x56Stick
        )
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.classify(sourceDeviceID: "x56-any", controlID: "btn:24"),
            .x56Throttle
        )
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.classify(sourceDeviceID: "x56-any", controlID: "btn:34"),
            .x56Throttle
        )
    }

    func testNormalizesCookieSuffixedControlIDs() {
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.normalizedControlID("gd:rz#1048576"),
            "gd:rz"
        )
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.classify(sourceDeviceID: "x56-any", controlID: "btn:35#555"),
            .x56Throttle
        )
    }

    func testCanonicalControlIDVariantsCollapseCookieAndReportSuffixes() {
        let variants = HOTASLogicalDeviceMatcher.canonicalControlIDVariants("gd:x#22@r0p-1")
        XCTAssertTrue(variants.contains("gd:x#22@r0p-1"))
        XCTAssertTrue(variants.contains("gd:x#22"))
        XCTAssertTrue(variants.contains("gd:x"))
    }

    func testFallsBackToDeviceNameHints() {
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.classify(sourceDeviceID: "Logitech X56 Stick", controlID: "unknown"),
            .x56Stick
        )
        XCTAssertEqual(
            HOTASLogicalDeviceMatcher.classify(sourceDeviceID: "Logitech X56 Throttle", controlID: "unknown"),
            .x56Throttle
        )
    }

    func testProfileBindingResolutionUsesLogicalDeviceAffinity() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [
            ControlBinding(role: .rightAcceptButton, controlID: "btn:1", sourceKind: .hotas, kind: .button),
            ControlBinding(role: .leftBottomToggle1, controlID: "btn:1", sourceKind: .hotas, kind: .button)
        ]

        let stickSignal = ControlSignal(
            controlID: "btn:1",
            kind: .button,
            phase: .began,
            normalizedValue: 1,
            rawValue: 1,
            timestamp: 1_000,
            sourceDeviceID: "x56-stick",
            sourceKind: .hotas
        )

        let matchedRoles = profile.bindings(for: stickSignal).map(\.role)
        XCTAssertEqual(matchedRoles, [.rightAcceptButton])
    }

    func testBindingResolutionMatchesNormalizedControlID() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [
            ControlBinding(
                role: .rightStickTwist,
                controlID: "gd:rz",
                sourceKind: .hotas,
                kind: .axis
            )
        ]

        let signal = ControlSignal(
            controlID: "gd:rz#1048576",
            kind: .axis,
            phase: .changed,
            normalizedValue: 0.72,
            rawValue: 72,
            timestamp: 1_000,
            sourceDeviceID: "hotas:test",
            sourceKind: .hotas
        )

        let matchedRoles = profile.bindings(for: signal).map(\.role)
        XCTAssertEqual(matchedRoles, [.rightStickTwist])
    }

    func testBindingResolutionMatchesControlIDsWithReportSuffixes() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [
            ControlBinding(
                role: .rightStickX,
                controlID: "gd:x#22",
                sourceKind: .hotas,
                kind: .axis
            )
        ]

        let signal = ControlSignal(
            controlID: "gd:x#22@r0p-1",
            kind: .axis,
            phase: .changed,
            normalizedValue: 0.41,
            rawValue: 41,
            timestamp: 1_000,
            sourceDeviceID: "hotas:test",
            sourceKind: .hotas
        )

        let matchedRoles = profile.bindings(for: signal).map(\.role)
        XCTAssertEqual(matchedRoles, [.rightStickX])
    }
}
