## Prompt

I want to build a demo iOS app for a Vonage developer-blog tutorial called
"Behind the Scenes: Visualizing Silent Auth in an iOS App." Read AGENTS.md
and CLAUDE.md first — AGENTS.md has settled facts about the Vonage Verify v2
/ Silent Auth API and the workflow rules I want for this whole project, and
I want you to follow them.

## What we're building

An iOS login screen that authenticates a phone number using Vonage Verify
v2, with this fallback order: Silent Authentication first, then SMS, then
voice as a last resort. In the normal case the user just enters their phone
number and is logged in within a couple of seconds — nothing visibly
"auth-y" happens. There's a "Dev Mode" toggle on the login screen (off by
default) that replaces the plain loading/success state with a live console
showing every request, response, and webhook involved: starting the Verify
request, the on-device cellular check_url call, the webhook callback the
backend received, the fallback to SMS if that's what happened, and so on.
The whole point of Dev Mode is to make an invisible auth flow visible for a
demo audience.

## Architecture

- `server/` — Node.js + Express backend. There's a reference implementation
  at `reference/kotlin-demo-server.js` (from
  https://github.com/Vonage-Community/demo-verify-kotlin-node-2fa) — use it
  to understand the shape of the flow (`/verification`, `/callback`,
  `/status/:request_id`, `/check-code`, `/next`), not as code to copy
  verbatim. We'll likely want richer logging for Dev Mode than that
  reference has.
- `ios/` — Native SwiftUI app, single Xcode project, iOS 16+. Use Vonage's
  `VonageClientLibrary` Swift package (not the deprecated
  `VonageClientSDKSilentAuth`) for the cellular-forced check_url call — see
  AGENTS.md for why.
- Use the Vonage Docs MCP server for anything you're not certain about,
  especially Verify v2 request/response shapes, webhook payloads, or the
  iOS client library's exact API — some of this changed recently (SDK
  rename, sandbox-parameter retirement) so don't rely on training data
  alone.

## Before you write any code

1. Skim the Vonage docs (via MCP) for Verify v2 + Silent Auth and confirm
   the request/response shapes, webhook payloads, and iOS client library
   usage match what's in AGENTS.md. Flag anything that's drifted.
2. Ask me what you need to about: whether I already have a Vonage
   Application ID + private key with Silent Auth / Network Registry
   enabled (or whether we need to set that up first), whether I want voice
   fallback actually wired up for the demo or just SMS, and any
   constraints on minimum iOS version or test devices.
3. Per AGENTS.md, write the plan to `tasks/todo.md` before writing any
   code. Break it into small, single-concern tasks — something like: repo
   scaffolding + .gitignore → backend skeleton + Verify integration →
   webhook handling → Dev Mode log buffer/transport → iOS networking layer
   → iOS state machine + UI → Dev Mode console → fallback flows → tests →
   polish. I'll review and approve the plan before you start executing it.

## One more thing — this is also blog content

I'm writing a "behind the scenes" post about building this with you,
including some of the prompts I used and the decisions you made. When you
make a non-obvious technical call (e.g., SSE vs. polling for the Dev Mode
log stream, how you're handling "silent auth fails fast" vs. "silent auth
times out", how you structured the iOS state machine), say so explicitly
and briefly explain why — a sentence or two is plenty. I'll pull some of
those into the writeup.

---

## Decisions recorded

- **SSE vs. polling for Dev Mode logs:** Using polling (`GET /logs/:request_id` every 1.5s). SSE would require keeping a persistent HTTP connection open alongside the cellular-forced `VGCellularRequestClient` request (which uses a custom `URLSession` config). Polling avoids any interaction between those two network paths and resumes cleanly after backgrounding.
- **iOS state machine as value-type enum:** All transitions are explicit and exhaustible — `switch` in the ViewModel gives compile-time exhaustiveness, which makes the flow easy to trace for tutorial readers.
- **iPad Dev Mode layout:** Side-by-side panel (login form + console visible simultaneously) rather than a sheet, so a presenter can demo without dismissing anything.
- **Doc discrepancy:** AGENTS.md references `startCellularGetRequest`; current Vonage docs name the method `startCellularRequest(params:debug:)`. Using the documented name.

---

## Checklist

### Task 1 — Repo scaffolding + secrets hygiene
- [x] Create `.gitignore` (secrets, node_modules, Xcode build artifacts)
- [x] Create `server/.env.example`
- [x] Create `server/package.json` with deps + devDeps
- [x] Create `tasks/todo.md` (this file)
- [x] Create `tasks/archive/.gitkeep`
- [x] Add Vonage app setup notes to `README.md`

### Task 2 — Backend skeleton: Express server + Verify v2 integration
- [ ] `server/store.js` — in-memory store + `LogEvent` shape
- [ ] `server/routes/verification.js` — `/verification`, `/next`, `/check-code`, `/health`
- [ ] `server/server.js` — middleware + route wiring
- [ ] Phone/code redaction helpers

### Task 3 — Webhook handler + log buffer
- [x] `server/routes/webhook.js` — `POST /callback` (event + summary), `GET /logs/:request_id`
- [x] Webhook JWT validation (skip in test env)
- [x] Store idempotent status updates

### Task 4 — Backend tests
- [x] `server/__tests__/store.test.js`
- [x] `server/__tests__/verification.test.js`
- [x] `server/__tests__/webhook.test.js`
- [x] `cd server && npm test` passes (36 tests, 3 suites)

### Task 5 — iOS project scaffold
- [ ] Xcode project (iOS 16+, iPhone + iPad target)
- [ ] VonageClientLibrary Swift package added
- [ ] Config.xcconfig + Config.local.xcconfig (gitignored)
- [ ] Folder structure: App/, Features/, Networking/, Models/

### Task 6 — iOS networking layer
- [ ] `Networking/APIClient.swift`
- [ ] `Networking/CellularAuthClient.swift` (wraps VGCellularRequestClient)
- [ ] Error types

### Task 7 — iOS verification state machine + LoginViewModel
- [ ] `Models/VerificationState.swift` (enum with all states)
- [ ] `Features/Login/LoginViewModel.swift` (ObservableObject, polling loop)

### Task 8 — iOS UI: LoginView + VerifiedView
- [ ] `Features/Login/LoginView.swift` (adaptive, maxWidth 440 on iPad)
- [ ] `Features/Verified/VerifiedView.swift`
- [ ] Verified on iPhone SE (375pt), iPhone 15 (390pt), iPad (768pt+)

### Task 9 — iOS Dev Mode console
- [ ] `Features/DevMode/DevConsoleView.swift` (sheet on iPhone, side panel on iPad)
- [ ] `Features/DevMode/LogEventRow.swift`

### Task 10 — iOS XCTest: state machine + log formatting
- [ ] `VerificationStateTests.swift` (all transitions)
- [ ] `LogRedactionTests.swift`
- [ ] `xcodebuild test` passes

### Task 11 — Fallback flows + voice wiring
- [ ] Voice fallback UI ("Didn't get it?" → `/next` → enteringVoiceCode)
- [ ] State machine test for sms→voice transition

### Task 12 — Polish + done checklist
- [ ] All tests pass (server + iOS)
- [ ] SwiftUI Previews verified all screen sizes
- [ ] Archive `tasks/todo.md` → `tasks/archive/2026-06-22-initial-build.md`
