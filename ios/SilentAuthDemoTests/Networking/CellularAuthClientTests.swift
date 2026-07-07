import XCTest
import VonageClientLibrary
@testable import SilentAuthDemo

final class CellularAuthClientTests: XCTestCase {
    var cellularAuthClient: CellularAuthClient!

    override func setUp() {
        super.setUp()
        cellularAuthClient = CellularAuthClient(client: MockCellularRequestClient())
    }

    func testPerformCellularCheck_returnsCode() async throws {
        let mockClient = MockCellularRequestClient(
            response: [
                "http_status": 200,
                "response_body": [
                    "request_id": "req-123",
                    "code": "si9sfG"
                ]
            ]
        )
        cellularAuthClient = CellularAuthClient(client: mockClient)

        let result = try await cellularAuthClient.performCellularCheck(
            checkUrl: "https://api.nexmo.com/v2/verify/req-123/silent-auth/redirect"
        )
        XCTAssertEqual(result.code, "si9sfG")
        XCTAssertEqual(result.requestId, "req-123")
    }

    func testPerformCellularCheck_throwsOnNetworkError() async throws {
        let mockClient = MockCellularRequestClient(
            response: [
                "error": "sdk_no_data_connectivity",
                "error_description": "Data connectivity not available"
            ]
        )
        cellularAuthClient = CellularAuthClient(client: mockClient)

        do {
            _ = try await cellularAuthClient.performCellularCheck(
                checkUrl: "https://api.nexmo.com/v2/verify/req-123/silent-auth/redirect"
            )
            XCTFail("Expected CellularAuthError.networkFailed")
        } catch let error as CellularAuthError {
            if case .networkFailed = error {
                // expected
            } else {
                XCTFail("Expected CellularAuthError.networkFailed but got \(error)")
            }
        }
    }

    func testPerformCellularCheck_throwsOnParseError() async throws {
        let mockClient = MockCellularRequestClient(
            response: [
                "http_status": 200,
                "response_body": [
                    "request_id": "req-123"
                    // missing "code"
                ]
            ]
        )
        cellularAuthClient = CellularAuthClient(client: mockClient)

        do {
            _ = try await cellularAuthClient.performCellularCheck(
                checkUrl: "https://api.nexmo.com/v2/verify/req-123/silent-auth/redirect"
            )
            XCTFail("Expected CellularAuthError.parseError")
        } catch let error as CellularAuthError {
            if case .parseError = error {
                // expected
            } else {
                XCTFail("Expected CellularAuthError.parseError but got \(error)")
            }
        }
    }
}

class MockCellularRequestClient: CellularRequestClientProtocol {
    var response: [String: Any]

    init(response: [String: Any] = [:]) {
        self.response = response
    }

    func startCellularGetRequest(
        params: VonageClientLibrary.VGCellularRequestParameters,
        debug: Bool
    ) async throws -> [String: Any] {
        return response
    }
}
