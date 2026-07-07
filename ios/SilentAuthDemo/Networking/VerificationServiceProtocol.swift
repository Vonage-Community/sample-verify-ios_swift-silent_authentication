import Foundation

protocol VerificationServiceProtocol: Sendable {
    func startVerification(phone: String) async throws -> (requestId: String, checkUrl: String?)
    func performCellularCheck(checkUrl: String) async throws -> CellularCheckResult
    func triggerFallback(requestId: String) async throws
    func submitCode(requestId: String, code: String) async throws -> Bool
    func fetchLogs(requestId: String) async throws -> LogsResponse
}
