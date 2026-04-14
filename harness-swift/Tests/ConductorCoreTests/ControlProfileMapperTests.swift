import ConductorCore
import XCTest

final class ControlProfileMapperTests: XCTestCase {
    func testMapsVectorAxisToPatch() {
        let profile = ControlProfile.defaultX56StrictLive
        let mapper = ControlProfileMapper(profile: profile)

        let signal = ControlSignal(
            controlID: "gd:x",
            kind: .axis,
            phase: .changed,
            normalizedValue: 0.75,
            rawValue: 96,
            timestamp: 1_000,
            sourceDeviceID: "hotas:test",
            sourceKind: .hotas
        )

        let actions = mapper.map(signal: signal, laneIDs: [])
        XCTAssertEqual(actions, [.patchVector(ParamVectorPatch(spatialX: 0.75))])
    }

    func testOutputModeBucketsWithHysteresis() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .leftMainThrottle,
            controlID: "gd:z",
            sourceKind: .hotas,
            kind: .axis
        )]

        let mapper = ControlProfileMapper(profile: profile)

        let off = mapper.map(signal: axis("gd:z", value: 0.10), laneIDs: [])
        let dynamic = mapper.map(signal: axis("gd:z", value: 0.50), laneIDs: [])
        let staticMode = mapper.map(signal: axis("gd:z", value: 0.92), laneIDs: [])
        let holdStatic = mapper.map(signal: axis("gd:z", value: 0.72), laneIDs: [])

        XCTAssertEqual(off, [.armOutputMode(.off)])
        XCTAssertEqual(dynamic, [.armOutputMode(.dynamic)])
        XCTAssertEqual(staticMode, [.armOutputMode(.static)])
        XCTAssertTrue(holdStatic.isEmpty)
    }

    func testBottomToggleQueuesTimelineStep() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .leftBottomToggle3,
            controlID: "btn:22",
            sourceKind: .hotas,
            kind: .button
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let actions = mapper.map(signal: button("btn:22"), laneIDs: ["preshow", "introduction", "ending"])

        XCTAssertEqual(actions, [.queueTimelineStep("introduction")])
    }

    func testRightAcceptButtonMapsToProposalAcceptAction() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .rightAcceptButton,
            controlID: "btn:1",
            sourceKind: .hotas,
            kind: .button
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let actions = mapper.map(signal: button("btn:1"), laneIDs: [])
        XCTAssertEqual(actions, [.acceptActiveProposal])
    }

    func testSecondThrottleControlsTextProbability() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .leftSecondThrottle,
            controlID: "gd:wheel",
            sourceKind: .hotas,
            kind: .axis
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let actions = mapper.map(
            signal: axis("gd:wheel", value: 0.62),
            laneIDs: ["preshow", "introduction"],
            context: ControlRuntimeContext(
                activeOutputMode: .static,
                phoneChoirModeActive: false,
                allowStaticVideoOverride: true,
                staticVisualClutchActive: false
            )
        )

        XCTAssertEqual(actions, [.setTextProbability(0.62)])
    }

    func testRightStickYBecomesDynamicCutCadenceInDynamicMode() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .rightStickY,
            controlID: "gd:y",
            sourceKind: .hotas,
            kind: .axis
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let actions = mapper.map(
            signal: axis("gd:y", value: 0.44),
            laneIDs: [],
            context: ControlRuntimeContext(
                activeOutputMode: .dynamic,
                phoneChoirModeActive: false,
                allowStaticVideoOverride: true,
                staticVisualClutchActive: false
            )
        )

        XCTAssertEqual(actions, [.setCutCadence(0.44)])
    }

    func testRightStickXBecomesDynamicSourceSelectorInDynamicMode() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .rightStickX,
            controlID: "gd:x",
            sourceKind: .hotas,
            kind: .axis
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let actions = mapper.map(
            signal: axis("gd:x", value: 0.88),
            laneIDs: [],
            context: ControlRuntimeContext(
                activeOutputMode: .dynamic,
                phoneChoirModeActive: false,
                allowStaticVideoOverride: true,
                staticVisualClutchActive: false
            )
        )

        XCTAssertEqual(actions, [.setDynamicBinSelection(0.88)])
    }

    func testRotaryOneStepAdjustsStrictLooseBlend() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .leftRotary1Increase,
            controlID: "btn:15",
            sourceKind: .hotas,
            kind: .button
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let first = mapper.map(signal: button("btn:15"), laneIDs: [])
        let second = mapper.map(signal: button("btn:15"), laneIDs: [])

        XCTAssertEqual(first, [.setStrictLooseBlend(0.58)])
        guard case let .setStrictLooseBlend(value) = second.first else {
            XCTFail("Expected strict/loose blend action on second step")
            return
        }
        XCTAssertEqual(value, 0.66, accuracy: 0.0001)
    }

    func testRotaryUsesChoirDomainWhenChoirContextIsActive() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .leftModeRotary,
            controlID: "gd:dial",
            sourceKind: .hotas,
            kind: .axis
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let actions = mapper.map(
            signal: axis("gd:dial", value: 0.9),
            laneIDs: [],
            context: ControlRuntimeContext(
                activeOutputMode: .off,
                phoneChoirModeActive: true,
                allowStaticVideoOverride: true,
                staticVisualClutchActive: false
            )
        )

        XCTAssertEqual(actions, [.setSampleBank(3, domain: .choir)])
    }

    func testStaticModeRoutesRightStickToAudioMacroWithoutClutch() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .rightStickX,
            controlID: "gd:x",
            sourceKind: .hotas,
            kind: .axis
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let actions = mapper.map(
            signal: axis("gd:x", value: 0.77),
            laneIDs: [],
            context: ControlRuntimeContext(
                activeOutputMode: .static,
                phoneChoirModeActive: false,
                allowStaticVideoOverride: false,
                staticVisualClutchActive: false
            )
        )

        XCTAssertEqual(actions, [.setStaticSampleMorph(0.77)])
    }

    func testStaticModeClutchRoutesRightStickToVisualOverridePatch() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .rightStickX,
            controlID: "gd:x",
            sourceKind: .hotas,
            kind: .axis
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let actions = mapper.map(
            signal: axis("gd:x", value: 0.77),
            laneIDs: [],
            context: ControlRuntimeContext(
                activeOutputMode: .static,
                phoneChoirModeActive: false,
                allowStaticVideoOverride: true,
                staticVisualClutchActive: true
            )
        )

        XCTAssertEqual(actions, [.patchVector(ParamVectorPatch(spatialX: 0.77))])
    }

    func testToggleDirectionalHoldProducesChoirActions() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [ControlBinding(
            role: .leftToggle1Directional,
            controlID: "gd:slider2",
            sourceKind: .hotas,
            kind: .axis
        )]

        let mapper = ControlProfileMapper(profile: profile)
        let up = mapper.map(signal: axis("gd:slider2", value: 1.0), laneIDs: [])
        let neutral = mapper.map(signal: axis("gd:slider2", value: 0.5), laneIDs: [])
        let down = mapper.map(signal: axis("gd:slider2", value: 0.0), laneIDs: [])

        XCTAssertEqual(up, [.setPhoneChoirContextActive(true), .triggerPhoneChoirNoteOn])
        XCTAssertEqual(neutral, [.triggerPhoneChoirNoteOff, .setPhoneChoirContextActive(false)])
        XCTAssertEqual(down, [.setPhoneChoirContextActive(false), .triggerPhoneChoirNoteOff, .stopAllPhoneAudio])
    }

    func testDeviceAwareBindingSelectsMatchingSourceDeviceID() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings = [
            ControlBinding(
                role: .rightStickX,
                controlID: "btn:2",
                sourceKind: .hotas,
                sourceDeviceID: "hotas:right",
                kind: .axis
            ),
            ControlBinding(
                role: .leftStaticVisualClutch,
                controlID: "btn:2",
                sourceKind: .hotas,
                sourceDeviceID: "hotas:left",
                kind: .button
            )
        ]

        let mapper = ControlProfileMapper(profile: profile)

        let rightActions = mapper.map(
            signal: ControlSignal(
                controlID: "btn:2",
                kind: .axis,
                phase: .changed,
                normalizedValue: 0.68,
                rawValue: 86,
                timestamp: 2_000,
                sourceDeviceID: "hotas:right",
                sourceKind: .hotas
            ),
            laneIDs: []
        )
        XCTAssertEqual(rightActions, [.patchVector(ParamVectorPatch(spatialX: 0.68))])

        let leftActions = mapper.map(
            signal: ControlSignal(
                controlID: "btn:2",
                kind: .button,
                phase: .began,
                normalizedValue: 1,
                rawValue: 1,
                timestamp: 2_100,
                sourceDeviceID: "hotas:left",
                sourceKind: .hotas
            ),
            laneIDs: []
        )
        XCTAssertEqual(leftActions, [.setStaticVisualOverrideHold(true)])
    }

    func testProfileValidationDetectsMissingRequiredRoles() {
        var profile = ControlProfile.defaultX56StrictLive
        profile.bindings.removeAll { $0.role == .rightTakeButton }
        let missing = profile.missingRequiredRoles()
        XCTAssertTrue(missing.contains(.rightTakeButton))
        XCTAssertFalse(profile.isValid)
    }

    private func axis(_ controlID: String, value: Double) -> ControlSignal {
        ControlSignal(
            controlID: controlID,
            kind: .axis,
            phase: .changed,
            normalizedValue: value,
            rawValue: Int(value * 127),
            timestamp: 1_000,
            sourceDeviceID: "hotas:test",
            sourceKind: .hotas
        )
    }

    private func button(_ controlID: String) -> ControlSignal {
        ControlSignal(
            controlID: controlID,
            kind: .button,
            phase: .began,
            normalizedValue: 1,
            rawValue: 1,
            timestamp: 1_000,
            sourceDeviceID: "hotas:test",
            sourceKind: .hotas
        )
    }
}
