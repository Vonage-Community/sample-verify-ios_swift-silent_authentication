# Behind the Scenes: Visualizing Silent Auth in an iOS App

*In this tutorial, you'll build an iOS login that verifies a phone number with zero user input — and a Dev Mode console that shows every invisible step as it happens.*

## Introduction

Your users hate one-time passcodes.

They wait for the text. They switch apps. They mistype the code. Some of them get phished, because any code a human can read, a human can be tricked into forwarding.

Silent Authentication fixes this: the phone number is verified by the carrier network itself, using the SIM card already in the device. No SMS. No code. No user action. The user taps "Sign in" and they're in.

But here's the catch for developers: **the whole flow is invisible**. When it works, you see nothing. When it fails, you also see nothing — did the coverage check fail? Did the device go over Wi-Fi instead of cellular? Did the carrier reject it? Did the fallback SMS fire? You're debugging a black box.

So we built a demo app that turns the black box inside out. It's a SwiftUI login screen backed by the Vonage Verify v2 API, with Silent Auth as the primary factor and automatic SMS and voice fallback. And it has a **Dev Mode** toggle: flip it, and the app renders a live, merged timeline of every API call the server makes, every webhook Vonage delivers, and every cellular request the device fires — grouped by channel, with plain-English notes explaining each hop.

