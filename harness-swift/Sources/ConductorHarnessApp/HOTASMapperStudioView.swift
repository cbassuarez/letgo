import ConductorCore
import SwiftUI

struct HOTASMapperStudioView: View {
    let model: ConductorHarnessViewModel
    @StateObject private var state = HOTASMapperWindowState()

    @Environment(\.dismissWindow) private var dismissWindow

    @State private var showClearAllConfirmation = false
    @State private var stickSurfaceMode: StickSurfaceMode = .combined
    @State private var snapshot = HOTASMapperRenderSnapshot.empty
    @State private var lastSnapshotRefreshMs: TimeInterval = 0
    private let refreshPulse = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    private let panelCornerRadius: CGFloat = 0

    private enum StickSurfaceMode: String, CaseIterable, Identifiable {
        case buttons = "Stick Buttons"
        case movement = "Stick Movement"
        case combined = "Combined"

        var id: String { rawValue }
    }

    private var groupedFunctions: [(group: ControlRoleGroup, items: [HOTASFunctionDescriptor])] {
        let grouped = Dictionary(grouping: HOTASFunctionDescriptor.ordered, by: \.group)
        return ControlRoleGroup.allCases.compactMap { group in
            guard let entries = grouped[group], !entries.isEmpty else { return nil }
            return (group, entries)
        }
    }

    private var canArmProfile: Bool {
        snapshot.missingRequiredRoles.isEmpty && snapshot.bindingConflicts.isEmpty
    }

