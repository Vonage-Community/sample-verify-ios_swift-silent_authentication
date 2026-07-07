## Prompt

ok lets create a new todo.md to tackle task 7:    ### Task 7 — iOS verification state machine + LoginViewModel Files: Models/VerificationState.swift, Features/Login/LoginViewModel.swift  State enum:

```
idle → enteringPhone → awaitingSilentAuth → 
```

`  ├─ silentAuthSucceeded → submittingCode → verified`
`  ├─ silentAuthFailed → enteringSmsCode`
`  │                          └─ submittingCode → verified`
`  └─ (no check_url) → enteringSmsCode`
Voice fallback state: `enteringVoiceCode` (after SMS also fails/times out via `/next` again).  `LoginViewModel` (ObservableObject): - `@Published var state: VerificationState` - `@Published var devLogs: [LogEvent]` - `@Published var devModeEnabled: Bool` - `func submitPhone(_ phone: String)` — starts verification, appends device-side log events, kicks off cellular check if `checkUrl` present, starts polling loop for `devLogs`. - `func triggerFallback()` — calls `/next`, transitions state. - `func submitCode(_ code: String)` — calls `/check-code`. - Polling: `Task` loop every 1.5s fetching `/logs/:request_id`, merging with device-side events (device events are prepended/merged by timestamp, not duplicated).  **State machine design note:** The state machine is a value-type enum rather than a class hierarchy because all transitions are explicit and exhaustible — a `switch` in the ViewModel covers every case with compile-time exhaustiveness, which matters for a tutorial where readers need to trace the full flow.  --- According to AGENTS.md

---

## Decisions recorded

- **`VerificationServiceProtocol` seam**: `LoginViewModel` must be unit-testable without HTTP. `APIClient` is a concrete `actor` and `CellularAuthClient` is a concrete class — neither is currently a protocol. Rather than protocolising both (verbose, two mocks), introduce a single `VerificationServiceProtocol` that owns the whole verification interaction. The real impl (`VerificationService`) delegates to `APIClient` + `CellularAuthClient`. Tests inject `MockVerificationService`. This keeps the ViewModel lean and the mock surface small.

- **`@MainActor` on `LoginViewModel`**: Published properties must be mutated on the main actor. Marking the whole class `@MainActor` is cleaner than sprinkling `await MainActor.run { }` throughout async functions. The service protocol uses `async` methods so the ViewModel can `await` them without blocking the main thread.

- **Polling cancellation**: The polling `Task` is stored as `private var pollingTask: Task<Void, Never>?`. It is cancelled in three places: when a new verification starts (replacing the previous), when verification completes (`verified` state), and in `deinit`. Not cancelling on fallback — polling continues across fallback transitions so Dev Mode stays live.

- **Log merging strategy**: Device-side log events (e.g. "Calling check_url over cellular…") are appended to a local `deviceLogs` array. When server logs are fetched, the two arrays are merged and sorted by `timestamp` string (ISO 8601 sorts lexicographically). De-duplication is by `(requestId, label, timestamp)` triple — server logs cannot contain device-sourced entries so there's no collision; the sort is the only operation needed.

- **State transition ownership**: The state machine transitions live entirely in `LoginViewModel`, not in `VerificationService`. The service is a thin async/await boundary; all logic about what state to enter next based on the response lives in the ViewModel `switch`. This makes the flow easy to trace for tutorial readers.

---

## Checklist

### 1. Protocol seam (needed before tests compile)
- [ ] `Networking/VerificationServiceProtocol.swift` — define `protocol VerificationServiceProtocol: Sendable` with:
  - `func startVerification(phone: String) async throws -> (requestId: String, checkUrl: String?)`
  - `func performCellularCheck(checkUrl: String) async throws -> String`
  - `func triggerFallback(requestId: String) async throws`
  - `func submitCode(requestId: String, code: String) async throws -> Bool`
  - `func fetchLogs(requestId: String) async throws -> [LogEvent]`
- [ ] `Networking/VerificationService.swift` — `actor VerificationService: VerificationServiceProtocol` that delegates to `APIClient` + `CellularAuthClient`

### 2. State model
- [ ] `Models/VerificationState.swift` — value-type `enum VerificationState: Equatable` with associated values:
  ```swift
  case idle
  case enteringPhone
  case awaitingSilentAuth(requestId: String)
  case silentAuthSucceeded(requestId: String, code: String)
  case submittingCode(requestId: String)
  case enteringSmsCode(requestId: String)
  case enteringVoiceCode(requestId: String)
  case verified
  case failed(APIError)
  ```
  - Include `requestId` in every post-verification state so the ViewModel can always find the right polling endpoint.

### 3. Tests (write before ViewModel implementation)
- [ ] `SilentAuthDemoTests/Features/Login/VerificationStateTests.swift` — state enum unit tests:
  - Equatability: same case + value == same case + value
  - `isTerminal` computed var (verified, failed) — not a state transition but important for polling stop logic
