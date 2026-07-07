## Prompt

hmm, for some reason its still not having the correct behaviour when it transitions from sms to voice. In this flow, I actually authenticated over voice and and not sms. But there was no logging of the voice behaviour

## Diagnosis

Vonage's Verify v2 workflow **auto-advances channels on timeout**, independent of the app. In the reported flow: silent_auth failed → app called /next → sms. The SMS then timed out, and Vonage *on its own* advanced to the voice channel and placed a call (workflow was [silent_auth, sms, voice]). The user entered the voice code, and it verified.

But channel progression is tracked in two places that only advance on an explicit app-initiated `/next` call:
- **Backend `record.channel`** — stayed `sms`, so `verification:completed` labeled it the SMS channel and step totals stayed /5.
- **App `path`** — stayed `.sms`, so device logs read `STEP 4/5`, `STEP 5/5`, "Verified via the SMS channel".

Neither reacted to the voice call because the app never tapped "Didn't get it?" — Vonage advanced by timeout. **Webhooks are the real source of truth for which channel is active**, and we log them but don't act on them.

## Design: webhooks drive channel progression

Make the webhook `event` callback authoritative for the active channel. The backend advances `record.channel` (forward-only, in workflow order silent_auth→sms→voice) whenever a webhook reports a later channel. The `/logs` endpoint exposes the current channel; the app reconciles its `path`/`state` from it during polling.

## Checklist

### Backend
- [ ] `store.js`: add forward-only `advanceChannelTo(requestId, channel)` (silent_auth=0, sms=1, voice=2; never moves backward)
- [ ] `webhook.js`: on `event` callbacks for real channels (sms/voice), call `advanceChannelTo` so `record.channel` tracks Vonage's actual progression; compute the event's step against the updated total
- [ ] `webhook.js` / `verification.js`: include the current `channel` in the `GET /logs/:request_id` response
- [ ] Server tests: voice `event` webhook advances `record.channel` sms→voice; a stale/earlier channel does NOT move it backward; `/logs` returns `channel`; `verification:completed` after an auto-advance labels the voice channel

### iOS
- [ ] `APIClient.fetchLogs` + `VerificationServiceProtocol`: return the active channel alongside logs (e.g. `(logs, channel)` or a small struct)
- [ ] `LoginViewModel`: during the polling merge, reconcile the local `path`/`state` when the server channel is ahead of the app's — if Vonage auto-advanced sms→voice while the app shows `.enteringSmsCode`, transition to `.enteringVoiceCode`, set `path = .voice`, and emit a device log ("Vonage advanced to voice on its own — the SMS channel timed out")
- [ ] iOS tests: polling that surfaces a `voice` active channel transitions the ViewModel sms→voice and relabels subsequent step totals to /6; mock `fetchLogs` returns the channel

### Wrap-up
- [ ] Full server + iOS suites green
- [ ] Blog-worthy notes (the auto-advance-vs-explicit-/next divergence is a strong teaching point) + archive

## Implementation complete ✓

Server 45/45, iOS 62/62 tests passing.

- [x] `store.js`: forward-only `advanceChannelTo` (silent_auth→sms→voice, never backward)
- [x] `webhook.js`: real-channel events advance `record.channel`; logs `workflow:channel_advanced`; step recomputed against updated total
- [x] `/logs/:request_id` returns `channel`
- [x] Server tests: voice event advances channel, earlier event doesn't downgrade, voice step is 6/6, /logs returns channel
- [x] iOS `fetchLogs` returns `LogsResponse { logs, channel }`; protocol/service/mocks updated
- [x] iOS `reconcileChannel` in the polling loop auto-switches sms→voice, sets path=.voice, emits `workflow:auto_advanced`
- [x] iOS tests: polling with server channel=voice auto-advances the ViewModel; APIClient decodes channel

## Blog-worthy notes

### The workflow advances without asking you — webhooks are the only truth
The sharpest lesson of the whole project. We modeled channel progression as app-driven: tap "Didn't get it?" → POST /next → advance. But Vonage's Verify v2 workflow **auto-advances on channel timeout**. If the user just waits on the SMS screen, the SMS channel expires and Vonage places the voice call on its own — no /next, no app involvement. The user authenticates over voice while every label in the app still says "SMS", because both the backend's channel counter and the app's local `path` only moved on explicit app actions.

This is invisible until you actually let a channel time out on a real device (a virtual-operator +990 number completes instantly and never exercises it). The fix reframes the architecture: **the webhook stream is the source of truth for which channel is live**, and both tiers reconcile to it — the backend advances `record.channel` from webhook events (forward-only, since at-least-once delivery means events can arrive out of order), and the app catches its UI up during polling.

### Forward-only advancement guards against at-least-once webhook delivery
Vonage webhooks are at-least-once and not ordered. A late/duplicate `sms` event arriving after `voice` must not drag the channel backward. Encoding the workflow as a rank (silent_auth=0, sms=1, voice=2) and only ever moving to a higher rank makes the reconciliation idempotent and order-independent on both tiers — the same guard lives in `store.advanceChannelTo` and in the app's `reconcileChannel`.

### Optimistic transitions and reconciled transitions coexist
Two different transition styles now drive the same state machine: the *user-initiated* fallback ("Didn't get it?") transitions optimistically and synchronously (previous task), while the *Vonage-initiated* auto-advance is discovered asynchronously via polling and applied when detected. Both funnel into the same `path`/`state`, and the `workflow:auto_advanced` device log makes the second kind visible in the console — so the demo audience sees the workflow move by itself, which is exactly the behavior that was previously silent.