    private var rolesByHotspotID: [ControlRole: [ControlRole]] {
        var map: [ControlRole: [ControlRole]] = [:]
        for binding in snapshot.profileBindings {
            guard let hotspot = hotspotForBinding(binding) else { continue }
            map[hotspot.id, default: []].append(binding.role)
        }
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar

            HStack(alignment: .top, spacing: 10) {
                functionPanel
                    .frame(width: 350)

                mappingCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                detailPanel
                    .frame(width: 330)
            }

            validationRail
        }
        .padding(14)
        .frame(minWidth: 1380, minHeight: 880)
        .background(ConsoleTheme.consoleBackground)
        .tint(ConsoleTheme.lampGreen)
        .preferredColorScheme(.dark)
        .transaction { transaction in
            transaction.animation = nil
        }
        .animation(nil, value: snapshot)
        .overlay {
            WindowAccessor { window in
                WindowChromeCoordinator.applyChromelessHUD(to: window, isResizable: true)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            model.ensureHOTASTrainingSession()
            state.selectedRole = state.selectedRole ?? .rightStickX
            refreshSnapshot(force: true)
        }
        .onReceive(refreshPulse) { _ in
            refreshSnapshot()
            guard snapshot.trainingActive else { return }
            guard let sweep = state.calibrationSweep,
                  let signal = snapshot.lastSignal,
                  snapshot.bindings(for: sweep.role).contains(where: { signalMatches(binding: $0, signal: signal) }) else {
                return
            }
            state.updateSweep(current: signal.normalizedValue)
        }
        .onDisappear {
            model.finishHOTASTrainingForLiveControl()
        }
        .confirmationDialog(
            "Clear all HOTAS bindings?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Bindings", role: .destructive) {
                model.clearAllHOTASBindings()
                refreshSnapshot(force: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every mapped role from the current HOTAS profile.")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text("HOTAS MAPPER STUDIO")
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.9))

            statusChip(snapshot.trainingActive ? "TRAINING LIVE" : "TRAINING PAUSED", color: snapshot.trainingActive ? ConsoleTheme.lampGreen : ConsoleTheme.lampAmber)
            statusChip("MISSING \(snapshot.missingRequiredRoles.count)", color: snapshot.missingRequiredRoles.isEmpty ? ConsoleTheme.lampGreen : ConsoleTheme.lampAmber)
            statusChip("CONFLICTS \(snapshot.bindingConflicts.count)", color: snapshot.bindingConflicts.isEmpty ? ConsoleTheme.lampGreen : ConsoleTheme.lampAmber)

            Spacer(minLength: 0)

            Button("Apply X56 Strict Live") {
                model.applyHOTASStrictLiveDefaults()
                model.ensureHOTASTrainingSession()
                refreshSnapshot(force: true)
            }
            .buttonStyle(.bordered)

            Button("Save Draft") {
                model.saveHOTASDraft()
                refreshSnapshot(force: true)
            }
            .buttonStyle(.bordered)

            Button("Clear All") {
                showClearAllConfirmation = true
            }
            .buttonStyle(.bordered)

            Button("Arm Profile") {
                model.saveAndArmHOTASProfile()
                refreshSnapshot(force: true)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canArmProfile)

            Button("Disable HOTAS") {
                model.disableHOTASControls()
                refreshSnapshot(force: true)
            }
            .buttonStyle(.bordered)

            Button("Revert Last Good") {
                model.revertHOTASToLastKnownGood()
                refreshSnapshot(force: true)
            }
            .buttonStyle(.bordered)

            Button("Close") {
                model.finishHOTASTrainingForLiveControl()
                dismissWindow(id: AppWindowID.hotasMapper.rawValue)
            }
            .buttonStyle(.bordered)
        }
    }

    private var functionPanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Picker("Mode", selection: $state.bindingMode) {
                        Text("Function First").tag(HOTASMapperWindowState.BindingMode.functionFirst)
                        Text("Control First").tag(HOTASMapperWindowState.BindingMode.controlFirst)
                    }
                    .pickerStyle(.segmented)
                }

                Picker("Input Source", selection: Binding(
                    get: { snapshot.inputMode },
                    set: {
                        model.updateHOTASInputMode($0)
                        refreshSnapshot(force: true)
                    }
                )) {
                    ForEach(ControlInputMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.uppercased()).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Stick Surface", selection: $stickSurfaceMode) {
                    ForEach(StickSurfaceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(groupedFunctions, id: \.group) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.group.rawValue.uppercased())
                            .font(ConsoleTheme.smallTagFont(size: 9))
                            .tracking(1.0)
                            .foregroundStyle(Color.white.opacity(0.62))

                        ForEach(section.items) { function in
                            functionRow(function)
                        }
                    }
                    .padding(8)
                    .background(ConsoleTheme.panelInnerFill)
                    .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: panelCornerRadius)
                            .stroke(ConsoleTheme.panelStroke, lineWidth: 0.7)
                    )
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func functionRow(_ function: HOTASFunctionDescriptor) -> some View {
        let bindings = snapshot.bindings(for: function.role)
        let isSelected = state.selectedRole == function.role
        let isPendingCapture = snapshot.pendingCaptureRole == function.role
        let isConflict = snapshot.conflictRoles.contains(function.role)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(function.shortLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.84))

                if function.required {
                    Text("REQ")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(ConsoleTheme.lampAmber)
                }

                if isConflict {
                    Text("CONFLICT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(ConsoleTheme.lampAmber)
                }

                Spacer(minLength: 0)

                if isPendingCapture {
                    Text("LISTENING")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(ConsoleTheme.lampGreen)
                }
            }

            Text(function.title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.78))

            Text(function.role.operationalDescription)
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.56))
                .lineLimit(2)

            Text(bindingSummary(bindings: bindings))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.54))
                .lineLimit(2)

            HStack(spacing: 6) {
                Button(state.bindingMode == .functionFirst ? "Bind" : "Select") {
                    state.selectedRole = function.role
                    state.controlFirstRole = function.role
                    if state.bindingMode == .functionFirst {
                        model.captureHOTASBinding(for: function.role)
                        refreshSnapshot(force: true)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    model.clearHOTASBinding(for: function.role)
                    refreshSnapshot(force: true)
                }
                .buttonStyle(.bordered)

                Button("Jump") {
                    if let hotspot = hotspotForRole(function.role) {
                        state.selectedHotspotID = hotspot.id
                    }
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background((isSelected ? ConsoleTheme.lampGreen.opacity(0.13) : Color.white.opacity(0.03)))
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .stroke(isSelected ? ConsoleTheme.lampGreen.opacity(0.75) : ConsoleTheme.panelStroke, lineWidth: 0.7)
        )
    }

    private var mappingCanvas: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("X56 CONTROL SCHEMATIC")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.64))

            HStack(spacing: 10) {
                schematicDevicePanel(title: "LEFT THROTTLE", logicalDevice: .x56Throttle)
                schematicDevicePanel(title: "RIGHT STICK", logicalDevice: .x56Stick)
            }

            unplacedSignalTray
        }
        .padding(10)
        .background(ConsoleTheme.panelInnerFill)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .stroke(ConsoleTheme.panelStroke, lineWidth: 0.8)
        )
    }

    private func schematicDevicePanel(title: String, logicalDevice: HOTASLogicalDevice) -> some View {
        let hotspots = visibleHotspots(for: logicalDevice)
        let indexedHotspots = Array(hotspots.enumerated()).map { (index, hotspot) in
            (index + 1, hotspot)
        }
        return GeometryReader { geo in
            HStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.34))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(ConsoleTheme.panelStroke, lineWidth: 0.8)
                        )

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.0, dash: [6, 6]))
                        .padding(16)

                    ForEach(indexedHotspots, id: \.1.id) { index, hotspot in
                        hotspotBadge(
                            index: index,
                            hotspot: hotspot,
                            in: CGSize(width: max(1, geo.size.width - 162), height: geo.size.height)
                        )
                    }

                    VStack {
                        HStack {
                            Text(title)
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .tracking(1.0)
                                .foregroundStyle(Color.white.opacity(0.78))
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    Text("MAP")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.6))
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(indexedHotspots, id: \.1.id) { index, hotspot in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(index)")
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.95))
                                        .frame(width: 16, height: 16)
                                        .background(colorForHotspotState(hotspotState(hotspot)).opacity(0.35))
                                        .clipShape(Circle())
                                    Text("\(hotspot.title) · \(controlsSummary(for: hotspot.role))")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.72))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding(8)
                .frame(width: 162)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(Color.white.opacity(0.04))
            }
        }
        .frame(minHeight: 390)
    }

    private func hotspotBadge(index: Int, hotspot: HOTASHotspotDescriptor, in size: CGSize) -> some View {
        let point = CGPoint(x: hotspot.x * size.width, y: hotspot.y * size.height)
        let visualState = hotspotState(hotspot)
        let isSelected = state.selectedHotspotID == hotspot.id
        let color = colorForHotspotState(visualState)

        return HStack(spacing: 4) {
            Text("\(index)")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: isSelected ? 18 : 15, height: isSelected ? 18 : 15)
                .background(color)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.95 : 0.4), lineWidth: isSelected ? 1.1 : 0.6)
                )

            Capsule()
                .fill(color.opacity(0.7))
                .frame(width: isSelected ? 18 : 12, height: 1.2)
        }
        .position(point)
        .onTapGesture {
            state.selectedHotspotID = hotspot.id
            if state.bindingMode == .controlFirst {
                state.controlFirstRole = state.selectedRole ?? hotspot.role
            }
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DETAILS")
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.64))

            mapperStatusBox

            if let hotspot = selectedHotspot {
                hotspotDetailCard(hotspot)
            } else {
                Text("Select a hotspot to bind functions and adjust calibration.")
                    .font(ConsoleTheme.telemetryFont(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(8)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
            }

            if let role = selectedCalibrationRole,
               let binding = snapshot.bindings(for: role).first(where: { $0.kind == .axis }) {
                calibrationCard(role: role, binding: binding)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(ConsoleTheme.panelInnerFill)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .stroke(ConsoleTheme.panelStroke, lineWidth: 0.8)
        )
    }

    private var mapperStatusBox: some View {
        return VStack(alignment: .leading, spacing: 4) {
            Text("Input: \(snapshot.inputStatus)")
            Text("Last: \(snapshot.lastSignalSummary)")
            Text("Profile: \(snapshot.profileName)")
            Text("Devices: \(snapshot.deviceCount)")
            if let signal = snapshot.lastSignal {
                let value = String(format: "%.3f", signal.normalizedValue)
                Text("Raw: \(signal.sourceKind.rawValue) · \(signal.sourceDeviceID)")
                Text("Ctrl: \(signal.controlID) · \(signal.kind.rawValue) · \(signal.phase.rawValue) · \(value)")
            }
        }
        .font(ConsoleTheme.telemetryFont(size: 10))
        .foregroundStyle(Color.white.opacity(0.62))
        .padding(8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
    }

    private func hotspotDetailCard(_ hotspot: HOTASHotspotDescriptor) -> some View {
        let roleBindings = snapshot.bindings(for: hotspot.role)

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(hotspot.title.uppercased()) · \(hotspot.role.shortLabel)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.84))

            Text("Kinds: \(supportedKindsSummary(for: hotspot.supportedKinds))")
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.56))

            Text("Bound: \(bindingSummary(bindings: roleBindings))")
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.56))
                .lineLimit(3)

            Text(hotspot.role.operationalDescription)
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(3)

            Picker("Function", selection: $state.controlFirstRole) {
                ForEach(ControlRole.mapperRoles, id: \.self) { role in
                    Text(role.shortLabel).tag(role)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 6) {
                Button("Bind From Live Input") {
                    state.selectedRole = state.controlFirstRole
                    model.captureHOTASBinding(for: state.controlFirstRole)
                    refreshSnapshot(force: true)
                }
                .buttonStyle(.borderedProminent)

                Button("Bind This Role") {
                    state.selectedRole = hotspot.role
                    model.captureHOTASBinding(for: hotspot.role)
                    refreshSnapshot(force: true)
                }
                .buttonStyle(.bordered)
            }

            if roleBindings.isEmpty {
                Text("No functions currently mapped to this control.")
                    .font(ConsoleTheme.telemetryFont(size: 10))
                    .foregroundStyle(Color.white.opacity(0.52))
            } else {
                ForEach(roleBindings, id: \.id) { binding in
                    Text("• \(binding.controlID) · \(binding.kind.rawValue.uppercased())")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
    }

    private func calibrationCard(role: ControlRole, binding: ControlBinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AXIS CALIBRATION · \(role.shortLabel)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.78))

            Toggle("Invert", isOn: Binding(
                get: { binding.calibration.inverted },
                set: { inverted in
                    var calibration = binding.calibration
                    calibration.inverted = inverted
                    model.updateHOTASCalibration(for: role, calibration: calibration)
                    refreshSnapshot(force: true)
                }
            ))
            .toggleStyle(.switch)

            calibrationSlider(
                title: "Deadzone",
                value: Binding(
                    get: { binding.calibration.deadzone },
                    set: { value in
                        var calibration = binding.calibration
                        calibration.deadzone = value
                        model.updateHOTASCalibration(for: role, calibration: calibration)
                        refreshSnapshot(force: true)
                    }
                ),
                range: 0 ... 0.2
            )

            calibrationSlider(
                title: "Hysteresis",
                value: Binding(
                    get: { binding.calibration.hysteresis },
                    set: { value in
                        var calibration = binding.calibration
                        calibration.hysteresis = value
                        model.updateHOTASCalibration(for: role, calibration: calibration)
                        refreshSnapshot(force: true)
                    }
                ),
                range: 0 ... 0.25
            )

            calibrationSlider(
                title: "Center",
                value: Binding(
                    get: { binding.calibration.center },
                    set: { value in
                        var calibration = binding.calibration
                        calibration.center = value
                        model.updateHOTASCalibration(for: role, calibration: calibration)
                        refreshSnapshot(force: true)
                    }
                ),
                range: 0.1 ... 0.9
            )

            if let sweep = state.calibrationSweep, sweep.role == role {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sweep: min \(format(sweep.min))  max \(format(sweep.max))  live \(format(sweep.current))")
                        .font(ConsoleTheme.telemetryFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.64))
                    HStack(spacing: 6) {
                        Button("Apply Sweep") {
                            applySweep(sweep, to: binding)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Cancel") {
                            state.cancelSweep()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Button("Calibrate Sweep") {
                    state.beginSweep(for: role, current: binding.calibration.center)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
    }

    private func calibrationSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title.uppercased())
                    .font(ConsoleTheme.smallTagFont(size: 8))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer(minLength: 0)
                Text(format(value.wrappedValue))
                    .font(ConsoleTheme.telemetryFont(size: 10))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            Slider(value: value, in: range)
        }
    }

    private var unplacedSignalTray: some View {
        let candidates = snapshot.observedSignals.filter { signal in
            !snapshot.profileBindings.contains(where: { binding in
                signalMatches(binding: binding, signal: signal)
            })
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("UNPLACED LIVE SIGNALS")
                .font(ConsoleTheme.smallTagFont(size: 8))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.56))

            if candidates.isEmpty {
                Text("No unmapped controls detected.")
                    .font(ConsoleTheme.telemetryFont(size: 10))
                    .foregroundStyle(Color.white.opacity(0.48))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { _, signal in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(signal.controlID)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.76))
                                Text("\(signal.sourceDeviceID) · \(signal.phase.rawValue)")
                                    .font(ConsoleTheme.telemetryFont(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.46))
                                    .lineLimit(1)
                                if let selected = state.selectedRole {
                                    Button("Bind \(selected.shortLabel)") {
                                        model.assignHOTASBinding(role: selected, from: signal)
                                        refreshSnapshot(force: true)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(6)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var validationRail: some View {
        HStack(spacing: 8) {
            statusChip("Profile \(snapshot.profileName)", color: Color.white.opacity(0.55))
            statusChip("Missing Required \(snapshot.missingRequiredRoles.count)", color: snapshot.missingRequiredRoles.isEmpty ? ConsoleTheme.lampGreen : ConsoleTheme.lampAmber)
            statusChip("Conflicts \(snapshot.bindingConflicts.count)", color: snapshot.bindingConflicts.isEmpty ? ConsoleTheme.lampGreen : ConsoleTheme.lampAmber)
            statusChip(snapshot.lastSignalSummary, color: Color.white.opacity(0.5))
            Spacer(minLength: 0)
        }
    }

    private var selectedHotspot: HOTASHotspotDescriptor? {
        guard let id = state.selectedHotspotID else { return nil }
        return HOTASHotspotDescriptor.byRole[id]
    }

    private var selectedCalibrationRole: ControlRole? {
        if let selected = state.selectedRole,
           snapshot.bindings(for: selected).contains(where: { $0.kind == .axis }) {
            return selected
        }

        if let hotspot = selectedHotspot {
            if snapshot.bindings(for: hotspot.role).contains(where: { $0.kind == .axis }) {
                return hotspot.role
            }
        }

        return nil
    }

    private func visibleHotspots(for logicalDevice: HOTASLogicalDevice) -> [HOTASHotspotDescriptor] {
        HOTASHotspotDescriptor.all.filter { hotspot in
            guard hotspot.logicalDevice == logicalDevice else { return false }
            guard logicalDevice == .x56Stick else { return true }
            switch stickSurfaceMode {
            case .buttons:
                return hotspot.preferredKind != .axis
            case .movement:
                return hotspot.preferredKind == .axis
            case .combined:
                return true
            }
        }
    }

    private func hotspotForRole(_ role: ControlRole) -> HOTASHotspotDescriptor? {
        return HOTASHotspotDescriptor.byRole[role]
    }

    private func hotspotForBinding(_ binding: ControlBinding) -> HOTASHotspotDescriptor? {
        HOTASHotspotDescriptor.byRole[binding.role]
    }

    private func rolesBound(to hotspot: HOTASHotspotDescriptor) -> [ControlRole] {
        let roles = rolesByHotspotID[hotspot.id] ?? []
        return Array(Set(roles)).sorted { $0.rawValue < $1.rawValue }
    }

    private enum VisualHotspotState {
        case unbound
        case bound
        case requiredUnbound
        case conflict
        case active
    }

    private func hotspotState(_ hotspot: HOTASHotspotDescriptor) -> VisualHotspotState {
        let boundRoles = rolesBound(to: hotspot)
        let roleBindings = snapshot.bindings(for: hotspot.role)
        let isActive = snapshot.lastSignal.map { signal in
            isSignalFresh(signal) && roleBindings.contains(where: { signalMatches(binding: $0, signal: signal) })
        } ?? false
        if isActive {
            return .active
        }
        if boundRoles.contains(where: { snapshot.conflictRoles.contains($0) }) {
            return .conflict
        }
        if !boundRoles.isEmpty {
            return .bound
        }
        if hotspot.role.isRequiredByDefault {
            return .requiredUnbound
        }
        return .unbound
    }

    private func colorForHotspotState(_ state: VisualHotspotState) -> Color {
        switch state {
        case .unbound:
            return Color.white.opacity(0.28)
        case .bound:
            return ConsoleTheme.lampBlue
        case .requiredUnbound:
            return ConsoleTheme.lampAmber
        case .conflict:
            return Color.red.opacity(0.9)
        case .active:
            return ConsoleTheme.lampGreen
        }
    }

    private func controlsSummary(for role: ControlRole) -> String {
        let controls = snapshot.bindings(for: role).map(\.controlID)
        guard !controls.isEmpty else { return "UNBOUND" }
        return controls.joined(separator: ", ")
    }

    private func bindingSummary(bindings: [ControlBinding]) -> String {
        guard !bindings.isEmpty else { return "UNBOUND" }
        return bindings
            .map { binding in
                let logical = binding.logicalDevice?.rawValue ?? binding.sourceDeviceID ?? "any-device"
                return "\(binding.controlID) · \(logical)"
            }
            .joined(separator: " | ")
    }

    private func supportedKindsSummary(for kinds: Set<ControlSignalKind>) -> String {
        kinds
            .map(\.rawValue)
            .sorted()
            .joined(separator: "/")
    }

    private func signalMatches(binding: ControlBinding, signal: ControlSignal) -> Bool {
        let signalControlID = HOTASLogicalDeviceMatcher.normalizedControlID(signal.controlID)
        let bindingControlID = HOTASLogicalDeviceMatcher.normalizedControlID(binding.controlID)
        guard signal.controlID == binding.controlID || signalControlID == bindingControlID else { return false }
        if let sourceKind = binding.sourceKind, sourceKind != signal.sourceKind {
            return false
        }
        if let sourceDeviceID = binding.sourceDeviceID, sourceDeviceID != signal.sourceDeviceID {
            return false
        }
        if let logical = binding.logicalDevice,
           logical != .unspecified {
            let signalLogical = HOTASLogicalDeviceMatcher.classify(sourceDeviceID: signal.sourceDeviceID, controlID: signal.controlID)
            return logical == signalLogical
        }
        return true
    }

    private func applySweep(_ sweep: HOTASMapperWindowState.CalibrationSweep, to binding: ControlBinding) {
        var calibration = binding.calibration
        let minValue = min(sweep.min, sweep.max)
        let maxValue = max(sweep.min, sweep.max)
        let span = max(0.001, maxValue - minValue)
        calibration.minimum = max(0, min(1, minValue))
        calibration.maximum = max(0, min(1, maxValue))
        calibration.center = max(0, min(1, minValue + (span / 2)))
        model.updateHOTASCalibration(for: sweep.role, calibration: calibration)
        refreshSnapshot(force: true)
        state.cancelSweep()
    }

    private func isSignalFresh(_ signal: ControlSignal) -> Bool {
        let nowMs = Date().timeIntervalSince1970 * 1_000
        let signalMs: TimeInterval = signal.timestamp > 1_000_000_000_000
            ? signal.timestamp
            : signal.timestamp * 1_000
        return (nowMs - signalMs) < 550
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func statusChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: panelCornerRadius)
                    .stroke(color.opacity(0.45), lineWidth: 0.8)
            )
    }

    private func refreshSnapshot(force: Bool = false) {
        let nowMs = Date().timeIntervalSince1970 * 1_000
        let hasInteractiveCapture = snapshot.pendingCaptureRole != nil || state.calibrationSweep != nil
        let minIntervalMs: TimeInterval = hasInteractiveCapture ? 220 : 1_000
        if !force, (nowMs - lastSnapshotRefreshMs) < minIntervalMs {
            return
        }
        lastSnapshotRefreshMs = nowMs

        let profileBindings = model.hotasProfileBindings
        let bindingsByRole = Dictionary(grouping: profileBindings, by: \.role)
        let observedSignals = hasInteractiveCapture ? Array(model.hotasObservedSignals.prefix(12)) : []

        var deviceCount = snapshot.deviceCount
        if force {
            deviceCount = model.availableHOTASDevices().count
        }

        let next = HOTASMapperRenderSnapshot(
            trainingActive: model.hotasTrainingActive,
            missingRequiredRoles: model.hotasMissingRequiredRoles,
            bindingConflicts: model.hotasBindingConflicts,
            conflictRoles: model.hotasConflictRoles,
            profileName: model.hotasProfileName,
            inputMode: model.hotasInputMode,
            pendingCaptureRole: model.hotasPendingCaptureRole,
            inputStatus: model.hotasInputStatus,
            lastSignalSummary: model.hotasLastSignalSummary,
            lastSignal: model.hotasLastSignal,
            observedSignals: observedSignals,
            profileBindings: profileBindings,
            bindingsByRole: bindingsByRole,
            deviceCount: deviceCount
        )
        if next != snapshot {
            snapshot = next
        }
    }
}

