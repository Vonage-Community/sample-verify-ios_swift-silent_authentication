import XCTest

// Canary test — proves the build target is wired correctly.
// If this fails, the project structure is broken before any app logic exists.
final class SmokeTests: XCTestCase {
    func testBundleIdentifier() {
        let bundle = Bundle(for: SmokeTests.self)
        XCTAssertEqual(bundle.bundleIdentifier, "com.vonage.SilentAuthDemoTests")
    }
}