- [ ] `SilentAuthDemoTests/Features/Login/LoginViewModelTests.swift` — all state machine transitions via `MockVerificationService`:
  - `testSubmitPhone_transitionsToAwaitingSilentAuth` — `startVerification` returns `(requestId, checkUrl)`; assert state becomes `.awaitingSilentAuth`
  - `testSubmitPhone_noCheckUrl_transitionsToEnteringSmsCode` — `startVerification` returns no `checkUrl`; assert `.enteringSmsCode`
  - `testSubmitPhone_cellularSucceeds_transitionsToVerified` — cellular check succeeds, `submitCode` returns `true`; assert `.verified`
  - `testSubmitPhone_cellularFails_transitionsToEnteringSmsCode` — cellular check throws; assert `.enteringSmsCode` (fallback called)
  - `testTriggerFallback_fromSilentAuth_transitionsToEnteringSmsCode`
  - `testTriggerFallback_fromSms_transitionsToEnteringSmsCode` (wait — second fallback goes to `.enteringVoiceCode`)  
    → `testTriggerFallback_fromSms_transitionsToEnteringVoiceCode`
  - `testSubmitCode_verified_transitionsToVerified`
  - `testSubmitCode_invalidCode_staysInCodeEntry`
  - `testDevLogs_appendsDeviceEvents` — after `submitPhone`, device-side log events appear in `devLogs`
  - `testPolling_mergesServerLogs` — `MockVerificationService.fetchLogs` returns server logs; assert merged into `devLogs` sorted by timestamp

### 4. ViewModel implementation
- [ ] `Features/Login/LoginViewModel.swift` — `@MainActor final class LoginViewModel: ObservableObject`:
  - State transitions as described in prompt
  - Device log events appended for: "Starting verification…", "check_url received — calling over cellular…", "Cellular check complete — sending code…", "Falling back to SMS…", "Falling back to voice…"
  - Phone and code values redacted in log detail (reuse `redactPhone` / `redactCode` from server pattern — implement equivalent in Swift)
  - Polling loop: `Task { while !state.isTerminal { try await Task.sleep(...); logs = merge(await service.fetchLogs(...), deviceLogs) } }`
  - Cancel polling task on new verification start and on `verified`/`failed`

### 5. Wire up + verify
- [x] Add `VerificationState.swift` and `LoginViewModel.swift` to `scripts/create_xcodeproj.rb` (app target) and `VerificationStateTests.swift` + `LoginViewModelTests.swift` to test target
- [x] Regenerate `.xcodeproj` and run: `xcodebuild test -scheme SilentAuthDemoTests` — all 30 tests pass (SmokeTests + APIClientTests + CellularAuthClientTests + VerificationStateTests + LoginViewModelTests)

---

## Blog-worthy notes

**Protocol seam for testability:** The real `APIClient` and `CellularAuthClient` are concrete types, not protocols. To make `LoginViewModel` testable without hitting the network, we introduced `VerificationServiceProtocol` — a single facade that owns the whole verification interaction. The real `VerificationService` delegates to both clients. Tests inject `MockVerificationService`. This is more scalable than trying to protocol-ify each client separately (two protocols, two mocks).

**State machine with associated values:** The `VerificationState` enum carries `requestId` in every post-verification case. This eliminates the need for instance variables like `currentRequestId` in the ViewModel — the state *is* the request context. Computed property `requestId` extracts it from any case, simplifying the code that needs it (polling, code submission).

**`@MainActor` on ViewModel:** `LoginViewModel` properties are published and mutated on the main thread. Rather than sprinkling `await MainActor.run { }` calls, we marked the whole class `@MainActor`. Tests need the same annotation to access properties — the compiler catches violations. This is safer than manual threading.

**Asynchronous test timing:** Unit tests of async code need patience. Initial tests used `await` directly, but `await` doesn't work in synchronous test functions. Instead, we use `DispatchQueue.main.asyncAfter` to schedule assertions with a small delay, and `XCTestExpectation` to wait for them. The 0.1-0.2s delays are long enough to let the ViewModel's `Task` blocks execute, but short enough to keep tests fast. Alternatively, `@preconcurrency` and `DispatchQueue.main.sync` in the mock can force synchronous execution for determinism.

**Log merging by timestamp:** Device logs (appended immediately) and server logs (fetched every 1.5s) are merged by sorting on the `timestamp` field (ISO 8601 format sorts lexicographically). A `Set<String>` of `(requestId, label, timestamp)` tuples prevents duplicate logs if the same event is fetched twice. This approach works because server logs are immutable once emitted; device logs never collide with server logs by design.

**Fallback state transitions:** The second call to `/next` (from SMS to Voice) uses the same service method as the first call (Silent Auth to SMS). The ViewModel's `switch` statement on current state determines which state to enter — no additional server-side logic needed. This keeps the service simple and all the fallback logic in the ViewModel where it's visible to readers.
