## Prompt

ok i was misunderstanding the ui, i didnt realize there was teh "didn't get the code?" button. But the way the authentication fallback works is that automatically the workflow goes from silent auth to sms and if the sms code times out after 3 minutes, then the voice fallback happens. But the UI in the app is only updated if the user clicks the "didn't get code" button. Is there a callback/webhook we can hook into to make that ui update automatically like we did from silent auth -> sms, to also do it automatically from sms -> voice?

## Answer + correction

**Yes — but it's the SMS `expired` event, not a "voice started" event.** Verified against Vonage docs (Verify v2 webhooks):

- Event callbacks (`type: event`) carry a channel's **final status** (`completed`, `expired`, `failed`, `blocked`, `user_rejected`, `cancelled`, `action_pending`). There is **no** "next channel started" event for SMS/Voice.
- When the SMS channel times out (~3 min), Vonage fires `{ type: "event", channel: "sms", status: "expired" }`. **That** is the signal that voice is now taking over.

This exposed a bug in the previous task's implementation: it advanced `record.channel` to the *event's own channel*, so it only reacted to a `voice` event that Vonage never sends. Corrected so the trigger is the **current channel finishing with a non-completing status**.

## Changes

- `verification.js`: store the real workflow channel list on the record (`setWorkflow`) so advancement respects the actual order (playground +990 = silent_auth only; real = silent_auth/sms/voice).
- `store.js`: replaced `advanceChannelTo(channel)` with `advanceOnChannelFinished(requestId, finishedChannel, status)` — advances to the *next* workflow channel only when the finished channel is the current one AND status ∈ {expired, failed, blocked} AND a next channel exists. Forward-only, ignores stale/out-of-order events.
- `webhook.js`: event handler calls `advanceOnChannelFinished`; logs `workflow:channel_advanced` with `{from, to}`.
- Server tests: SMS `expired` → voice; SMS `completed` does NOT advance; stale earlier-channel event doesn't move backward; voice `expired` on last channel doesn't advance; voice completion after advance is numbered 6/6. (47/47)
- iOS: **no change needed** — the app already reconciles off `response.channel` from `/logs`, which the backend now advances correctly. (62/62 still green)

## Blog-worthy notes

### "There is no 'started' event" — model transitions off the *previous* channel's terminal event
The intuitive design is "listen for the voice channel starting." Vonage doesn't emit that. The only mid-flow signal is the **outgoing** channel's terminal status (`sms: expired`). So the correct mental model is: a workflow advance is inferred from the *departing* channel finishing without completing, combined with knowing the workflow order — not from the *arriving* channel announcing itself. This is a subtle but important API-shape lesson: when a system won't tell you X started, look for "the thing before X ended."

### Why status filtering matters
Not every terminal status implies a forward move. `completed` finishes the request; `user_rejected` (wrong PIN 3×) fails it; `cancelled` stops it. Only `expired`/`failed`/`blocked` mean "this channel is out, try the next one." Advancing on the wrong status would desync the UI from Vonage's actual state — the exact class of bug this whole thread has been about.

### The channel_timeout is the clock
SMS→voice fires after the channel timeout (default 300s; the user observed ~3 min, suggesting a configured `channel_timeout`). Worth noting in the tutorial that the auto-advance latency is a tunable request parameter, not a fixed delay — a demo can shorten it to make the fallback visible faster.