***>> TL;DR:*** *Skip ahead and find the [quickstart and app code on GitHub](https://github.com/Vonage-Community/sample-verify-ios_swift-silent_authentication).*

## Prerequisites

Before you get started, make sure you have:

- macOS with [Xcode 15+](https://developer.apple.com/xcode/)
- [Node.js 20+](https://nodejs.org/en/download)
- [ngrok](https://ngrok.com) (to expose your local backend to Vonage webhooks)
- An iPhone with a SIM and cellular data — for the real Silent Auth path (the simulator works for everything else via test numbers)

### Vonage API Account

To complete this tutorial, you will need a [Vonage API account](https://developer.vonage.com/sign-up). If you don't have one already, you can sign up today and start building with free credit.

You'll also need a Vonage **Application** with the **Verify** and **Network Registry** capabilities enabled — Network Registry is what unlocks Silent Authentication. The [repo README](https://github.com/Vonage-Community/sample-verify-ios_swift-silent_authentication#quick-start-10-minutes) walks through creating one.

## How Silent Auth Works

The trick at the heart of Silent Auth is a URL.

When your backend starts a verification with `silent_auth` as the first workflow step, Vonage runs a coverage check on the phone number. If the carrier supports it, the API response includes a `check_url`. Then comes the part that surprises everyone the first time:

**The device — not your server — must fetch that URL, and it must do it over cellular data, never Wi-Fi.**

That's the whole mechanism. The mobile network identifies the SIM from the connection itself, the same way it knows which phone to bill. If the SIM matches the number being verified, the response contains a `code`, the app sends it to your backend, and the backend completes the verification. The user saw a spinner for two seconds.

### How the System Flows

Here's what happens when a user taps "Sign in":

1. The app sends the phone number to your backend
2. The backend calls Verify v2 with a workflow of `[silent_auth, sms, voice]` — Silent Auth **must** be first; it can't be a fallback for another channel
3. Vonage returns a `request_id` and (if the coverage check passed) a `check_url`
4. The app fetches the `check_url` **over the cellular interface**, using Vonage's iOS client library — even if the phone is on Wi-Fi
5. The response contains a `code`; the app posts it to the backend, which calls `checkCode`
6. If anything fails along the way — no `check_url`, cellular error, carrier rejection — the app tells the backend to advance the workflow, and Vonage sends an SMS instead
7. If the SMS also goes unanswered, Vonage falls back again and *calls* the user with a spoken code

Meanwhile, every one of those steps emits a structured log event to a per-request buffer on the server. The app polls that buffer every 1.5 seconds and merges the server's events with its own device-side events into one timeline. That's Dev Mode.

### How It's Put Together

1. **The Server** ([server/](https://github.com/Vonage-Community/sample-verify-ios_swift-silent_authentication/tree/main/server))

   A small Express app that owns all Vonage credentials and API calls. It exposes four endpoints the app cares about — start a verification, advance the workflow, check a code, and fetch logs — plus a `/callback` route for Vonage's webhooks. It authenticates to Verify v2 with an Application ID + private key JWT (Verify v2 doesn't use the classic API key/secret pair). It also runs a *channel-timeout mirror* — more on that scar tissue below.

2. **The iOS App** ([ios/](https://github.com/Vonage-Community/sample-verify-ios_swift-silent_authentication/tree/main/ios))

   SwiftUI, iOS 16+, iPhone and iPad. The verification flow is a value-type state machine — an enum whose cases (`awaitingSilentAuth`, `enteringSmsCode`, `enteringVoiceCode`, `verified`…) carry the `request_id` as an associated value, so the state *is* the request context. The cellular request uses `VGCellularRequestClient` from Vonage's [iOS client library](https://github.com/Vonage/vonage-ios-client-library), which forces the request over the cellular interface even when Wi-Fi is active. The Dev Mode console groups the merged log timeline by channel — Silent Auth, SMS, Voice — with a tracker pill showing which channel is live.

3. **Data Safety**

   Anything that could end up in a screenshot is redacted at *write* time, not display time: phone numbers show as `+14•••••1234` (last four digits), and codes never log more than their last two digits — enough to prove the flow worked, useless to an attacker. Because redaction happens when the log event is created, exports and screen recordings are safe by default.

## Run It in 10 Minutes

### Step 1: Create the Vonage Application

In the [Vonage Dashboard](https://dashboard.nexmo.com/applications), create an application, enable **Verify** and **Network Registry**, generate a key pair, and save `private.key` into `server/` (it's gitignored).

### Step 2: Start the Backend

```bash
cd server
cp .env.example .env   # fill in VONAGE_APPLICATION_ID
npm install
npm run dev
```

### Step 3: Expose It to Webhooks

```bash
ngrok http 4000
```

Copy the HTTPS URL into your Vonage application's Verify **callback URL** as `https://<your-ngrok-id>.ngrok.io/callback`.

### Step 4: Run the App

Open `ios/SilentAuthDemo.xcodeproj`, copy `ios/Config.xcconfig` to `ios/Config.local.xcconfig`, set `BASE_URL` to your ngrok URL, and hit **Cmd+R**.

## Run Your First Verification

Enable the **Dev Mode** toggle on the login screen, enter a number, and tap **Sign in**. The console takes over the screen and narrates the flow live.

### Testing Without a Real SIM

You don't need to burn real SMS credits (or a real SIM) to exercise the flow. Vonage's **Network Registry Playground** routes any number starting with `+990` to a virtual operator, and the last digit scripts the outcome:

| Number ends in | Silent Auth outcome |
|----------------|---------------------|
| even digit     | `completed` — verified instantly |
| odd digit      | `user_rejected` — falls back to SMS |
| `99`           | `failed` — falls back to SMS |

So `+99012345670` demos the happy path on a simulator, and `+99012345671` demos the fallback cascade. (If you remember the old `sandbox: true` request parameter — it's retired and now returns a 422. The playground replaced it.)

The one thing the playground can't fake is the on-device cellular round trip. For that you need a physical iPhone on cellular data with a supported carrier.

### What You'll See

- **A channel tracker** pinned at the top — `SILENT AUTH · SMS · VOICE` — that fills in as each channel is tried: the active one highlighted, failed ones crossed out, the winner checked
- **Stage-grouped events**, each with a plain-English note first ("Fetching the check_url over the cellular interface — the network identifies the SIM from the connection itself…") and the machine label underneath
- **Source badges** distinguishing what the *server* did from what the *device* did — the whole point of the merged timeline
- **The summary webhook** at the end, which is quietly the best teaching moment in the entire flow: on a Silent Auth success it reads `silent_auth: completed, sms: unused, voice: unused`. Those "unused" entries are every code your user didn't have to type.

## How It Was Built

This app was built with Claude Code, working from an `AGENTS.md` that encoded the workflow: plan every task into a checklist first, write tests before finishing, and — the rule that made this post possible — append "blog-worthy notes" to every completed plan before archiving it. What follows is distilled from those notes. Like any real build, it wasn't linear.

### 1. Scaffolding Against the Docs, Not Memory

The first hazard with AI-assisted coding on a fast-moving API is stale training data, and Silent Auth has moved recently. Three things the agent would have gotten wrong from memory, caught by checking current docs (via the Vonage Docs MCP server) up front:

- The older `VGSilentAuthClient` and Number Verification SDKs are **archived** — the current path is the unified `VonageClientLibrary` package
- Even Vonage's own blog refers to the method as `startCellularRequest`, but the actual method in the shipped library is `startCellularGetRequest` — we verified against the checked-out package source rather than any prose
- `sandbox: true` is retired; the `+990` playground replaced it

We wrote all of these into `AGENTS.md` as "settled facts — don't relitigate", so no later session could helpfully "fix" them backwards.

### 2. Getting It Running

Two gotchas from this phase earned their place in the notes:

**The xcconfig comment bug.** The app kept requesting `http://verification/` instead of the backend. The cause: in `.xcconfig` files, `//` starts a comment — *anywhere on the line*. So `BASE_URL = http://localhost:4000` silently truncates to `http:`. The fix is a classic Xcode incantation:

```
_SLASH = /
BASE_URL = http:$(_SLASH)/localhost:4000
```

**The playground is stricter than production.** Sending the full three-channel workflow with a `+990` number returns a 422: with a virtual operator, `silent_auth` must be the *only* channel (the fake number can't receive real SMS). The server now detects the prefix and adjusts the workflow — a small fork, but the kind that costs an hour when the error message is just "phone number is invalid."

### 3. Debugging: The Workflow Advances Without Asking You

The sharpest lesson of the whole project, and it only surfaces on a real device.

We had modeled channel progression as app-driven: the user taps "Didn't get it?", the app calls `/next`, the workflow advances. Clean. Wrong. Verify v2 workflows **auto-advance on channel timeout**. If the user just waits on the SMS screen, Vonage expires the SMS channel and places the voice call *on its own* — no `/next`, no app involvement. In our first real-device test, the phone rang while every label in the app still said "SMS."

Fine, we thought — we'll listen for the webhook that says the SMS channel expired. So we wired that up, tested again, and watched **six minutes of total silence**: no webhooks between the fallback and the final summary. It turns out mid-flow event callbacks exist only for Silent Auth and WhatsApp; SMS and voice outcomes surface *only* in the end-of-request summary, after everything is over. You cannot webhook your way out of this one.

The workable answer came from noticing who controls the clock: `channel_timeout` is a parameter *we* set on the request, so the server knows Vonage's schedule exactly. When a channel starts, the server arms a local timer for `channel_timeout + 5 seconds` of grace; if the request is still pending on that channel when it fires, the server advances its own record and logs the hop — the same move Vonage just made silently on its side. The grace period guarantees our clock fires *after* theirs, so the UI never gets ahead of reality. The app picks the change up on its next poll and switches screens.

Channel progression now has three drivers — user tap, webhook (if one ever comes), and the timeout mirror — and all three funnel through the same forward-only, same-channel-guarded advancement, so any combination firing in any order converges on the same state. That guard matters because webhooks are at-least-once and unordered: a late duplicate `sms` event must never drag the state backward from `voice`.

Two smaller finds from this phase worth stealing:

- **The anti-MITM check the docs bury:** the `check_url` response echoes the `request_id`; you're supposed to compare it against the original and abort on mismatch. Everything works if you skip it, which is exactly why everyone skips it. It's three lines. The app logs it as `silent_auth:integrity_check passed` so the console makes the security step visible too.
- **A `.env` file can silently break your test mocks.** Server tests inject a mock Verify client, but the server wired the *real* client whenever credentials existed — overwriting the mock. Tests passed for weeks, right up until we created a real `.env` to run the app, and seven of them failed. "Tests never hit the real API" has to be enforced in the app wiring, not just the test setup.

### 4. Iterating on the UX

With the data flowing correctly, the console itself went through two redesigns driven by actually using it:

- **The sheet that blocked the demo.** Dev Mode originally opened as a bottom sheet — which covered the Sign In button. The console you open *before* signing in prevented signing in. It's now a full-screen takeover that appears only after the form is submitted.
- **"STEP 2/5" three times in a row.** Early on, every log event carried a step badge. But a merged device+server timeline has several events per phase, so the same step number kept repeating — *correct*, yet it read as broken. The real question a viewer has isn't "what step is this?" but "**which channel am I on?**" — so the redesign made the channel the primary visual unit: a tracker pill for the at-a-glance answer, stage headers for the scroll-through answer, and no per-event numbering at all. When a progress indicator feels noisy, check whether you're numbering events when you should be grouping by phase.
- **Making the fallback demoable.** The default channel timeout is 300 seconds — a five-minute wait to show SMS→voice live on stage. Since the server sets the value, the demo default is 60 seconds: the full silent_auth → sms → voice cascade fits inside two minutes, with the mirrored timer narrating each hop in the console as it happens.
- **Vonage-ifying without the logo.** The brand guidelines restrict the logo to provided assets with approval, so the app brands through palette and type alone — and the channel colors (Silent Auth purple, SMS magenta, voice orange) double as the timeline's legend.

## Conclusion

Silent Auth's greatest strength — the user sees nothing — is exactly what makes it hard to build confidently. A live console that narrates the flow turned out to be more than a demo gimmick: it's how we *found* the auto-advance behavior, the missing webhooks, and the timeout mechanics described above. If you're integrating Verify v2, consider keeping a per-request log buffer even if you never ship a UI for it.

Ideas for extending the sample:

- **WhatsApp channel** — Verify v2 supports WhatsApp in the workflow; slot it between SMS and voice
- **Persist verified sessions** — the demo intentionally forgets everything; add Keychain-backed sessions
- **Android client** — the same backend serves any client that can make a cellular-forced request
- **Push the timeline further** — export the merged log as JSON for bug reports, or replay a stored timeline in the console

The full source code is available on [GitHub](https://github.com/Vonage-Community/sample-verify-ios_swift-silent_authentication). Fork it, run the cascade, and let us know what you build!

Have a question or want to share what you're building?

- Subscribe to the [Developer Newsletter](https://developer.vonage.com/en/newsletter)
- Follow us on [X (formerly Twitter)](https://vonage.dev/TwitterBlog) for updates
- Watch tutorials on our [YouTube channel](https://vonage.dev/YouTubeBlog)
- Connect with us on the [Vonage Developer page on LinkedIn](https://vonage.dev/LinkedinBlog)

Stay connected and keep up with the latest developer news, tips, and events.
