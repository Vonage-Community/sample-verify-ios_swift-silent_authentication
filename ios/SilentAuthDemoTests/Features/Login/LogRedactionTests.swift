import XCTest
@testable import SilentAuthDemo

final class LogRedactionTests: XCTestCase {
    // MARK: - Phone Redaction Tests

    func testRedactPhone_standard() {
        let result = redactPhone("+14155551234")
        XCTAssertEqual(result, "+14•••••1234")
    }

    func testRedactPhone_international() {
        let result = redactPhone("+447911123456")
        XCTAssertEqual(result, "+44•••••3456")
    }

    func testRedactPhone_short() {
        let result = redactPhone("+123")
        XCTAssertEqual(result, "+123")
    }

    func testRedactPhone_preservesPrefix() {
        let result = redactPhone("+551198765432")
        XCTAssertEqual(result, "+55•••••5432")
        XCTAssertTrue(result.hasPrefix("+55"))
    }

    // MARK: - Code Redaction Tests

    func testRedactCode_sixDigit() {
        let result = redactCode("123456")
        XCTAssertEqual(result, "56")
    }

    func testRedactCode_fourDigit() {
        let result = redactCode("9012")
        XCTAssertEqual(result, "12")
    }

    func testRedactCode_twoDigit() {
        let result = redactCode("42")
        XCTAssertEqual(result, "42")
    }

    func testRedactCode_oneDigit() {
        let result = redactCode("7")
        XCTAssertEqual(result, "7")
    }

    // MARK: - AnyCodable String Value Tests

    func testAnyCodable_string() {
        let value = AnyCodable.string("hello")
        XCTAssertEqual(value.stringValue, "hello")
    }

    func testAnyCodable_int() {
        let value = AnyCodable.int(42)
        XCTAssertEqual(value.stringValue, "42")
    }

    func testAnyCodable_bool_true() {
        let value = AnyCodable.bool(true)
        XCTAssertEqual(value.stringValue, "true")
    }

    func testAnyCodable_bool_false() {
        let value = AnyCodable.bool(false)
        XCTAssertEqual(value.stringValue, "false")
    }

    func testAnyCodable_null() {
        let value = AnyCodable.null
        XCTAssertEqual(value.stringValue, "null")
    }

    func testAnyCodable_double() {
        let value = AnyCodable.double(3.14)
        XCTAssertEqual(value.stringValue, "3.14")
    }

    func testAnyCodable_array() {
        let value = AnyCodable.array([.string("a"), .int(1)])
        XCTAssertEqual(value.stringValue, "[a, 1]")
    }

    func testAnyCodable_object_sorted() {
        let value = AnyCodable.object(["z": .string("last"), "a": .string("first")])
        XCTAssertEqual(value.stringValue, "{a: first, z: last}")
    }

    // MARK: - LogEvent step/note decoding

    func testLogEvent_decodesStepAndNote() throws {
        let json = """
        {"timestamp":"2026-07-06T12:00:00Z","source":"server","requestId":"req-1",
         "label":"silent_auth:coverage_passed","step":"2/5",
         "note":"Coverage check passed.","detail":{"checkUrl":"present"}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(LogEvent.self, from: json)
        XCTAssertEqual(event.step, "2/5")
        XCTAssertEqual(event.note, "Coverage check passed.")
    }

    func testLogEvent_decodesWithoutStepAndNote() throws {
        let json = """
        {"timestamp":"2026-07-06T12:00:00Z","source":"device","requestId":"req-1",
         "label":"verification:error","detail":{}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(LogEvent.self, from: json)
        XCTAssertNil(event.step)
        XCTAssertNil(event.note)
    }
}
