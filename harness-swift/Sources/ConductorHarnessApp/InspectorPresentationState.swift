import Foundation

enum InspectorPresentationSource: String, CaseIterable, Identifiable, Sendable {
    case fullConsole
    case vufine
    case safety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullConsole:
            return "Full Console"
        case .vufine:
            return "Vufine Realtime"
        case .safety:
            return "Safety Monitor"
        }
    }
}

enum InspectorModalTab: String, CaseIterable, Identifiable, Sendable {
    case link
    case media
    case coreML
    case controls
    case hudDebug
    case actionStream

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link:
            return "Link"
        case .media:
            return "Media"
        case .coreML:
            return "CoreML"
        case .controls:
            return "Controls"
        case .hudDebug:
            return "HUD Debug"
        case .actionStream:
            return "Action Stream"
        }
    }
}

@MainActor
final class InspectorPresentationState: ObservableObject {
    @Published private(set) var source: InspectorPresentationSource = .safety
    @Published var isPresented = false
    @Published var selectedTab: InspectorModalTab = .actionStream
    @Published private(set) var lastActiveSource: InspectorPresentationSource = .safety

    func markActive(_ source: InspectorPresentationSource) {
        lastActiveSource = source
    }

    func present(from source: InspectorPresentationSource) {
        self.source = source
        lastActiveSource = source
        isPresented = true
    }

    func presentFromLastActiveSource() {
        present(from: lastActiveSource)
    }

    func dismiss() {
        isPresented = false
    }
}
