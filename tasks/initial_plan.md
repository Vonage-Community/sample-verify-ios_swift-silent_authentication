# Plan: SilentAuthDemo — Vonage Verify v2 iOS + Node.js Backend

## Context

Building a full-stack iOS demo app for a Vonage developer-blog tutorial titled "Behind the Scenes: Visualizing Silent Auth in an iOS App." The app authenticates a phone number silently (no visible code entry in the normal path) using Vonage Verify v2 with fallback order: silent_auth → sms → voice. A "Dev Mode" toggle reveals a live console of every API call, webhook, and device-side event, making the normally invisible flow visible for a tutorial audience.

Starting from a clean slate: no Vonage app credentials yet, physical test device available, voice fallback wanted.

**Doc discrepancy resolved:** AGENTS.md says `startCellularGetRequest`; current Vonage docs name the method `startCellularRequest(params:debug:)`. The plan uses the documented name.

---

## Task Breakdown (execute one task per prompt, in order)

### Task 1 — Repo scaffolding + secrets hygiene
- Create `.gitignore` excluding `.env`, `*.key`, `private.key`, `ios/Config.local.xcconfig`, `.DS_Store`, `node_modules/`, `.build/`, `xcuserdata/`
- Create `server/.env.example` with `VONAGE_APPLICATION_ID=`, `VONAGE_PRIVATE_KEY_PATH=./private.key`, `PORT=4000`, `NGROK_URL=`
- Create `server/package.json` with deps: `express`, `cors`, `dotenv`, `@vonage/auth`, `@vonage/verify2`, `@vonage/jwt` (for webhook signature validation); devDeps: `jest`, `supertest`, `nodemon`
- Create `tasks/todo.md` with the verbatim prompt at the top + the task checklist below it
- Create `tasks/archive/` placeholder (`.gitkeep`)
- Add a setup note in `README.md` about creating the Vonage application (dashboard.nexmo.com → Applications → Create, enable "Verify" + "Network Registry / Silent Auth" capability, download private key, set callback URL to `https://<ngrok-url>/callback`)

**Why .gitignore first:** secrets must be excluded before any other files are created, not retrofitted.

---

### Task 2 — Backend skeleton: Express server + Verify v2 integration
Files: `server/server.js`, `server/routes/verification.js`, `server/store.js`

- `store.js`: in-memory `Map<requestId, VerificationRecord>` where record shape is `{ requestId, phone, status, createdAt, updatedAt, checkUrl, logs: LogEvent[] }`. `LogEvent = { timestamp, source: "server"|"device", requestId, label, detail }`.
- `verification.js` routes:
  - `POST /verification` — calls `verifyClient.newRequest({ brand, workflow: [{channel:"silent_auth",to},{channel:"sms",to},{channel:"voice",to}] })`, stores record, returns `{ request_id, check_url }`. Logs the outgoing request params and Vonage response.
  - `POST /next` — calls `verifyClient.nextWorkflow(requestId)`, logs it.
  - `POST /check-code` — calls `verifyClient.checkCode(requestId, code)`, logs it, returns `{ verified, status }`.
  - `GET /health`
- `server.js`: wires middleware (cors, json, urlencoded) + routes.
- Add `// TODO: add rate limiting before production use` comment on the `/verification` route.
- Phone number redaction helper: `redactPhone(e164)` → `+1•••••1234` (country code + bullets + last 4).
- Code redaction: log only last 2 digits of any `code` value.

**Why separate `store.js`:** tests can import and reset it in isolation without spinning up Express.

---

### Task 3 — Webhook handler + log buffer
Files: `server/routes/webhook.js`, update `store.js`

- `POST /callback`: parse `type` field — handle both `"event"` and `"summary"` shapes (see webhook payload schemas from Vonage docs above).
  - For `"event"`: log `{ label: "webhook:event", detail: { channel, status, action? } }`.
  - For `"summary"`: log `{ label: "webhook:summary", detail: { status, workflow[] } }`; update the stored record's `status`.
  - Always respond 200 immediately (idempotent update).
- Webhook JWT validation: verify `Authorization` bearer token using `@vonage/jwt` `verifySignature`. Skip validation if `NODE_ENV=test`.
- `GET /logs/:request_id`: return the `logs[]` array for that request (for iOS polling or SSE).

**SSE vs. polling decision:** Use **polling** (`GET /logs/:request_id` every 1.5s from iOS). Rationale: SSE requires keeping a persistent HTTP connection open while the app is also making a cellular-forced request via `VGCellularRequestClient` (which uses a custom `URLSession` configuration). Polling avoids any interaction between the two network paths and is trivially resumable after backgrounding. The polling interval (1.5s) is fast enough for a live demo feel without being chatty. This decision will be recorded in `tasks/todo.md`.

---

### Task 4 — Backend tests
Files: `server/__tests__/verification.test.js`, `server/__tests__/webhook.test.js`, `server/__tests__/store.test.js`

