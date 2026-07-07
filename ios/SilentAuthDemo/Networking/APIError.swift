import Foundation

enum APIError: Error, Equatable {
    case network(String)
    case server(statusCode: Int, body: String?)
    case decoding(String)

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case let (.network(a), .network(b)):
            return a == b
        case let (.server(aCode, aBody), .server(bCode, bBody)):
            return aCode == bCode && aBody == bBody
        case let (.decoding(a), .decoding(b)):
            return a == b
        default:
            return false
        }
    }
}
