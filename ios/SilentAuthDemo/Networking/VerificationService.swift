import Foundation

actor VerificationService: VerificationServiceProtocol {
    private let apiClient: APIClient
    private let cellularAuthClient: CellularAuthClient

    init(apiClient: APIClient = APIClient(), cellularAuthClient: CellularAuthClient = CellularAuthClient()) {
        self.apiClient = apiClient
        self.cellularAuthClient = cellularAuthClient
    }

    func startVerification(phone: String) async throws -> (requestId: String, checkUrl: String?) {
        try await apiClient.startVerification(phone: phone)
    }

    func performCellularCheck(checkUrl: String) async throws -> CellularCheckResult {
        try await cellularAuthClient.performCellularCheck(checkUrl: checkUrl)
    }

    func triggerFallback(requestId: String) async throws {
        try await apiClient.nextWorkflow(requestId: requestId)
    }

    func submitCode(requestId: String, code: String) async throws -> Bool {
        try await apiClient.checkCode(requestId: requestId, code: code)
    }

    func fetchLogs(requestId: String) async throws -> LogsResponse {
        try await apiClient.fetchLogs(requestId: requestId)
    }
}
