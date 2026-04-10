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
    public enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    public var onMessage: ((String) -> Void)?
    public private(set) var state: ConnectionState = .disconnected

    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public override init() {
        session = URLSession(configuration: .default)
        super.init()
    }

    public func connect(url: URL) {
        state = .connecting
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        state = .connected
        receiveLoop()
    }

    public func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
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

    private func send(_ data: Data) async throws {
        guard let task else { return }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeRawData)
        }
        try await task.send(.string(text))
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.onMessage?(text)
                case .data(let data):
                    self.onMessage?(String(decoding: data, as: UTF8.self))
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure:
                self.state = .disconnected
            }
        }
    }
}
