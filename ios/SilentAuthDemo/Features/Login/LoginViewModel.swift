import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var state: VerificationState = .idle
    @Published var devLogs: [LogEvent] = []
    @Published var devModeEnabled: Bool = false

    /// Which channel is currently doing the verifying. Determines the step
    /// totals shown in Dev Mode: silent auth and SMS are 5-step paths, the
    /// voice fallback (silent_auth → sms → voice) stretches to 6.
    enum Path {
        case silentAuth, sms, voice

        var total: Int { self == .voice ? 6 : 5 }

        /// The backend's channel name for this path (silent auth and SMS both
        /// run before voice; the SMS path also covers the silent-auth phase).
        var serverName: String {
            switch self {
            case .silentAuth: return "silent_auth"
            case .sms: return "sms"
            case .voice: return "voice"
            }
        }
    }

    private(set) var path: Path = .silentAuth

    private let service: any VerificationServiceProtocol
    private var pollingTask: Task<Void, Never>?
    private var deviceLogs: [LogEvent] = []

    init(service: any VerificationServiceProtocol = VerificationService()) {
        self.service = service
    }

    func submitPhone(_ phone: String) {
        pollingTask?.cancel()
        pollingTask = nil
        deviceLogs = []
        devLogs = []
        path = .silentAuth

        addDeviceLog(
            label: "verification:started",
            step: "1/5",
            note: "Phone submitted. The backend asks Vonage to start a verification with the workflow [silent_auth, sms, voice] — Silent Auth always goes first.",
            detail: ["phone": redactPhone(phone)]
        )

        Task {
            do {
                state = .enteringPhone
                let (requestId, checkUrl) = try await service.startVerification(phone: phone)

                if let checkUrl = checkUrl {
                    state = .awaitingSilentAuth(requestId: requestId)
                    addDeviceLog(
                        label: "silent_auth:check_url_received",
                        step: "2/5",
                        note: "Vonage's carrier coverage check passed and returned a check_url. Only this device can complete it — the proof is the SIM itself.",
                        detail: ["requestId": requestId]
                    )
                    startPolling(requestId: requestId)

                    do {
                        addDeviceLog(
                            label: "silent_auth:cellular_check",
                            step: "3/5",
                            note: "Fetching the check_url over the cellular interface (never Wi-Fi). The request hops through carrier redirects; the network identifies the SIM from the connection itself — no code, no user input.",
                            detail: [:]
                        )

                        let result = try await service.performCellularCheck(checkUrl: checkUrl)

                        // Anti-MITM check from Vonage's Silent Auth guidance: the
                        // request_id echoed through the carrier must match ours.
                        if let echoed = result.requestId, echoed != requestId {
                            addDeviceLog(
                                label: "silent_auth:integrity_mismatch",
                                note: "The request_id returned by the carrier does not match the original — possible man-in-the-middle. Aborting Silent Auth.",
                                detail: ["expected": requestId, "received": echoed]
                            )
                            await triggerFallback()
                            return
                        }

                        addDeviceLog(
                            label: "silent_auth:code_obtained",
                            step: "4/5",
                            note: "The carrier confirmed SIM ownership and returned a one-time code. request_id integrity check passed. The user never sees this code — the device sends it straight to the backend.",
                            detail: ["code": redactCode(result.code)]
                        )
                        state = .submittingCode(requestId: requestId)

                        let verified = try await service.submitCode(requestId: requestId, code: result.code)
                        if verified {
                            state = .verified
                            addDeviceLog(
                                label: "verification:verified",
                                step: "5/5",
                                note: "Verified — and the user typed nothing. Compare this timeline with an SMS run to see the difference.",
                                detail: [:]
                            )
                            pollingTask?.cancel()
                        } else {
                            await triggerFallback()
                        }
                    } catch {
                        addDeviceLog(
                            label: "silent_auth:failed",
                            note: "The cellular check failed (Wi-Fi-only, unsupported carrier, or network error). Falling back to SMS instead of waiting for the silent_auth timeout.",
                            detail: ["error": String(describing: error)]
                        )
                        await triggerFallback()
                    }
                } else {
                    path = .sms
                    addDeviceLog(
                        label: "silent_auth:not_available",
                        step: "2/5",
                        note: "No check_url — the carrier coverage check did not pass. Vonage skips straight to the SMS channel; the path is still 5 steps, but now the user has to participate.",
                        detail: [:]
                    )
                    state = .enteringSmsCode(requestId: requestId)
                    startPolling(requestId: requestId)
                }
            } catch {
                state = .failed(String(describing: error))
                addDeviceLog(label: "verification:error", detail: ["error": String(describing: error)])
            }
        }
    }

    func triggerFallback() {
        guard let requestId = state.requestId else { return }

        // Decide the next channel from the *current* state, then transition the
        // UI immediately. The /next call is fired afterwards in the background:
        // waiting for that round-trip to flip the state left the screen frozen
        // on the previous channel when the request was slow or the cellular
        // request's URLSession was still tearing down.
        let nextState: VerificationState?
        switch state {
        case .awaitingSilentAuth, .silentAuthSucceeded:
            path = .sms
            nextState = .enteringSmsCode(requestId: requestId)
            addDeviceLog(
                label: "verification:fallback",
                step: "2/5",
                note: "Silent Auth didn't complete — asking the backend to advance the workflow to SMS immediately.",
                detail: ["requestId": requestId, "to": "sms"]
            )
        case .enteringSmsCode:
            path = .voice
            nextState = .enteringVoiceCode(requestId: requestId)
            addDeviceLog(
                label: "verification:fallback",
                step: "4/6",
                note: "SMS didn't arrive — advancing the workflow to voice. Note the path just grew from 5 steps to 6: each fallback adds work.",
                detail: ["requestId": requestId, "to": "voice"]
            )
        default:
            // Voice is the last channel — nothing to fall back to. The backend
            // call still happens (Vonage decides what "next" means), but the
            // path and state stay put.
            nextState = nil
            addDeviceLog(label: "verification:fallback", detail: ["requestId": requestId])
        }

        if let nextState {
            state = nextState
        }

        Task {
            do {
                try await service.triggerFallback(requestId: requestId)
            } catch {
                state = .failed(String(describing: error))
                addDeviceLog(label: "verification:fallback_error", detail: ["error": String(describing: error)])
            }
        }
    }

    func submitCode(_ code: String) {
        guard let requestId = state.requestId else { return }

        // Keep the path honest even if state was set externally.
        if case .enteringVoiceCode = state {
            path = .voice
        } else if case .enteringSmsCode = state, path == .silentAuth {
            path = .sms
        }

        let total = path.total
        addDeviceLog(
            label: "verification:code_submitted",
            step: "\(total - 1)/\(total)",
            note: "The user read the code and typed it in — the manual step Silent Auth avoids entirely.",
            detail: ["code": redactCode(code)]
        )
        state = .submittingCode(requestId: requestId)

        Task {
            do {
                let verified = try await service.submitCode(requestId: requestId, code: code)
                if verified {
                    state = .verified
                    pollingTask?.cancel()
                    addDeviceLog(
                        label: "verification:verified",
                        step: "\(total)/\(total)",
                        note: "Verified via the \(path == .voice ? "voice" : "SMS") channel after \(total) steps.",
                        detail: [:]
                    )
                } else {
                    // Invalid code, stay in code entry state
                    switch state {
                    case .submittingCode:
                        state = path == .voice
                            ? .enteringVoiceCode(requestId: requestId)
                            : .enteringSmsCode(requestId: requestId)
                    default:
                        break
                    }
                    addDeviceLog(
                        label: "verification:invalid_code",
                        note: "Vonage rejected the code — three wrong attempts fail the whole request.",
                        detail: [:]
                    )
                }
            } catch {
                state = .failed(String(describing: error))
                addDeviceLog(label: "verification:code_error", detail: ["error": String(describing: error)])
            }
        }
    }

    func signOut() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .idle
        path = .silentAuth
        devLogs = []
        deviceLogs = []
    }

    private func startPolling(requestId: String) {
        pollingTask?.cancel()

        pollingTask = Task {
            while !state.isTerminal {
                do {
                    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    let response = try await service.fetchLogs(requestId: requestId)
                    reconcileChannel(response.channel, requestId: requestId)
                    mergeLogs(serverLogs: response.logs)
                } catch {
                    // Polling error, continue
                }
            }
        }
    }

    /// Vonage auto-advances channels on timeout (e.g. SMS expires → it places a
    /// voice call) without the app ever calling /next. The backend learns this
    /// from webhooks and reports the live channel here; if it's ahead of our
    /// local path, catch the UI up so the code screen, step totals, and labels
    /// match what actually happened.
    private func reconcileChannel(_ serverChannel: String?, requestId: String) {
        guard let serverChannel else { return }

        let serverRank = ["silent_auth": 0, "sms": 1, "voice": 2]
        let currentRank = serverRank[path.serverName] ?? 0
        guard let incoming = serverRank[serverChannel], incoming > currentRank else { return }

        if serverChannel == "voice" {
            path = .voice
            addDeviceLog(
                label: "workflow:auto_advanced",
                step: "4/6",
                note: "Vonage advanced to voice on its own — the SMS channel timed out. The app didn't tap \"Didn't get it?\"; the workflow moved forward by itself.",
                detail: ["to": "voice"]
            )
            if case .enteringSmsCode = state {
                state = .enteringVoiceCode(requestId: requestId)
            }
        } else if serverChannel == "sms", path == .silentAuth {
            path = .sms
        }
    }

    private func mergeLogs(serverLogs: [LogEvent]) {
        var merged = serverLogs + deviceLogs
        merged.sort { $0.timestamp < $1.timestamp }

        var seen = Set<String>()
        devLogs = merged.filter { log in
            let key = "\(log.requestId):\(log.label):\(log.timestamp)"
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func addDeviceLog(label: String, step: String? = nil, note: String? = nil, detail: [String: String]) {
        let log = LogEvent(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            source: "device",
            requestId: state.requestId ?? "unknown",
            label: label,
            step: step,
            note: note,
            detail: detail.mapValues { AnyCodable.string($0) }
        )
        deviceLogs.append(log)
        mergeLogs(serverLogs: [])
    }

    deinit {
        pollingTask?.cancel()
    }
}

func redactPhone(_ phone: String) -> String {
    guard phone.count >= 6 else { return phone }
    let countryPart = String(phone.prefix(3))
    let lastFour = String(phone.suffix(4))
    return "\(countryPart)•••••\(lastFour)"
}

func redactCode(_ code: String) -> String {
    guard code.count >= 2 else { return code }
    return String(code.suffix(2))
}
