## Prompt

ok lets create a new todo.md to tackle task 6: 

### Task 6 — iOS networking layer
Files: `Networking/APIClient.swift`, `Networking/CellularAuthClient.swift`

- `APIClient`: async/await wrapper around `URLSession`. Methods: `startVerification(phone:)→(requestId, checkUrl?)`, `nextWorkflow(requestId:)`, `checkCode(requestId:code:)→verified:Bool`, `fetchLogs(requestId:)→[LogEvent]`. Base URL read from `Config.xcconfig`.
- `CellularAuthClient`: wraps `VGCellularRequestClient`. Method: `performCellularCheck(checkUrl:)→String` (returns the `code` from the JSON response). Uses `startCellularRequest(params:debug:)` — note: current Vonage docs show this method name, not `startCellularGetRequest` as referenced in some older sources.
- Error types: `APIError` (network, server, decoding), `CellularAuthError` (noCheckUrl, networkFailed, parseError).

---
According to AGENTS.md

---

## Decisions recorded

- **`startCellularGetRequest` vs `startCellularRequest`**: Confirmed by reading `VGCellularRequestClient.swift` from the checked-out source (v1.0.5): the method is `startCellularGetRequest(params:debug:)`. The Vonage blog says `startCellularRequest` but the source is the authority. AGENTS.md updated accordingly.

- **`CellularClient` protocol is internal**: The `CellularClient` protocol and the `convenience init(cellularClient:)` on `VGCellularRequestClient` are both internal (not `public`). This means we cannot inject a mock from test code outside the library. Solution: define our own `CellularRequestClientProtocol` in the app, wrap `VGCellularRequestClient` behind it, and inject the protocol in tests. `CellularAuthClient` depends on the protocol, not the concrete type.

- **`startCellularGetRequest` response shape** (confirmed from source):
  - Error: `{ "error": "sdk_no_data_connectivity", "error_description": "...", "debug"?: {...} }`
  - Success: `{ "http_status": <Int>, "response_body": { "request_id": "...", "code": "..." }, "debug"?: {...} }`
  - The `response_body` is the parsed JSON from the final redirect in the check_url chain.

- **`APIClient` testability**: Inject `URLSession` via `URLProtocol` subclass in tests — no third-party mocking libraries. Register a custom `URLProtocol` that intercepts requests and returns fixture data. This keeps the test target dependency-free.

- **Base URL from `Config.xcconfig`**: The xcconfig sets `BASE_URL = http://localhost:4000`. Reading it at runtime via `Bundle.main.infoDictionary` requires adding `$(BASE_URL)` as an entry in `Info.plist`. We'll use a `Configuration` enum that reads this key, falling back to `http://localhost:4000` if missing (safe for unit tests which have no Info.plist).

---

## Checklist

### Models (write first — types tests depend on)
- [x] `Models/LogEvent.swift` — `Codable` struct: `timestamp: String`, `source: String`, `requestId: String`, `label: String`, `detail: [String: AnyCodable]`
- [x] `Models/AnyCodable.swift` — thin `Codable` wrapper for `[String: Any]` detail values (needed because `detail` is a heterogeneous dict)
- [x] `Networking/APIError.swift` — `enum APIError: Error` with cases `network(Error)`, `server(statusCode: Int, body: String?)`, `decoding(Error)`
- [x] `Networking/CellularAuthError.swift` — `enum CellularAuthError: Error` with cases `noCheckUrl`, `networkFailed(String)`, `parseError`

### Tests (write before implementation)
- [x] `SilentAuthDemoTests/Networking/APIClientTests.swift` (8 tests, all passing):
  - `testStartVerification_returnsRequestIdAndCheckUrl` ✓
  - `testStartVerification_returnsNilCheckUrl` ✓
  - `testStartVerification_throwsOnServerError` ✓
  - `testNextWorkflow_succeeds` ✓
  - `testNextWorkflow_throwsOnError` ✓
  - `testCheckCode_returnsTrue` ✓
  - `testCheckCode_returnsFalse` ✓
  - `testFetchLogs_returnsLogArray` ✓
