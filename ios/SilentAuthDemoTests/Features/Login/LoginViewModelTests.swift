import XCTest
@testable import SilentAuthDemo

@MainActor
final class LoginViewModelTests: XCTestCase {
    var viewModel: LoginViewModel!
    var mockService: MockVerificationService!

    override func setUp() {
        super.setUp()
        mockService = MockVerificationService()
        viewModel = LoginViewModel(service: mockService)
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(viewModel.devLogs.isEmpty)
        XCTAssertFalse(viewModel.devModeEnabled)
    }

    func testSubmitPhone_transitionsToAwaitingSilentAuth() {
        mockService.startVerificationResult = ("req-123", "https://check-url")
        // Don't set performCellularCheckResult, so it throws and falls back to SMS

        viewModel.submitPhone("+14155551234")
        let expectation = expectation(description: "State changed to enteringSmsCode (after cellular fallback)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if case .enteringSmsCode(let requestId) = self.viewModel.state {
                XCTAssertEqual(requestId, "req-123")
                expectation.fulfill()
            } else {
                XCTFail("Expected enteringSmsCode but got \(self.viewModel.state)")
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitPhone_noCheckUrl_transitionsToEnteringSmsCode() {
        mockService.startVerificationResult = ("req-456", nil)

        viewModel.submitPhone("+14155551234")
        let expectation = expectation(description: "State changed to enteringSmsCode")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if case .enteringSmsCode(let requestId) = self.viewModel.state {
                XCTAssertEqual(requestId, "req-456")
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitPhone_addsDeviceLogEvents() {
        mockService.startVerificationResult = ("req-123", nil)

        viewModel.submitPhone("+14155551234")
        let expectation = expectation(description: "Device logs added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.viewModel.devLogs.contains { $0.label.contains("verification") })
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitCode_verified_transitionsToVerified() {
        mockService.startVerificationResult = ("req-123", nil)
        mockService.submitCodeResult = true

        viewModel.submitPhone("+14155551234")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.viewModel.submitCode("123456")
        }

        let expectation = expectation(description: "State changed to verified")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(self.viewModel.state, .verified)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitCode_invalidCode_staysInCodeEntry() {
        mockService.startVerificationResult = ("req-123", nil)
        mockService.submitCodeResult = false

        viewModel.submitPhone("+14155551234")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.viewModel.submitCode("wrong")
        }

        let expectation = expectation(description: "State stays in enteringSmsCode")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if case .enteringSmsCode = self.viewModel.state {
                expectation.fulfill()
            } else {
                XCTFail("Expected to stay in enteringSmsCode state")
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testTriggerFallback_fromSilentAuth_transitionsToEnteringSmsCode() {
        // Start with awaitingSilentAuth state by manually setting it
        viewModel.state = .awaitingSilentAuth(requestId: "req-123")

        viewModel.triggerFallback()

        let expectation = expectation(description: "State changed to enteringSmsCode")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if case .enteringSmsCode(let requestId) = self.viewModel.state {
                XCTAssertEqual(requestId, "req-123")
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testTriggerFallback_fromSms_transitionsToEnteringVoiceCode() {
        mockService.startVerificationResult = ("req-123", nil)

        viewModel.submitPhone("+14155551234")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.viewModel.triggerFallback()
        }

        let expectation = expectation(description: "State changed to enteringVoiceCode")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if case .enteringVoiceCode(let requestId) = self.viewModel.state {
                XCTAssertEqual(requestId, "req-123")
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testDevModeToggle() async throws {
        XCTAssertFalse(viewModel.devModeEnabled)
        viewModel.devModeEnabled = true
        XCTAssertTrue(viewModel.devModeEnabled)
    }

    func testSignOut_resetsToIdle() {
        viewModel.state = .verified

        viewModel.signOut()

        let expectation = expectation(description: "State reset to idle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.state, .idle)
            XCTAssertTrue(self.viewModel.devLogs.isEmpty)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitPhone_cellularSuccess_transitionsToVerified() {
        mockService.startVerificationResult = ("req-123", "https://check-url")
        mockService.performCellularCheckResult = CellularCheckResult(code: "123456", requestId: "req-123")
        mockService.submitCodeResult = true

        viewModel.submitPhone("+14155551234")

        let expectation = expectation(description: "State changed to verified via cellular")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(self.viewModel.state, .verified)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitCode_fromVoiceState_verified() {
        viewModel.state = .enteringVoiceCode(requestId: "req-123")
        mockService.submitCodeResult = true

        viewModel.submitCode("123456")

        let expectation = expectation(description: "State changed to verified from voice")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.state, .verified)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitPhone_cellularSuccess_logsEnumeratedSteps() {
        mockService.startVerificationResult = ("req-123", "https://check-url")
        mockService.performCellularCheckResult = CellularCheckResult(code: "123456", requestId: "req-123")
        mockService.submitCodeResult = true

        viewModel.submitPhone("+14155551234")

        let expectation = expectation(description: "Silent auth path logs steps 1/5 through 5/5")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let steps = self.viewModel.devLogs.compactMap { $0.step }
            XCTAssertEqual(steps, ["1/5", "2/5", "3/5", "4/5", "5/5"])
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitPhone_integrityMismatch_abortsToFallback() {
        mockService.startVerificationResult = ("req-123", "https://check-url")
        // Carrier echoes back a different request_id — possible MITM
        mockService.performCellularCheckResult = CellularCheckResult(code: "123456", requestId: "req-EVIL")

        viewModel.submitPhone("+14155551234")

        let expectation = expectation(description: "Mismatch logged and fell back to SMS")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertTrue(self.viewModel.devLogs.contains { $0.label == "silent_auth:integrity_mismatch" })
            XCTAssertFalse(self.viewModel.devLogs.contains { $0.label == "silent_auth:code_obtained" })
            if case .enteringSmsCode = self.viewModel.state {
                expectation.fulfill()
            } else {
                XCTFail("Expected enteringSmsCode after integrity mismatch, got \(self.viewModel.state)")
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSubmitCode_fromVoiceState_logsSixStepTotals() {
        viewModel.state = .enteringVoiceCode(requestId: "req-123")
        mockService.submitCodeResult = true

        viewModel.submitCode("123456")

        let expectation = expectation(description: "Voice path uses /6 step totals")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let steps = self.viewModel.devLogs.compactMap { $0.step }
            XCTAssertEqual(steps, ["5/6", "6/6"])
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testTriggerFallback_fromSms_setsVoicePath() {
        viewModel.state = .enteringSmsCode(requestId: "req-123")

        viewModel.triggerFallback()

        let expectation = expectation(description: "Fallback log announces the 6-step voice path")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let fallbackLog = self.viewModel.devLogs.first { $0.label == "verification:fallback" }
            XCTAssertEqual(fallbackLog?.step, "4/6")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testPolling_serverChannelVoice_autoAdvancesSmsToVoice() {
        // Land in the SMS code screen (no check_url → straight to SMS)
        mockService.startVerificationResult = ("req-123", nil)
        // Vonage auto-advanced to voice on its own; the polled /logs reports it
        mockService.fetchLogsChannel = "voice"

        viewModel.submitPhone("+14155551234")

        // Polling sleeps 1.5s before its first fetch
        let expectation = expectation(description: "App catches up to the voice channel from polling")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if case .enteringVoiceCode = self.viewModel.state {
                XCTAssertTrue(self.viewModel.devLogs.contains { $0.label == "workflow:auto_advanced" })
                expectation.fulfill()
            } else {
                XCTFail("Expected enteringVoiceCode after server reported voice, got \(self.viewModel.state)")
            }
        }
        waitForExpectations(timeout: 3.0)
    }

    func testTriggerFallback_fromVoiceCode_isNoOp() {
        viewModel.state = .enteringVoiceCode(requestId: "req-123")

        viewModel.triggerFallback()

        let expectation = expectation(description: "triggerFallback called but state unchanged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.state, .enteringVoiceCode(requestId: "req-123"))
            XCTAssertTrue(self.mockService.triggerFallbackCalled)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }
}

class MockVerificationService: VerificationServiceProtocol {
    var startVerificationResult: (String, String?)? = nil
    var performCellularCheckResult: CellularCheckResult? = nil
    var submitCodeResult: Bool = false
    var fetchLogsResult: [LogEvent] = []
    var fetchLogsChannel: String? = nil
    var triggerFallbackCalled: Bool = false

    func startVerification(phone: String) async throws -> (requestId: String, checkUrl: String?) {
        guard let result = startVerificationResult else {
            throw APIError.network("Mock not configured")
        }
        return result
    }

    func performCellularCheck(checkUrl: String) async throws -> CellularCheckResult {
        guard let result = performCellularCheckResult else {
            throw CellularAuthError.networkFailed("Mock error")
        }
        return result
    }

    func triggerFallback(requestId: String) async throws {
        triggerFallbackCalled = true
    }

    func submitCode(requestId: String, code: String) async throws -> Bool {
        return submitCodeResult
    }

    func fetchLogs(requestId: String) async throws -> LogsResponse {
        return LogsResponse(logs: fetchLogsResult, channel: fetchLogsChannel)
    }
}
