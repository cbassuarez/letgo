import ConductorCore
import SwiftUI

/// Auto-scrolling teletype-style monospace log of `StatusLineEvent`s.
/// Newest entry sits at the bottom (the way a real teletype rolls).
struct FlightLogTape: View {
    let entries: [StatusLineEvent]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if entries.isEmpty {
                        Text("// flight log standing by")
                            .font(ConsoleTheme.telemetryFont(size: 10))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(entries.enumerated()), id: \.offset) { pair in
                            row(index: pair.offset, event: pair.element)
                                .id(pair.offset)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: entries.count) { _, _ in
                guard !entries.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(entries.count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func row(index: Int, event: StatusLineEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 70, alignment: .leading)

            Text(severityTag(event.severity))
                .font(ConsoleTheme.smallTagFont(size: 9))
                .tracking(0.8)
                .foregroundStyle(severityColor(event.severity))
                .frame(width: 36, alignment: .leading)

            Text(event.message)
                .font(ConsoleTheme.telemetryFont(size: 10))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }

    private func severityTag(_ severity: StatusLineSeverity) -> String {
        switch severity {
        case .info: return "INFO"
        case .success: return "OK"
        case .warn: return "WARN"
        case .error: return "FAIL"
        }
    }

    private func severityColor(_ severity: StatusLineSeverity) -> Color {
        switch severity {
        case .info: return ConsoleTheme.lampBlue
        case .success: return ConsoleTheme.lampGreen
        case .warn: return ConsoleTheme.lampAmber
        case .error: return ConsoleTheme.lampRed
        }
    }
}
