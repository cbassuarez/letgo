import Foundation

public struct HarnessOutboundEnvelope<T: Codable>: Codable {
    public let kind: String
    public let data: T

    public init(kind: String, data: T) {
        self.kind = kind
        self.data = data
    }
}

public final class WebSocketConductorClient: NSObject {
    public enum LinkState: String, Codable {
        case idle
        case connecting
        case online
        case degraded
        case offline
        case backoff
    }

    public struct LinkDiagnostics: Equatable {
        public let endpointURL: URL?
        public let state: LinkState
        public let retryInSeconds: Int?
        public let lastError: String?
        public let lastHandshakeAt: Date?
    }

    public var onMessage: ((String) -> Void)?
    public var onOpen: (() -> Void)?
    public var onClose: ((Int, String?) -> Void)?
    public var onStateChange: ((LinkState) -> Void)?
    public var onRetryScheduled: ((TimeInterval) -> Void)?
    public var onError: ((String) -> Void)?
    public var onDiagnostics: ((LinkDiagnostics) -> Void)?

    public private(set) var state: LinkState = .idle

    private static let forwardedMessageKinds: [String] = [
        "\"kind\":\"error\"",
        "\"kind\":\"phone_audio_pool_state\"",
        "\"kind\":\"phone_audio_ack\"",
        "\"kind\":\"voice_stream_start\"",
        "\"kind\":\"voice_stream_stop\"",
        "\"kind\":\"group_stem_start\"",
        "\"kind\":\"group_stem_stop\"",
        "\"kind\":\"keyboard_state\"",
        "\"kind\":\"keyboard_patch_change\"",
        "\"kind\":\"show_snapshot\"",
        "\"kind\":\"audio_features\"",
        "\"kind\":\"push_deck_event\"",
        "\"kind\":\"procedural_state\""
    ]

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var managedURL: URL?
    private var reconnectWorkItem: DispatchWorkItem?
    private var heartbeatTimer: Timer?
    private var supervisionTimer: Timer?
    private var backoffUntil: Date?
    private var reconnectAttempt = 0
    private var intentionallyStopped = true
    private var lastActivityAt: Date?
    private var lastHandshakeAt: Date?
    private var lastErrorMessage: String?
    private var lastEmittedDiagnostics: LinkDiagnostics?

    public override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    deinit {
        stop()
        session.invalidateAndCancel()
    }

    public static func retryDelaySeconds(attempt: Int, jitterSource: Double) -> TimeInterval {
        let normalizedAttempt = max(1, attempt)
        let unclampedBase = pow(2.0, Double(normalizedAttempt - 1))
        let base = min(30.0, unclampedBase)
        let normalizedJitter = min(1.0, max(0.0, jitterSource))
        let signedJitter = (normalizedJitter - 0.5) * 0.5 // -0.25...+0.25
        let jittered = base * (1 + signedJitter)
        return min(30.0, max(1.0, jittered))
    }

    public static func stateForSilence(elapsedSeconds: TimeInterval) -> LinkState {
        if elapsedSeconds > 30 {
            return .offline
        }
        if elapsedSeconds > 20 {
            return .degraded
        }
        return .online
    }

    public func start(url: URL) {
        managedURL = url
        intentionallyStopped = false
        reconnectAttempt = 0
        backoffUntil = nil
        lastErrorMessage = nil
        lastHandshakeAt = nil
        lastActivityAt = nil
        lastEmittedDiagnostics = nil
        startSupervisionTimer()
        connectNow()
    }

    public func stop() {
        intentionallyStopped = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        backoffUntil = nil
        lastEmittedDiagnostics = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        supervisionTimer?.invalidate()
        supervisionTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        transition(to: .idle)
        emitDiagnostics()
    }

    public func connect(url: URL) {
        start(url: url)
    }

    public func disconnect() {
        stop()
    }

    public func sendCue(_ cue: CueCommand) async throws {
        let data = try JSONEncoder().encode(HarnessOutboundEnvelope(kind: "cue", data: cue))
        try await send(data)
    }

    public func sendCommand(
        _ action: CueAction,
        targetState: ShowState? = nil,
        payload: [String: String]? = nil
    ) async throws {
        struct CommandData: Codable {
            let action: String
            let targetState: String?
            let payload: [String: String]?
        }

        let command = CommandData(
            action: action.rawValue,
            targetState: targetState?.rawValue,
            payload: payload
        )
        let data = try JSONEncoder().encode(HarnessOutboundEnvelope(kind: "command", data: command))
        try await send(data)
    }

    public func sendVector(_ vector: ParamVector) async throws {
        let data = try JSONEncoder().encode(HarnessOutboundEnvelope(kind: "param_vector", data: vector))
        try await send(data)
    }

    public func sendEnvelope<T: Codable>(kind: String, data payload: T) async throws {
        let data = try JSONEncoder().encode(HarnessOutboundEnvelope(kind: kind, data: payload))
        try await send(data)
    }