private struct HOTASMapperRenderSnapshot: Equatable {
    var trainingActive: Bool
    var missingRequiredRoles: [ControlRole]
    var bindingConflicts: [String]
    var conflictRoles: Set<ControlRole>
    var profileName: String
    var inputMode: ControlInputMode
    var pendingCaptureRole: ControlRole?
    var inputStatus: String
    var lastSignalSummary: String
    var lastSignal: ControlSignal?
    var observedSignals: [ControlSignal]
    var profileBindings: [ControlBinding]
    var bindingsByRole: [ControlRole: [ControlBinding]]
    var deviceCount: Int

    static let empty = HOTASMapperRenderSnapshot(
        trainingActive: false,
        missingRequiredRoles: [],
        bindingConflicts: [],
        conflictRoles: [],
        profileName: "HOTAS",
        inputMode: .hybrid,
        pendingCaptureRole: nil,
        inputStatus: "HOTAS OFF",
        lastSignalSummary: "No HOTAS signal",
        lastSignal: nil,
        observedSignals: [],
        profileBindings: [],
        bindingsByRole: [:],
        deviceCount: 0
    )

    func bindings(for role: ControlRole) -> [ControlBinding] {
        bindingsByRole[role] ?? []
    }
}

private struct HOTASSchematicBackdrop: View {
    let logicalDevice: HOTASLogicalDevice

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if logicalDevice == .x56Throttle {
                    throttleBackdrop(width: w, height: h)
                } else {
                    stickBackdrop(width: w, height: h)
                }
            }
        }
    }

    @ViewBuilder
    private func throttleBackdrop(width: CGFloat, height: CGFloat) -> some View {
        let plate = RoundedRectangle(cornerRadius: 14)
        plate
            .stroke(Color.white.opacity(0.22), lineWidth: 1.0)
            .frame(width: width * 0.78, height: height * 0.84)

        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.07))
            .frame(width: width * 0.32, height: height * 0.24)
            .offset(x: -width * 0.1, y: -height * 0.18)

        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.07))
            .frame(width: width * 0.32, height: height * 0.24)
            .offset(x: width * 0.1, y: -height * 0.18)

        HStack(spacing: width * 0.045) {
            ForEach(0 ..< 6, id: \.self) { _ in
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: width * 0.035, height: height * 0.12)
            }
        }
        .offset(y: height * 0.28)

        VStack(spacing: height * 0.04) {
            Circle().stroke(Color.white.opacity(0.24), lineWidth: 1.1)
            Circle().stroke(Color.white.opacity(0.24), lineWidth: 1.1)
            Circle().stroke(Color.white.opacity(0.24), lineWidth: 1.1)
        }
        .frame(width: width * 0.12)
        .offset(x: width * 0.28, y: -height * 0.08)
    }

    @ViewBuilder
    private func stickBackdrop(width: CGFloat, height: CGFloat) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.24), lineWidth: 1.0)
            .frame(width: width * 0.56, height: width * 0.56)
            .offset(y: height * 0.18)

        Capsule(style: .continuous)
            .stroke(Color.white.opacity(0.24), lineWidth: 1.0)
            .frame(width: width * 0.22, height: height * 0.48)
            .offset(y: -height * 0.08)

        Circle()
            .stroke(Color.white.opacity(0.24), lineWidth: 1.0)
            .frame(width: width * 0.1, height: width * 0.1)
            .offset(x: width * 0.16, y: -height * 0.06)

        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.2), lineWidth: 1.0)
            .frame(width: width * 0.12, height: height * 0.22)
            .offset(x: width * 0.24, y: -height * 0.24)
    }
}
