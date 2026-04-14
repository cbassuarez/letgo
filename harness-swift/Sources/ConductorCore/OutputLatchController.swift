import Foundation

public enum StatusLineSeverity: String, Codable, Sendable {
    case info
    case success
    case warn
    case error
}

public struct StatusLineEvent: Equatable, Sendable {
    public let message: String
    public let severity: StatusLineSeverity
    public let timestamp: Date
    public let expiresAt: Date?

    public init(
        message: String,
        severity: StatusLineSeverity,
        timestamp: Date,
        expiresAt: Date? = nil
    ) {
        self.message = message
        self.severity = severity
        self.timestamp = timestamp
        self.expiresAt = expiresAt
    }
}

public struct OutputLatchSnapshot: Equatable, Sendable {
    public let pendingMode: String?
    public let pendingLaneId: String?
    public let latchId: String?
    public let armedAt: Date?
    public let expiresAt: Date?
    public let status: StatusLineEvent

    public init(
        pendingMode: String?,
        pendingLaneId: String?,
        latchId: String?,
        armedAt: Date?,
        expiresAt: Date?,
        status: StatusLineEvent
    ) {
        self.pendingMode = pendingMode
        self.pendingLaneId = pendingLaneId
        self.latchId = latchId
        self.armedAt = armedAt
        self.expiresAt = expiresAt
        self.status = status
    }

    public var isArmed: Bool {
        pendingMode != nil && expiresAt != nil
    }

    public var canFire: Bool {
        guard let pendingMode else { return false }
        if pendingMode == "static" {
            return pendingLaneId != nil
        }
        return true
    }

    public func countdownSeconds(at now: Date = Date()) -> TimeInterval? {
        guard let expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSince(now))
    }

    public var summary: String {
        guard let pendingMode else {
            return "DISARMED"
        }
        if pendingMode == "static", let pendingLaneId {
            return "ARMED: STATIC + \(pendingLaneId)"
        }
        return "ARMED: \(pendingMode.uppercased())"
    }
}

public struct OutputLatchFireDecision: Equatable, Sendable {
    public let mode: String
    public let laneId: String?
    public let latchId: String

    public init(mode: String, laneId: String?, latchId: String) {
        self.mode = mode
        self.laneId = laneId
        self.latchId = latchId
    }
}

public struct OutputLatchController: Sendable {
    public let timeoutSeconds: TimeInterval
    public private(set) var snapshot: OutputLatchSnapshot

    public init(timeoutSeconds: TimeInterval = 8, now: Date = Date()) {
        self.timeoutSeconds = timeoutSeconds
        self.snapshot = OutputLatchSnapshot(
            pendingMode: nil,
            pendingLaneId: nil,
            latchId: nil,
            armedAt: nil,
            expiresAt: nil,
            status: StatusLineEvent(
                message: "Latch disarmed",
                severity: .info,
                timestamp: now
            )
        )
    }

    @discardableResult
    public mutating func armMode(_ mode: String, now: Date = Date()) -> OutputLatchSnapshot {
        let lane: String?
        if mode == "static" {
            lane = snapshot.pendingLaneId
        } else {
            lane = nil
        }

        snapshot = OutputLatchSnapshot(
            pendingMode: mode,
            pendingLaneId: lane,
            latchId: UUID().uuidString,
            armedAt: now,
            expiresAt: now.addingTimeInterval(timeoutSeconds),
            status: StatusLineEvent(
                message: "Armed \(mode.uppercased())",
                severity: .info,
                timestamp: now
            )
        )
        return snapshot
    }