    private func connectNow() {
        guard !intentionallyStopped, let managedURL else {
            return
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        transition(to: .connecting)
        emitDiagnostics()

        task?.cancel(with: .goingAway, reason: nil)
        let nextTask = session.webSocketTask(with: managedURL)
        task = nextTask
        nextTask.resume()
        receiveLoop(for: nextTask)
    }

    private func send(_ data: Data) async throws {
        guard state == .online || state == .degraded else {
            throw URLError(.notConnectedToInternet)
        }
        guard let task else {
            throw URLError(.networkConnectionLost)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeRawData)
        }
        try await task.send(.string(text))
    }

    private func receiveLoop(for receivingTask: URLSessionWebSocketTask) {
        receivingTask.receive { [weak self, weak receivingTask] result in
            guard let self else { return }
            guard let receivingTask, self.task === receivingTask else { return }

            switch result {
            case .success(let message):
                self.noteActivity()
                switch message {
                case .string(let text):
                    if Self.shouldForwardMessage(text) {
                        self.onMessage?(text)
                    }
                case .data(let data):
                    let text = String(decoding: data, as: UTF8.self)
                    if Self.shouldForwardMessage(text) {
                        self.onMessage?(text)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop(for: receivingTask)
            case .failure(let error):
                self.handleSocketFailure(reason: "Receive failed: \(error.localizedDescription)")
            }
        }
    }

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self, !self.intentionallyStopped else { return }
            guard let task = self.task else { return }
            task.sendPing { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard !self.intentionallyStopped else { return }
                    if let error {
                        self.handleSocketFailure(reason: "Heartbeat ping failed: \(error.localizedDescription)")
                        return
                    }
                    self.noteActivity()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func startSupervisionTimer() {
        supervisionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.state == .backoff {
                self.emitDiagnostics()
                return
            }

            guard (self.state == .online || self.state == .degraded),
                  let lastActivityAt = self.lastActivityAt else {
                return
            }

            let elapsed = Date().timeIntervalSince(lastActivityAt)
            let expectedState = Self.stateForSilence(elapsedSeconds: elapsed)

            if expectedState == .degraded, self.state == .online {
                self.transition(to: .degraded)
                self.emitDiagnostics()
                return
            }

            if expectedState == .offline {
                self.handleSocketFailure(reason: "Heartbeat timeout: no activity for \(Int(elapsed))s")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        supervisionTimer = timer
    }

    private func noteActivity() {
        lastActivityAt = Date()
        if state == .degraded {
            transition(to: .online)
        }
        emitDiagnostics()
    }

    private func scheduleReconnect() {
        guard !intentionallyStopped else { return }

        reconnectAttempt += 1
        let delay = Self.retryDelaySeconds(
            attempt: reconnectAttempt,
            jitterSource: Double.random(in: 0 ... 1)
        )
        backoffUntil = Date().addingTimeInterval(delay)
        transition(to: .backoff)
        onRetryScheduled?(delay)
        emitDiagnostics()

        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.intentionallyStopped else { return }
            self.backoffUntil = nil
            self.connectNow()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func handleSocketFailure(reason: String) {
        guard !intentionallyStopped else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        lastErrorMessage = reason
        transition(to: .offline)
        onError?(reason)
        emitDiagnostics()
        scheduleReconnect()
    }

    private func transition(to nextState: LinkState) {
        guard state != nextState else { return }
        state = nextState
        onStateChange?(nextState)
    }

    private func emitDiagnostics() {
        let retryIn: Int?
        if let backoffUntil {
            retryIn = max(0, Int(ceil(backoffUntil.timeIntervalSinceNow)))
        } else {
            retryIn = nil
        }

        let diagnostics = LinkDiagnostics(
            endpointURL: managedURL,
            state: state,
            retryInSeconds: retryIn,
            lastError: lastErrorMessage,
            lastHandshakeAt: lastHandshakeAt
        )
        guard diagnostics != lastEmittedDiagnostics else {
            return
        }
        lastEmittedDiagnostics = diagnostics
        onDiagnostics?(diagnostics)
    }

    private static func shouldForwardMessage(_ message: String) -> Bool {
        forwardedMessageKinds.contains(where: { message.contains($0) })
    }
}

extension WebSocketConductorClient: URLSessionWebSocketDelegate {
    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard task === webSocketTask else { return }
        reconnectAttempt = 0
        backoffUntil = nil
        lastErrorMessage = nil
        lastHandshakeAt = Date()
        lastActivityAt = lastHandshakeAt
        transition(to: .online)
        startHeartbeatTimer()
        emitDiagnostics()
        onOpen?()
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard task === webSocketTask else { return }
        task = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        let reasonText: String?
        if let reason, !reason.isEmpty {
            reasonText = String(data: reason, encoding: .utf8)
        } else {
            reasonText = nil
        }
        onClose?(Int(closeCode.rawValue), reasonText)

        guard !intentionallyStopped else {
            transition(to: .idle)
            emitDiagnostics()
            return
        }

        let detail: String
        if let reasonText {
            detail = "Socket closed (\(closeCode.rawValue)): \(reasonText)"
        } else {
            detail = "Socket closed (\(closeCode.rawValue))"
        }
        handleSocketFailure(reason: detail)
    }
}
