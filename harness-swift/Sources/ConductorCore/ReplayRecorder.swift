import Foundation

public actor ReplayRecorder {
    private var events: [ReplayEvent] = []

    public init() {}

    public func append(_ event: ReplayEvent) {
        events.append(event)
    }

    public func latest(limit: Int = 200) -> [ReplayEvent] {
        let start = max(0, events.count - limit)
        return Array(events[start...])
    }

    public func freezeFrame(center: Date, before: TimeInterval = 5, after: TimeInterval = 5) -> [ReplayEvent] {
        events.filter {
            $0.timestamp >= center.addingTimeInterval(-before) &&
            $0.timestamp <= center.addingTimeInterval(after)
        }
    }
}
