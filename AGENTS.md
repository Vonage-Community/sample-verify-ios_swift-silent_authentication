# AGENTS.md

## What this project is

A reference app demonstrating **invisible login** on iOS using the Vonage Verify v2 API: Silent Authentication as the primary factor, with automatic SMS and voice fallback when Silent Auth isn't available or doesn't complete. A "Dev Mode" toggle on the login screen reveals a live console of every request, response, and webhook involved in the flow — the point of the app is to make an otherwise invisible auth flow visible, for a developer-blog tutorial and its accompanying sample repo.

One repo, two halves:

```
.
├── AGENTS.md
├── CLAUDE.md            # imports AGENTS.md — see note below
├── server/              # Node.js + Express backend, talks to Vonage Verify v2
│   ├── server.js
│   ├── package.json
│   └── .env.example
├── ios/                 # SwiftUI app, single Xcode project
│   └── SilentAuthDemo.xcodeproj
├── tasks/
│   ├── todo.md
│   └── archive/
└── README.md
```

This is a **public** demo repo for a tutorial. Code clarity and comments matter as much as correctness — write it the way you'd want a reader learning Verify v2 for the first time to find it.

> **Note on this file:** Claude Code reads `CLAUDE.md`, not `AGENTS.md`, natively. `CLAUDE.md` in this repo is a one-line `@AGENTS.md` import so both this file and Claude Code's memory system stay in sync — edit `AGENTS.md`, not `CLAUDE.md`.

## Vonage Verify v2 / Silent Auth facts — don't relitigate these

Settled by checking current Vonage docs. If something here looks wrong mid-task, check developer.vonage.com (or the Vonage Docs MCP, if connected) before changing approach — don't silently "fix" it from memory, since several of these changed recently:

- **Auth**: Verify v2 uses JWT auth via an Application ID + private key (`@vonage/auth` + `@vonage/verify2`), not classic API key/secret. The Vonage application needs Silent Auth / Network Registry capability enabled in the dashboard.
- **Workflow order**: `silent_auth` must be the *first* step in the `workflow` array passed to `newRequest()`. It can't be used as a fallback for another channel. Typical shape: `[{channel: "silent_auth", to}, {channel: "sms", to}, {channel: "voice", to}]`.
- **`check_url` is the core trick**: if Vonage's coverage check passes, `newRequest()` returns a `check_url`. The *device*, not the server, must `GET` that URL **over cellular data, never Wi-Fi**. On iOS, use Vonage's **`VonageClientLibrary`** Swift package (`VGCellularRequestClient` / `startCellularGetRequest(params:debug:)`), which forces the request over the cellular interface even when Wi-Fi is active. Note: the Vonage blog refers to this as `startCellularRequest` but the actual method name in v1.0.5 source is `startCellularGetRequest` — always verify against the checked-out source in DerivedData.
  - Do **not** use `VonageClientSDKSilentAuth` / `VGSilentAuthClient` or `VonageClientSDKNumberVerification` — both are archived and deprecated in favor of `VonageClientLibrary` (`github.com/Vonage/vonage-ios-client-library`).
- **Completing the flow**: a successful `check_url` response body contains a `code` field. The client sends `{request_id, code}` to the backend, which calls `verifyClient.checkCode(requestId, code)`; a `"completed"` status means the user is verified.
- **Forcing fallback**: if there's no `check_url`, or the cellular request fails/errors, call the backend's `next` endpoint, which calls `verifyClient.nextWorkflow(requestId)` to skip straight to SMS instead of waiting for Silent Auth to time out.
- **Testing without a real SIM**: the old `sandbox: true` request parameter is **retired** (returns 422 now). Use the **Network Registry Playground** + **Virtual Operator** instead: in Playground mode, any `to` number starting with `+990` routes to a virtual operator, and the outcome depends on the last digit — even = `completed`, odd = `user_rejected`, ending in `99` = `failed`. This covers backend logic and simulator testing; a real device on cellular data is still needed to exercise the actual on-device `check_url` round trip.
- **Webhooks**: the app's Verify callback URL should point at `https://<public-url>/callback`. Vonage signs webhooks with a JWT in the `Authorization` header. Always respond `200`/`204` quickly and treat delivery as **at-least-once** (idempotent updates only). Two payload shapes matter for logging: per-channel **event** callbacks (`type: "event"`) and the overall **summary** callback (`type: "summary"`, includes the full `workflow` array with each channel's status) — the summary is the more useful one for Dev Mode's "final state" view.
- **Secrets**: `VONAGE_APPLICATION_ID` and the private key file path live in `server/.env` (see `.env.example`), never committed. `.gitignore` must exclude `.env`, `*.key`, and any local iOS config (e.g. `ios/Config.local.xcconfig`) before those files are ever created — set this up in the very first task, not as an afterthought.