- Mock `@vonage/verify2` and `@vonage/jwt` with Jest.
- `store.test.js`: CRUD operations, log append, idempotent status update.
- `verification.test.js` (supertest):
  - `POST /verification` happy path returns `{ request_id, check_url }`.
  - `POST /verification` missing phone → 400.
  - `POST /next` unknown requestId → 404.
  - `POST /check-code` verified → `{ verified: true }`, invalid code → `{ verified: false }`.
- `webhook.test.js`:
  - event callback updates log.
  - summary callback updates status.
  - unknown requestId still returns 200.

Run: `cd server && npm test`

---

### Task 5 — iOS project scaffold
Files: `ios/SilentAuthDemo.xcodeproj` (Xcode), `ios/SilentAuthDemo/` source tree

- Create Xcode project: SwiftUI app, iOS 16+, **`TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad)**, bundle ID `com.vonage.SilentAuthDemo`, no Core Data, no tests target yet (added manually next task).
- Add Swift package dependency: `https://github.com/Vonage/vonage-ios-client-library.git` (latest release, `VonageClientLibrary` product).
- Create `ios/Config.xcconfig` (committed, safe values only: `BASE_URL = http://localhost:4000`) and `ios/Config.local.xcconfig` (gitignored, overrides for ngrok URL).
- Folder structure inside `SilentAuthDemo/`:
  - `App/` — `SilentAuthDemoApp.swift`, `ContentView.swift`
  - `Features/Login/` — `LoginView.swift`, `LoginViewModel.swift`
  - `Features/Verified/` — `VerifiedView.swift`
  - `Features/DevMode/` — `DevConsoleView.swift`, `LogEventRow.swift`
  - `Networking/` — `APIClient.swift`, `CellularAuthClient.swift`
  - `Models/` — `LogEvent.swift`, `VerificationState.swift`

---

### Task 6 — iOS networking layer
Files: `Networking/APIClient.swift`, `Networking/CellularAuthClient.swift`

- `APIClient`: async/await wrapper around `URLSession`. Methods: `startVerification(phone:)→(requestId, checkUrl?)`, `nextWorkflow(requestId:)`, `checkCode(requestId:code:)→verified:Bool`, `fetchLogs(requestId:)→[LogEvent]`. Base URL read from `Config.xcconfig`.
- `CellularAuthClient`: wraps `VGCellularRequestClient`. Method: `performCellularCheck(checkUrl:)→String` (returns the `code` from the JSON response). Uses `startCellularRequest(params:debug:)` — note: current Vonage docs show this method name, not `startCellularGetRequest` as referenced in some older sources.
- Error types: `APIError` (network, server, decoding), `CellularAuthError` (noCheckUrl, networkFailed, parseError).

---

### Task 7 — iOS verification state machine + LoginViewModel
Files: `Models/VerificationState.swift`, `Features/Login/LoginViewModel.swift`

State enum:
```
idle → enteringPhone → awaitingSilentAuth → 
  ├─ silentAuthSucceeded → submittingCode → verified
  ├─ silentAuthFailed → enteringSmsCode
  │                          └─ submittingCode → verified
  └─ (no check_url) → enteringSmsCode
```
Voice fallback state: `enteringVoiceCode` (after SMS also fails/times out via `/next` again).

`LoginViewModel` (ObservableObject):
- `@Published var state: VerificationState`
- `@Published var devLogs: [LogEvent]`
- `@Published var devModeEnabled: Bool`
- `func submitPhone(_ phone: String)` — starts verification, appends device-side log events, kicks off cellular check if `checkUrl` present, starts polling loop for `devLogs`.
- `func triggerFallback()` — calls `/next`, transitions state.
- `func submitCode(_ code: String)` — calls `/check-code`.
- Polling: `Task` loop every 1.5s fetching `/logs/:request_id`, merging with device-side events (device events are prepended/merged by timestamp, not duplicated).

**State machine design note:** The state machine is a value-type enum rather than a class hierarchy because all transitions are explicit and exhaustible — a `switch` in the ViewModel covers every case with compile-time exhaustiveness, which matters for a tutorial where readers need to trace the full flow.

---

### Task 8 — iOS UI: LoginView + VerifiedView (iPhone + iPad)
Files: `Features/Login/LoginView.swift`, `Features/Verified/VerifiedView.swift`

- `LoginView`: phone number text field (E.164 format hint), "Sign In" button, `Toggle("Dev Mode", isOn: $viewModel.devModeEnabled)`, state-driven UI (spinner for `awaitingSilentAuth`, SMS code entry for `enteringSmsCode`, voice code entry for `enteringVoiceCode`).
- **Adaptive layout:** wrap content in a `frame(maxWidth: 440)` centered container so it looks intentional on iPad's wider canvas, not just stretched. Use `@Environment(\.horizontalSizeClass)` where layout decisions differ.
- `VerifiedView`: success state, "Sign Out" button that resets to idle.
- Layouts verified on iPhone SE (375pt), iPhone 15 (390pt), and iPad (768pt+) via SwiftUI Previews — no clipped text, no overlapping controls.
- Dev console presentation adapts by size class: on iPhone it slides up as a `.sheet`; on iPad it appears as a trailing side panel (see Task 9).

