import Foundation

public protocol CueTransport {
    func sendCommand(
        action: CueAction,
        targetState: ShowState?,
        payload: [String: String]
    ) async throws
    func sendVector(_ vector: ParamVector) async throws
}

public actor TimelineTransport {
    private let machine: ShowStateMachine
    private let transport: CueTransport

    public init(machine: ShowStateMachine, transport: CueTransport) {
        self.machine = machine
        self.transport = transport
    }

    @discardableResult
    public func apply(
        action: CueAction,
        targetState: ShowState? = nil,
        payload: [String: String] = [:],
        now: Date = Date()
    ) async throws -> CueCommand {
        let cue = try machine.apply(action: action, at: now, targetState: targetState, payload: payload)
        var commandPayload = cue.payload
        commandPayload["localCueId"] = cue.cueId
        commandPayload["localLogicalMs"] = String(Int(cue.logicalTime * 1000))
        try await transport.sendCommand(
            action: action,
            targetState: targetState ?? cue.showState,
            payload: commandPayload
        )
        return cue
    }

    public func updateVector(_ patch: ParamVectorPatch) async throws {
        let vector = machine.updateVector(with: patch)
        try await transport.sendVector(vector)
    }

    public func logicalTime(now: Date = Date()) -> TimeInterval {
        machine.logicalTime(at: now)
    }
}
