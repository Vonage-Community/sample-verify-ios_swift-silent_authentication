import Foundation

/// The channel stages a verification passes through, in order. The Dev Mode
/// console groups the merged log timeline by these stages instead of numbering
/// individual events — the real story of the flow is "which channel is being
/// tried", not "step N of M".
enum LogStage: Int, CaseIterable {
    case request      // before any channel is active
    case silentAuth
    case sms
    case voice
    case result       // verified / final summary

    var title: String {
        switch self {
        case .request: return "Request"
        case .silentAuth: return "Silent Auth"
        case .sms: return "SMS"
        case .voice: return "Voice"
        case .result: return "Result"
        }
    }

    /// One-line explainer shown under the stage header.
    var blurb: String {
        switch self {
        case .request: return "Kicking off the verification"
        case .silentAuth: return "Verifying via the SIM — no user input"
        case .sms: return "One-time code by text message"
        case .voice: return "One-time code read aloud by phone call"
        case .result: return "Final outcome"
        }
    }
}

extension LogEvent {
    /// Which stage this event belongs to, derived from its label. Kept in one
    /// place so the console grouping and the stage tracker agree.
    var stage: LogStage {
        // Result-level events first — they can mention an earlier channel.
        if label == "verification:verified"
            || label == "verification:completed"
            || label == "webhook:summary" {
            return .result
        }

        if label.contains("silent_auth") { return .silentAuth }
        if label.contains("voice") { return .voice }
        if label.contains("sms") { return .sms }

        // Channel-less flow events: infer from the detail's target where present.
        if label == "verification:fallback"
            || label == "workflow:auto_advanced"
            || label == "workflow:channel_advanced" {
            let to = detail["to"]?.stringValue
            if to == "voice" { return .voice }
            if to == "sms" { return .sms }
        }

        // verification:started / :created / :request happen before any channel.
        return .request
    }
}
