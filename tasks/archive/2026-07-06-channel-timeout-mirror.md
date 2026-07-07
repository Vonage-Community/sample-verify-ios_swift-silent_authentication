## Prompt

hmm, its still not doing the correct behaviour. you can see in the screenshot. there is a ui update when silent auth moves to sms. but no update when the phone call is initiated. in this run, i never  entered a code or pikced up the phone. so i received an sms, but did nothing. received a call but did nothing. and there were no ui updates to show that i received the call other than the webhook:summary. Is there a way to do what i want?

## Diagnosis (from the screenshot)

Between `verification:fallback` (17:06:23) and `webhook:summary` (17:12:25), **no webhooks arrived at all** — no `sms:expired` event mid-flow. The per-channel event hook from the previous task never fires in practice for SMS/voice; Vonage only documents mid-flow events for Silent Auth / WhatsApp Codeless. The summary (with `sms: expired, voice: expired`) only comes at the very end.

## Design: mirror Vonage's channel clock server-side

`channel_timeout` is a request parameter we control. If we set it explicitly, the server knows precisely when Vonage advances each channel: `channel_timeout` seconds after the channel starts. So:

1. Pass `channelTimeout` in `newRequest()` (env `CHANNEL_TIMEOUT_SECONDS`, default 60 — also makes the demo fallback fast instead of 3 minutes).
2. When the active channel changes to one that has a successor (sms, or silent_auth if unattended), arm a server-side timer for `channel_timeout + grace (5s)`.
3. When the timer fires and the request is still pending on that same channel, advance to the next channel, log `workflow:channel_advanced` (reason: channel timeout mirrored), and re-arm for the new channel if it also has a successor.
4. Clear the timer on: explicit `/next`, completion via `/check-code`, terminal summary webhook.
5. Keep the webhook-event advance from last task — if Vonage ever does send an `expired` event, forward-only advancement makes the two mechanisms idempotent together.

iOS needs no changes: polling already reconciles from `/logs`'s `channel` field.

## Checklist

- [ ] `verification.js`: pass `channelTimeout` to `newRequest`; store it on the record
- [ ] `server/channelTimer.js`: `arm(requestId)` / `clear(requestId)` timer registry; advance + log + re-arm on fire
- [ ] Arm after: `/next` advance, webhook-event advance; clear on completion/summary-terminal
- [ ] Tests (fake timers): timer advances sms→voice + logs; completion clears; same-channel guard; voice (last) not re-armed
- [ ] Existing suites stay green (server + iOS)
- [ ] Blog-worthy notes + archive

## Implementation complete ✓

Server 54/54 (7 new timer tests), iOS unchanged (62/62 from last run).

- [x] `channelTimeout` passed to `newRequest` (env `CHANNEL_TIMEOUT_SECONDS`, default 60) and stored on the record
- [x] `server/channelTimer.js`: arm/clear registry; on fire → advance channel, log `workflow:channel_advanced` (reason: channel_timeout), re-arm for the next channel
- [x] Armed at request creation, after `/next`, and after a webhook-event advance; cleared on `/check-code` completion and on any summary webhook
- [x] Fake-timer tests: sms→voice on timeout, grace period respected, completed request untouched, clear() disarms, moved-channel guard, last-channel no-op, full silent_auth→sms→voice chain
- [x] `.env.example` documents `CHANNEL_TIMEOUT_SECONDS`

## Blog-worthy notes

### Vonage sends no webhook for mid-flow channel timeouts — mirror the clock instead
The previous fix hooked the `sms:expired` event webhook. A real device run disproved it: six minutes of silence between the fallback and the final summary — zero webhooks — then `webhook:summary` reporting `sms: expired, voice: expired` after everything was over. Mid-flow event callbacks exist only for Silent Auth / WhatsApp Codeless; SMS and voice outcomes surface solely in the end-of-request summary.

The workable answer: `channel_timeout` is a parameter *we* set on the request, so the server knows Vonage's schedule exactly. When a channel starts, arm a local timer for `channel_timeout + 5s grace`; if the request is still pending on that channel when it fires, advance — the same move Vonage just made silently on its side. The grace ensures our clock always fires *after* Vonage's, so the UI never gets ahead of reality.

### Defense in depth for state sync: three advancement triggers, one idempotent rule
Channel progression now has three drivers — explicit `/next` (user tap), webhook events (if Vonage ever sends one), and the timeout mirror. All three funnel through the same forward-only, same-channel-guarded advancement, so any combination of them firing in any order converges on the same state. The timer callback re-checks the record before acting ("is it still pending, still on the channel I armed for?") — the timer being stale is normal, not exceptional.

### Setting channel_timeout explicitly is a demo superpower
The default channel timeout (300s) means a 5-minute wait to see SMS→voice fallback live. Since the server now controls the value (60s default via env), a presenter can show the entire silent_auth→sms→voice cascade inside two minutes — and the mirrored timer narrates each hop in the console as it happens.
