import XCTest
@testable import SilentAuthDemo

final class VerificationStateTests: XCTestCase {
    func testEquatability() {
        let state1 = VerificationState.awaitingSilentAuth(requestId: "req-1")
        let state2 = VerificationState.awaitingSilentAuth(requestId: "req-1")
        let state3 = VerificationState.awaitingSilentAuth(requestId: "req-2")

        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }

    func testIsTerminal_verified() {
        XCTAssertTrue(VerificationState.verified.isTerminal)
    }

    func testIsTerminal_failed() {
        XCTAssertTrue(VerificationState.failed("error").isTerminal)
    }

    func testIsTerminal_idle() {
        XCTAssertFalse(VerificationState.idle.isTerminal)
    }

    func testIsTerminal_enteringSms() {
        XCTAssertFalse(VerificationState.enteringSmsCode(requestId: "req-1").isTerminal)
    }

    func testRequestId_awaitingSilentAuth() {
        let state = VerificationState.awaitingSilentAuth(requestId: "req-123")
        XCTAssertEqual(state.requestId, "req-123")
    }

    func testRequestId_enteringSmsCode() {
        let state = VerificationState.enteringSmsCode(requestId: "req-456")
        XCTAssertEqual(state.requestId, "req-456")
    }

    func testRequestId_idle() {
        XCTAssertNil(VerificationState.idle.requestId)
    }

    func testRequestId_verified() {
        XCTAssertNil(VerificationState.verified.requestId)
    }

    func testIsIdle_idle() {
        XCTAssertTrue(VerificationState.idle.isIdle)
    }

    func testIsIdle_enteringPhone() {
        XCTAssertTrue(VerificationState.enteringPhone.isIdle)
    }

    func testIsIdle_awaitingSilentAuth() {
        XCTAssertFalse(VerificationState.awaitingSilentAuth(requestId: "req-1").isIdle)
    }

    func testIsIdle_enteringSmsCode() {
        XCTAssertFalse(VerificationState.enteringSmsCode(requestId: "req-1").isIdle)
    }

    func testIsIdle_verified() {
        XCTAssertFalse(VerificationState.verified.isIdle)
    }
}
