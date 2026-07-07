import VonageClientLibrary

/// Result of a successful check_url round trip over cellular.
/// `requestId` is echoed back by Vonage so the caller can compare it against
/// the original request — a mismatch indicates a man-in-the-middle and the
/// flow must be aborted (per Vonage's Silent Auth security guidance).
struct CellularCheckResult: Sendable, Equatable {
    let code: String
    let requestId: String?
}

final class CellularAuthClient: Sendable {
    private let client: any CellularRequestClientProtocol

    init(client: any CellularRequestClientProtocol = VGCellularRequestClient()) {
        self.client = client
    }

    func performCellularCheck(checkUrl: String) async throws -> CellularCheckResult {
        let params = VGCellularRequestParameters(
            url: checkUrl,
            headers: [:],
            queryParameters: [:],
            maxRedirectCount: 10
        )

        let response = try await client.startCellularGetRequest(params: params, debug: false)

        // Check for error
        if let error = response["error"] as? String {
            throw CellularAuthError.networkFailed(error)
        }

        // Extract code from response_body
        guard let responseBody = response["response_body"] as? [String: Any],
              let code = responseBody["code"] as? String else {
            throw CellularAuthError.parseError
        }

        return CellularCheckResult(
            code: code,
            requestId: responseBody["request_id"] as? String
        )
    }
}