---

### Task 9 — iOS Dev Mode console (adaptive: sheet on iPhone, side panel on iPad)
Files: `Features/DevMode/DevConsoleView.swift`, `Features/DevMode/LogEventRow.swift`

- `DevConsoleView`: `ScrollView` + `LazyVStack` of `LogEventRow`, auto-scrolls to newest entry, timestamp + source badge (server = blue, device = green) + label + detail.
- `LogEventRow`: renders one `LogEvent`. Phone numbers redacted. Codes show last 2 digits only.
- **iPhone:** presented as a `.sheet` with `.presentationDetents([.medium, .large])` — slides up over the login screen, dismissible.
- **iPad (regular horizontal size class):** presented inline as a trailing side panel — `HStack { LoginContent(); Divider(); DevConsoleView() }` — both panes visible simultaneously, no sheet. This is the more useful layout for a live demo on iPad.
- Size class check at the `ContentView` / `LoginView` level using `@Environment(\.horizontalSizeClass)`.

**iPad layout design note:** Showing the login form and Dev Mode console side-by-side on iPad is deliberate — a presenter can keep the app on screen while the audience reads the log panel, without dismissing anything. This is a presentation-context decision, not just a layout nicety.

---

### Task 10 — iOS XCTest: state machine + log formatting
Files: `ios/SilentAuthDemoTests/VerificationStateTests.swift`, `ios/SilentAuthDemoTests/LogRedactionTests.swift`

- Every state transition gets a test: idle→enteringPhone, enteringPhone→awaitingSilentAuth, awaitingSilentAuth→silentAuthSucceeded, silentAuthSucceeded→verified, awaitingSilentAuth→enteringSmsCode (no check_url path), awaitingSilentAuth→enteringSmsCode (cellular failed path), enteringSmsCode→verified, enteringSmsCode→enteringVoiceCode (after `/next`), enteringVoiceCode→verified.
- `LogRedactionTests`: phone redaction (`+14155551234` → `+1•••••1234`), code redaction (only last 2 digits logged).

Run: `xcodebuild test -project ios/SilentAuthDemo.xcodeproj -scheme SilentAuthDemo -destination 'platform=iOS Simulator,name=iPhone 15'`

---

### Task 11 — Fallback flows + voice wiring
- Ensure voice fallback path in state machine is exercised: after SMS `enteringSmsCode`, user can tap "Didn't get it?" → calls `/next` again → `enteringVoiceCode`.
- UI: voice code entry view with appropriate label ("Check your phone — we're calling you now").
- Backend: `/next` works for both silent_auth→sms and sms→voice transitions (no change needed — `nextWorkflow` is generic).
- Test: state machine test for sms→voice transition.

---

### Task 12 — Polish + done checklist
- Run `npm test` — all pass.
- Run `xcodebuild test` — all pass.
- Verify SwiftUI Previews on iPhone SE (375pt), iPhone 14/15 (390pt), and iPad (768pt+) — no UI issues.
- Verify `.gitignore` excludes all secrets before any `git add`.
- Move `tasks/todo.md` to `tasks/archive/YYYY-MM-DD-initial-build.md`.

---

## Critical files to create (none exist yet)

- `server/server.js`, `server/routes/verification.js`, `server/routes/webhook.js`, `server/store.js`
- `server/__tests__/*.test.js`
- `ios/SilentAuthDemo.xcodeproj` + full SwiftUI source tree
- `.gitignore`, `server/.env.example`, `tasks/todo.md`

## Key reuse / library facts

- Backend auth: `@vonage/auth` + `@vonage/verify2` (JWT auth, not API key/secret)
- iOS cellular: `VGCellularRequestClient.startCellularRequest(params:debug:)` from `https://github.com/Vonage/vonage-ios-client-library.git`
- Testing: `+990` numbers with virtual operator (even last digit = completed, odd = rejected, `99` = failed)
- Sandbox mode (`sandbox: true`) is **retired** — do not use

## Verification

1. `cd server && npm install && npm test` — all 3 test suites pass
2. `cd server && npm run dev` + `ngrok http 4000` — update Vonage dashboard callback URL
3. `xcodebuild test -project ios/SilentAuthDemo.xcodeproj -scheme SilentAuthDemo -destination 'platform=iOS Simulator,name=iPhone 15'` — all tests pass
4. On simulator with `+99012345670` (even last digit) — verify full silent auth flow completes, Dev Mode shows server + webhook log events
5. On physical device — verify cellular `check_url` path works end-to-end