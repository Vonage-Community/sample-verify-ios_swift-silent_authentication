import XCTest
@testable import SilentAuthDemo

final class LogStageTests: XCTestCase {
    private func event(_ label: String, detail: [String: AnyCodable] = [:]) -> LogEvent {
        LogEvent(timestamp: "2026-07-06T12:00:00Z", source: "server",
                 requestId: "req-1", label: label, detail: detail)
    }

    func testRequestStage() {
        XCTAssertEqual(event("verification:started").stage, .request)
        XCTAssertEqual(event("verification:created").stage, .request)
    }

    func testSilentAuthStage() {
        XCTAssertEqual(event("silent_auth:cellular_check").stage, .silentAuth)
        XCTAssertEqual(event("silent_auth:failed").stage, .silentAuth)
        XCTAssertEqual(event("webhook:silent_auth:action_pending").stage, .silentAuth)
    }

    func testSmsStage() {
        XCTAssertEqual(event("webhook:sms:pending").stage, .sms)
        XCTAssertEqual(event("silent_auth:not_available").stage, .silentAuth) // still names silent_auth
    }

    func testVoiceStage() {
        XCTAssertEqual(event("webhook:voice:completed").stage, .voice)
    }

    func testResultStageWinsOverChannelMention() {
        // summary names every channel but belongs to Result
        let summary = event("webhook:summary", detail: ["workflow": .string("sms, voice")])
        XCTAssertEqual(summary.stage, .result)
        XCTAssertEqual(event("verification:verified").stage, .result)
        XCTAssertEqual(event("verification:completed").stage, .result)
    }

    func testFallbackStageFollowsTarget() {
        XCTAssertEqual(event("verification:fallback", detail: ["to": .string("sms")]).stage, .sms)
        XCTAssertEqual(event("verification:fallback", detail: ["to": .string("voice")]).stage, .voice)
        XCTAssertEqual(event("workflow:auto_advanced", detail: ["to": .string("voice")]).stage, .voice)
        XCTAssertEqual(event("workflow:channel_advanced", detail: ["to": .string("voice")]).stage, .voice)
    }

    func testStagesAreOrdered() {
        XCTAssertTrue(LogStage.request.rawValue < LogStage.silentAuth.rawValue)
        XCTAssertTrue(LogStage.silentAuth.rawValue < LogStage.sms.rawValue)
        XCTAssertTrue(LogStage.sms.rawValue < LogStage.voice.rawValue)
        XCTAssertTrue(LogStage.voice.rawValue < LogStage.result.rawValue)
    }
}
