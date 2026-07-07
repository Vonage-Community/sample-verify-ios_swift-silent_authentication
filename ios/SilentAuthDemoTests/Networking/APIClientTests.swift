import XCTest
@testable import SilentAuthDemo

final class APIClientTests: XCTestCase {
    var apiClient: APIClient!
    var mockURLSession: URLSession!

    override func setUp() {
        super.setUp()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockURLSession = URLSession(configuration: config)
        apiClient = APIClient(session: mockURLSession)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testStartVerification_returnsRequestIdAndCheckUrl() async throws {
        let responseData = """
        {
            "request_id": "req-123",
            "check_url": "https://api.nexmo.com/v2/verify/req-123/silent-auth/redirect"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }

        let (requestId, checkUrl) = try await apiClient.startVerification(phone: "+14155551234")
        XCTAssertEqual(requestId, "req-123")
        XCTAssertEqual(checkUrl, "https://api.nexmo.com/v2/verify/req-123/silent-auth/redirect")
    }

    func testStartVerification_returnsNilCheckUrl() async throws {
        let responseData = """
        {
            "request_id": "req-456"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }

        let (requestId, checkUrl) = try await apiClient.startVerification(phone: "+14155551234")
        XCTAssertEqual(requestId, "req-456")
        XCTAssertNil(checkUrl)
    }

    func testStartVerification_throwsOnServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!
            let errorData = """
            {
                "title": "Invalid phone number"
            }
            """.data(using: .utf8)!
            return (response, errorData)
        }

        do {
            _ = try await apiClient.startVerification(phone: "+999")
            XCTFail("Expected APIError.server but no error was thrown")
        } catch let error as APIError {
            if case .server(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 422)
            } else {
                XCTFail("Expected APIError.server but got \(error)")
            }
        }
    }

    func testCheckCode_returnsTrue() async throws {
        let responseData = """
        {
            "verified": true,
            "status": "completed"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }

        let verified = try await apiClient.checkCode(requestId: "req-123", code: "abc123")
        XCTAssertTrue(verified)
    }

    func testCheckCode_returnsFalse() async throws {
        let responseData = """
        {
            "verified": false,
            "error": "Invalid code"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }

        let verified = try await apiClient.checkCode(requestId: "req-123", code: "wrong")
        XCTAssertFalse(verified)
    }

    func testNextWorkflow_succeeds() async throws {
        let responseData = """
        {
            "ok": true
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }

        try await apiClient.nextWorkflow(requestId: "req-123")
    }

    func testNextWorkflow_throwsOnError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            try await apiClient.nextWorkflow(requestId: "no-such-id")
            XCTFail("Expected APIError.server but no error was thrown")
        } catch let error as APIError {
            if case .server(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 404)
            } else {
                XCTFail("Expected APIError.server but got \(error)")
            }
        }
    }

    func testFetchLogs_returnsLogArray() async throws {
        let responseData = """
        {
            "logs": [
                {
                    "timestamp": "2026-06-22T22:00:00Z",
                    "source": "server",
                    "requestId": "req-123",
                    "label": "verification:created",
                    "detail": {
                        "phone": "+1•••••1234"
                    }
                }
            ],
            "channel": "voice"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }

        let result = try await apiClient.fetchLogs(requestId: "req-123")
        XCTAssertEqual(result.logs.count, 1)
        XCTAssertEqual(result.logs[0].label, "verification:created")
        XCTAssertEqual(result.logs[0].source, "server")
        XCTAssertEqual(result.channel, "voice")
    }
}

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("MockURLProtocol handler not set")
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