## Workflow

- Plan first. Write a checklist to `tasks/todo.md` before coding.
- Start every `tasks/todo.md` with the exact prompt that produced it, verbatim — what I actually typed, not a summary or paraphrase of it — before the checklist itself (template below). That block travels with the file into `tasks/archive/` when the plan is done; never strip it during cleanup.
- **Before archiving a completed `tasks/todo.md`**, add a "Blog-worthy notes" section documenting any non-obvious technical decisions, trade-offs, or gotchas discovered while implementing. These notes are pulled into the behind-the-scenes blog post. Include: why a choice was made over alternatives, sharp edges or surprising behavior encountered, and patterns that might help someone else doing similar work.
- One task per prompt. One concern per diff.
- Read relevant files before editing.
- Keep diffs small and reviewable.
- Prefer files under 300 lines.
- If a file grows past 300 lines, consider splitting by responsibility.
- Do not split files only to satisfy line count; keep cohesive code together.

**`tasks/todo.md` template:**

```markdown
## Prompt

<verbatim prompt text — exactly what I typed, not a summary>

## Checklist

- [ ] ...
```

## Testing

- No behavior change without a test.
- Add or update tests for every feature, bug fix, API contract change, and state transition.
- Run the relevant test first when fixing a bug, then make it pass.

Project-specific defaults (adjust during planning if there's a good reason):

- `server/`: tests mock the Vonage SDK calls — never hit the real Verify API from automated tests.
- `ios/`: XCTest for the verification state machine and log-formatting logic. Since nothing is watching the simulator in an agent loop, `xcodebuild test` (not a human eyeballing the preview) is what proves a change works — prioritize logic/unit tests over UI tests that need visual judgment.
- Every transition in the verification state machine (e.g. `enteringPhone → awaitingSilentAuth → enteringSmsCode → verified`) gets a test on whichever side owns that transition.

## Dev Mode logging

- Every Verify API call, webhook delivery, and `check_url` attempt produces one structured log event: `{ timestamp, source: "server" | "device", requestId, label, detail }`.
- The server keeps a per-`requestId` log buffer and exposes it to the client; the client appends its own device-side events (e.g. "Calling check_url over cellular…") so Dev Mode renders one merged timeline, not two separate logs. **Transport: polling** (`GET /logs/:request_id` every 1.5s from iOS). SSE was ruled out because it requires a persistent HTTP connection open simultaneously with `VGCellularRequestClient`'s custom `URLSession` configuration — polling avoids that interaction and resumes cleanly after backgrounding.
- Redact sensitive values in anything that might end up in a screenshot or screen recording for the blog post: show phone numbers as `+1•••••1234` (last 4 digits) and never log a full OTP/Silent-Auth code — the last 2 digits is enough to prove it worked.
- Dev Mode is a runtime toggle on the login screen, not a build flag: the server always captures logs; Dev Mode only controls whether the iOS app *displays* the console.

## Done means

- Plan completed and checked off.
- Tests added or updated for behavior changes.
- iOS layouts verified on iPhone SE (375pt), a standard iPhone width (390pt — iPhone 14/15/16), and iPad (768pt+) — no clipped text, no overlapping controls — checked via SwiftUI Previews and/or Simulator, not assumed. The app targets `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad); on iPad the Dev Mode console renders as a side panel rather than a sheet.
- Completed plan moved from `tasks/todo.md` to `tasks/archive/` and renamed with date + feature name.

## Commands

- Backend: `cd server && npm install && npm test && npm run dev`
- iOS build/test from the CLI: `xcodebuild test -project ios/SilentAuthDemo.xcodeproj -scheme SilentAuthDemo -destination 'platform=iOS Simulator,name=iPhone 15'`
- Exposing the local backend for Vonage webhooks during development: `ngrok http <port>`, then update the callback URL in the Vonage Dashboard.

## Out of scope — don't gold-plate

- No real user accounts, sessions, or persistent database. An in-memory store on the server is intentional and matches the educational scope of this repo.
- No production-grade rate limiting or abuse protection on the start-verification endpoint — leave a `// TODO` comment, don't build it.
- No Android client. If asked to add one later, it's a new feature with its own plan in `tasks/todo.md`, not a tack-on to an existing task.