- [x] `SilentAuthDemoTests/Networking/CellularAuthClientTests.swift` (3 tests, all passing):
  - `testPerformCellularCheck_returnsCode` ✓
  - `testPerformCellularCheck_throwsOnNetworkError` ✓
  - `testPerformCellularCheck_throwsOnParseError` ✓

### Implementation
- [x] `Networking/CellularRequestClientProtocol.swift` — `protocol CellularRequestClientProtocol` with `func startCellularGetRequest(params:debug:) async throws -> [String: Any]`; add `extension VGCellularRequestClient: CellularRequestClientProtocol {}`
- [x] `Networking/Configuration.swift` — reads `BASE_URL` from `Bundle.main.infoDictionary`, falls back to `http://localhost:4000`
- [x] `Networking/APIClient.swift` — `actor APIClient` (actor for thread safety on the shared URLSession); inject `URLSession` for testability
- [x] `Networking/CellularAuthClient.swift` — depends on `CellularRequestClientProtocol`; inject in init

### Wire up + verify
- [x] Add `BASE_URL` key to `ios/SilentAuthDemo/Info.plist` so `Configuration` can read it at runtime: `<key>BASE_URL</key><string>$(BASE_URL)</string>`
- [x] Add new source files to `scripts/create_xcodeproj.rb` (or add to Xcode target manually and update script to match)
- [x] `xcodebuild test -scheme SilentAuthDemoTests` — all 12 tests pass (SmokeTests + APIClientTests + CellularAuthClientTests)

---

## Blog-worthy notes

**Protocol wrapping for library limitations:** `VGCellularRequestClient` from `VonageClientLibrary` has an internal `CellularClient` protocol that can't be injected from test code. Solution: define a public `CellularRequestClientProtocol` in the app and make `VGCellularRequestClient` conform to it via an extension (without modifying library source). This pattern lets you write unit tests that mock the cellular request without hitting real Vonage infrastructure. The extension approach is safer than forking or patching the library.

**`URLProtocol` for URLSession mocking:** No third-party mocking libraries. A custom `URLProtocol` subclass registered on a test-only `URLSessionConfiguration` intercepts all HTTP requests and returns fixture data from the test. This exercises the full encode/decode path and keeps dependencies minimal — just Foundation + VonageClientLibrary.

**`actor` for NetworkClient thread safety:** The iOS networking layer uses Swift `actor` to wrap shared `URLSession` state. This gives thread-safe mutation (the session is immutable, but reference counting is handled by the actor) and eliminates the need for locks or serial queues. The actor also isolates the `baseURL` and session instance, preventing accidental concurrent access.

**AnyCodable for heterogeneous detail dicts:** The `LogEvent.detail` field is `[String: AnyCodable]` because the server's logs contain varied value types (strings, numbers, nested objects). A custom `AnyCodable` enum with recursive `Codable` conformance avoids force-casting when decoding and encoding logs. This keeps the log model clean: no `[String: Any]` or unsafe casts.

**Configuration reading from Info.plist at runtime:** `BASE_URL` is a build setting (`$(BASE_URL)`) substituted into `Info.plist` at compile time. Reading it at runtime via `Bundle.main.infoDictionary` lets the backend URL change between Debug (local), Staging (ngrok), and Release (production) builds without code changes. The fallback to `http://localhost:4000` ensures tests don't crash if the key is missing (no Info.plist in test bundles).

**`VGCellularRequestClient` response shape gotcha:** The documented response includes both success (with `response_body`) and error cases (with `error` + `error_description`). Both are dictionary shapes from the library; there's no intermediate type. The `response_body` is always the parsed JSON from the final response at the end of the redirect chain, so extracting the `code` field requires nested dict access — no Swift struct available.
