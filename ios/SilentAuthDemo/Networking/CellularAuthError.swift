import Foundation

enum CellularAuthError: Error, Equatable {
    case noCheckUrl
    case networkFailed(String)
    case parseError

    static func == (lhs: CellularAuthError, rhs: CellularAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.noCheckUrl, .noCheckUrl):
            return true
        case let (.networkFailed(a), .networkFailed(b)):
            return a == b
        case (.parseError, .parseError):
            return true
        default:
            return false
        }
    }
}
