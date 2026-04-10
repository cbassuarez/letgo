import Foundation

public final class ShowStateMachine {
    public enum TransitionError: Error {
        case invalidTransition(ShowState, ShowState)
        case missingTargetState
    }

    public private(set) var state: ShowState = .idle
    public private(set) var vector: ParamVector = .neutral

    private var startedAt: Date?
    private var pausedAt: Date?
    private var pauseOffset: TimeInterval = 0

    private let transitions: [ShowState: Set<ShowState>] = [
        .idle: [.preshow, .introduction, .main, .ending],
        .preshow: [.idle, .introduction, .main, .ending, .hold, .aborted],
        .introduction: [.idle, .preshow, .main, .ending, .hold, .aborted],
        .main: [.idle, .preshow, .introduction, .ending, .hold, .aborted],
        .ending: [.idle, .preshow, .introduction, .main, .hold, .aborted],
        .hold: [.idle, .preshow, .introduction, .main, .ending, .recovery, .aborted],
        .aborted: [.recovery, .idle],
        .recovery: [.idle, .preshow, .introduction, .main, .ending, .hold, .aborted]
    ]

    public init() {}

    public func canTransition(to next: ShowState) -> Bool {
        if next == state {
            return true
        }
        return transitions[state, default: []].contains(next)
    }

    public func canApply(action: CueAction, targetState: ShowState? = nil) -> Bool {
        let next: ShowState
        switch action {
        case .start:
            next = targetState ?? .preshow
        case .hold:
            next = .hold
        case .jump:
            guard let targetState else { return false }
            next = targetState
        case .abort:
            next = .aborted
        case .recover:
            next = targetState ?? .recovery
        }
        return canTransition(to: next)
    }

    public func apply(
        action: CueAction,
        at now: Date = Date(),
        targetState: ShowState? = nil,
        payload: [String: String] = [:]
    ) throws -> CueCommand {
        let next: ShowState

        switch action {
        case .start:
            next = targetState ?? .preshow
        case .hold:
            next = .hold
        case .jump:
            guard let targetState else { throw TransitionError.missingTargetState }
            next = targetState
        case .abort:
            next = .aborted
        case .recover:
            next = targetState ?? .recovery
        }

        try transition(to: next, at: now)

        let logical = logicalTime(at: now)
        let cueId = "\(next.rawValue):\(Int(logical * 1000))"

        var enriched = payload
        enriched["textAmount"] = String(vector.textAmount)
        enriched["compositeBias"] = String(vector.compositeBias)
        enriched["audioGain"] = String(vector.audioGain)

        if next == .main {
            enriched["showFixed"] = "true"
            enriched["showDynamic"] = "true"
        }

        return CueCommand(
            cueId: cueId,
            showState: next,
            logicalTime: logical,
            payload: enriched,
            version: 1,
            action: action
        )
    }

    public func updateVector(with patch: ParamVectorPatch) -> ParamVector {
        vector = vector.merged(patch)
        return vector
    }

    public func logicalTime(at now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        let pausedDelta = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - pauseOffset - pausedDelta)
    }

    private func transition(to next: ShowState, at now: Date) throws {
        if next == state {
            // Treat same-state actions as idempotent no-ops for live safety.
            return
        }

        guard transitions[state, default: []].contains(next) else {
            throw TransitionError.invalidTransition(state, next)
        }

        if next == .preshow && startedAt == nil {
            startedAt = now
            pausedAt = nil
            pauseOffset = 0
        }

        if state == .hold, let pausedAt, next != .hold {
            pauseOffset += now.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }

        if next == .hold, state != .hold {
            pausedAt = now
        }

        if next == .idle {
            startedAt = nil
            pausedAt = nil
            pauseOffset = 0
        }

        state = next
    }
}
