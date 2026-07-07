import Foundation

enum VerificationState: Equatable {
    case idle
    case enteringPhone
    case awaitingSilentAuth(requestId: String)
    case silentAuthSucceeded(requestId: String, code: String)
    case submittingCode(requestId: String)
    case enteringSmsCode(requestId: String)
    case enteringVoiceCode(requestId: String)
    case verified
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .verified, .failed:
            return true
        default:
            return false
        }
    }

    var requestId: String? {
        switch self {
        case .awaitingSilentAuth(let id),
             .silentAuthSucceeded(let id, _),
             .submittingCode(let id),
             .enteringSmsCode(let id),
             .enteringVoiceCode(let id):
            return id
        default:
            return nil
        }
    }

    var isIdle: Bool {
        switch self {
        case .idle, .enteringPhone:
            return true
        default:
            return false
        }
    }
}
