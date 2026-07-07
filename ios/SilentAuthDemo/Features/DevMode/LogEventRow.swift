import SwiftUI

struct LogEventRow: View {
    let event: LogEvent

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timeString: String {
        if let date = Self.isoFormatter.date(from: event.timestamp) {
            return Self.timeFormatter.string(from: date)
        }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: event.timestamp) {
            return Self.timeFormatter.string(from: date)
        }
        return event.timestamp
    }

    private var sourceColor: Color {
        event.source == "server" ? VonageBrand.plum : VonageBrand.purple
    }

    private var accentColor: Color {
        StageStyle.accent(for: event.stage)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Stage accent bar on the leading edge
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                // Row header: time + source dot
                HStack(spacing: 6) {
                    Circle()
                        .fill(sourceColor)
                        .frame(width: 7, height: 7)
                    Text(event.source)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(sourceColor)
                    Text(timeString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(VonageBrand.gray4)
                }

                // Note first — the plain-English story is the primary text
                if let note = event.note {
                    Text(note)
                        .font(.callout)
                        .foregroundColor(VonageBrand.plum)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Machine label, quieted down
                Text(event.label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(VonageBrand.gray4)

                // Detail key-values
                if !event.detail.isEmpty {
                    ForEach(event.detail.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        Text("\(key): \(value.stringValue)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(VonageBrand.gray3)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
    }
}

/// Maps a stage to its brand accent color — the timeline's visual language.
enum StageStyle {
    static func accent(for stage: LogStage) -> Color {
        switch stage {
        case .request: return VonageBrand.gray4
        case .silentAuth: return VonageBrand.purple
        case .sms: return VonageBrand.magenta
        case .voice: return VonageBrand.orange
        case .result: return VonageBrand.plum
        }
    }
}

#Preview {
    let sampleEvents: [LogEvent] = [
        LogEvent(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            source: "device",
            requestId: "req-123",
            label: "silent_auth:cellular_check",
            step: "3/5",
            note: "Fetching the check_url over cellular — the network identifies the SIM from the connection itself.",
            detail: [:]
        ),
        LogEvent(
            timestamp: ISO8601DateFormatter().string(from: Date().addingTimeInterval(1)),
            source: "server",
            requestId: "req-123",
            label: "workflow:auto_advanced",
            note: "Vonage advanced to voice on its own — the SMS channel timed out.",
            detail: ["to": .string("voice")]
        )
    ]
    return VStack(alignment: .leading, spacing: 0) {
        ForEach(sampleEvents) { event in
            LogEventRow(event: event)
            Divider()
        }
    }
    .padding()
}
