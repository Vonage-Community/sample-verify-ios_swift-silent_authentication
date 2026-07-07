import Foundation

struct LogEvent: Codable, Identifiable {
    let id = UUID()
    let timestamp: String
    let source: String
    let requestId: String
    let label: String
    /// Enumerated position in the current verification path, e.g. "3/5".
    /// The total differs by path: silent auth and SMS are 5-step stories,
    /// the voice fallback stretches to 6.
    let step: String?
    /// Plain-English explanation of why this event matters — the narration
    /// Dev Mode renders under the raw detail values.
    let note: String?
    let detail: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case timestamp, source, requestId, label, step, note, detail
    }

    init(timestamp: String, source: String, requestId: String, label: String,
         step: String? = nil, note: String? = nil, detail: [String: AnyCodable]) {
        self.timestamp = timestamp
        self.source = source
        self.requestId = requestId
        self.label = label
        self.step = step
        self.note = note
        self.detail = detail
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(step, forKey: .step)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(detail, forKey: .detail)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        source = try container.decode(String.self, forKey: .source)
        requestId = try container.decode(String.self, forKey: .requestId)
        label = try container.decode(String.self, forKey: .label)
        step = try container.decodeIfPresent(String.self, forKey: .step)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        detail = try container.decode([String: AnyCodable].self, forKey: .detail)
    }
}
