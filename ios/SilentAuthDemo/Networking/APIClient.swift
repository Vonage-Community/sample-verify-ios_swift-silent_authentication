import Foundation

/// Response from `GET /logs/:request_id`. `channel` is the channel Vonage
/// currently considers active — it can move ahead of the app's local state
/// when Vonage auto-advances on a channel timeout.
struct LogsResponse: Decodable {
    let logs: [LogEvent]
    let channel: String?
}

actor APIClient {
    private let session: URLSession
    private let baseURL: String

    init(session: URLSession = .shared, baseURL: String = Configuration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func startVerification(phone: String) async throws -> (requestId: String, checkUrl: String?) {
        let url = URL(string: "\(baseURL)/verification")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["phone": phone]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        struct Response: Decodable {
            let request_id: String
            let check_url: String?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (requestId: decoded.request_id, checkUrl: decoded.check_url)
    }

    func checkCode(requestId: String, code: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/check-code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["request_id": requestId, "code": code]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        struct Response: Decodable {
            let verified: Bool
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.verified
    }

    func nextWorkflow(requestId: String) async throws {
        let url = URL(string: "\(baseURL)/next")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["request_id": requestId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func fetchLogs(requestId: String) async throws -> LogsResponse {
        let url = URL(string: "\(baseURL)/logs/\(requestId)")!
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)

        return try JSONDecoder().decode(LogsResponse.self, from: data)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network("Invalid response type")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(statusCode: httpResponse.statusCode, body: nil)
        }
    }
}
