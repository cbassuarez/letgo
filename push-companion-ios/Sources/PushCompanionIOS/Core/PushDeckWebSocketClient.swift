import Foundation

@MainActor
final class PushDeckWebSocketClient: ObservableObject {
    enum LinkState: String {
        case idle
        case connecting
        case online
        case offline
    }

    @Published private(set) var linkState: LinkState = .idle
    @Published private(set) var statusLine: String = "Disconnected"

    private var session: URLSession = .shared
    private var task: URLSessionWebSocketTask?
    private var targetURL: URL?

    var onEnvelope: ((String) -> Void)?

    func connect(url: URL) {
        disconnect()
        targetURL = url
        linkState = .connecting
        statusLine = "Connecting to \(url.host() ?? "backend")…"
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        linkState = .online
        statusLine = "Connected"
        receiveLoop(task: task)
        sendPermissionsEnvelope()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if targetURL != nil {
            linkState = .offline
            statusLine = "Disconnected"
        } else {
            linkState = .idle
            statusLine = "Disconnected"
        }
    }

    func reconnect() {
        guard let targetURL else { return }
        connect(url: targetURL)
    }

    func sendPushEvent(_ payload: PushDeckEventPayload) {
        guard let task else { return }
        let envelope = PushWireEnvelope(kind: "push_deck_event", data: payload, sentAt: Date().timeIntervalSince1970 * 1000)
        do {
            let encoded = try JSONEncoder().encode(envelope)
            guard let text = String(data: encoded, encoding: .utf8) else { return }
            task.send(.string(text)) { [weak self] error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.linkState = .offline
                        self.statusLine = "Send failed: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            statusLine = "Encode failed: \(error.localizedDescription)"
        }
    }

    private func sendPermissionsEnvelope() {
        struct PermissionsPayload: Codable {
            let audio: Bool
            let geolocation: Bool
            let motion: Bool
        }
        guard let task else { return }
        let envelope = PushWireEnvelope(
            kind: "permissions",
            data: PermissionsPayload(audio: true, geolocation: true, motion: true),
            sentAt: Date().timeIntervalSince1970 * 1000
        )
        guard let data = try? JSONEncoder().encode(envelope),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        task.send(.string(text)) { _ in }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            guard task == self.task else { return }
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self.linkState = .online
                }
                switch message {
                case .string(let text):
                    Task { @MainActor in
                        self.onEnvelope?(text)
                    }
                case .data(let data):
                    Task { @MainActor in
                        self.onEnvelope?(String(decoding: data, as: UTF8.self))
                    }
                @unknown default:
                    break
                }
                receiveLoop(task: task)
            case .failure(let error):
                Task { @MainActor in
                    self.linkState = .offline
                    self.statusLine = "Socket error: \(error.localizedDescription)"
                }
            }
        }
    }
}