    @discardableResult
    public mutating func armLane(_ laneId: String, now: Date = Date()) -> OutputLatchSnapshot {
        guard snapshot.pendingMode == "static" else {
            snapshot = OutputLatchSnapshot(
                pendingMode: snapshot.pendingMode,
                pendingLaneId: snapshot.pendingLaneId,
                latchId: snapshot.latchId,
                armedAt: snapshot.armedAt,
                expiresAt: snapshot.expiresAt,
                status: StatusLineEvent(
                    message: "Blocked: lane requires STATIC armed",
                    severity: .error,
                    timestamp: now
                )
            )
            return snapshot
        }

        snapshot = OutputLatchSnapshot(
            pendingMode: snapshot.pendingMode,
            pendingLaneId: laneId,
            latchId: snapshot.latchId ?? UUID().uuidString,
            armedAt: snapshot.armedAt ?? now,
            expiresAt: now.addingTimeInterval(timeoutSeconds),
            status: StatusLineEvent(
                message: "Lane \(laneId) selected",
                severity: .info,
                timestamp: now
            )
        )
        return snapshot
    }

    public mutating func fire(now: Date = Date()) -> OutputLatchFireDecision? {
        guard let pendingMode = snapshot.pendingMode else {
            snapshot = OutputLatchSnapshot(
                pendingMode: snapshot.pendingMode,
                pendingLaneId: snapshot.pendingLaneId,
                latchId: snapshot.latchId,
                armedAt: snapshot.armedAt,
                expiresAt: snapshot.expiresAt,
                status: StatusLineEvent(
                    message: "Blocked: mode arm required",
                    severity: .error,
                    timestamp: now
                )
            )
            return nil
        }

        if let expiresAt = snapshot.expiresAt, now >= expiresAt {
            snapshot = OutputLatchSnapshot(
                pendingMode: nil,
                pendingLaneId: nil,
                latchId: nil,
                armedAt: nil,
                expiresAt: nil,
                status: StatusLineEvent(
                    message: "Arm timeout",
                    severity: .warn,
                    timestamp: now
                )
            )
            return nil
        }

        if pendingMode == "static", snapshot.pendingLaneId == nil {
            snapshot = OutputLatchSnapshot(
                pendingMode: snapshot.pendingMode,
                pendingLaneId: snapshot.pendingLaneId,
                latchId: snapshot.latchId,
                armedAt: snapshot.armedAt,
                expiresAt: snapshot.expiresAt,
                status: StatusLineEvent(
                    message: "Blocked: lane arm required",
                    severity: .error,
                    timestamp: now
                )
            )
            return nil
        }

        let latchId = snapshot.latchId ?? UUID().uuidString
        let decision = OutputLatchFireDecision(
            mode: pendingMode,
            laneId: snapshot.pendingLaneId,
            latchId: latchId
        )

        snapshot = OutputLatchSnapshot(
            pendingMode: nil,
            pendingLaneId: nil,
            latchId: nil,
            armedAt: nil,
            expiresAt: nil,
            status: StatusLineEvent(
                message: "GO fired: \(pendingMode.uppercased())",
                severity: .success,
                timestamp: now
            )
        )

        return decision
    }

    @discardableResult
    public mutating func tick(now: Date = Date()) -> OutputLatchSnapshot {
        guard snapshot.isArmed, let expiresAt = snapshot.expiresAt else {
            return snapshot
        }

        if now < expiresAt {
            return snapshot
        }

        snapshot = OutputLatchSnapshot(
            pendingMode: nil,
            pendingLaneId: nil,
            latchId: nil,
            armedAt: nil,
            expiresAt: nil,
            status: StatusLineEvent(
                message: "Arm timeout",
                severity: .warn,
                timestamp: now
            )
        )

        return snapshot
    }

    @discardableResult
    public mutating func reset(now: Date = Date(), message: String = "Latch disarmed") -> OutputLatchSnapshot {
        snapshot = OutputLatchSnapshot(
            pendingMode: nil,
            pendingLaneId: nil,
            latchId: nil,
            armedAt: nil,
            expiresAt: nil,
            status: StatusLineEvent(
                message: message,
                severity: .info,
                timestamp: now
            )
        )
        return snapshot
    }
}
