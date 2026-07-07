## Prompt

ok so the app works and i get the correct behaviour silent auth -> sms -> voice, but when the sms doesn't work and the verification falls back to voice, the app ui doesn't get updated. Here is the xcode log:

[Xcode console output showing CoreTelephony XPC errors, layout constraint warnings, and the cellular check_url redirect chain succeeding with a returned code — full log included in conversation]

## Checklist

- [x] Diagnose why the UI didn't transition to `.enteringVoiceCode` after SMS fallback
- [x] Fix `triggerFallback()` to transition state synchronously instead of waiting on the `/next` network round-trip
- [x] Re-run iOS test suite to confirm fix and check the pre-existing flaky test
- [x] Archive with blog-worthy notes

## Blog-worthy Notes

### State transitions gated behind a network call freeze the UI under real-world timing

**What happened:** Tapping "Didn't get it?" from the SMS code screen correctly triggered the backend `/next` call (visible in Dev Mode logs: `verification:next → to: sms`, `vonage:nextWorkflow` confirmed), but the on-screen UI stayed frozen on the SMS code entry screen instead of showing the voice code entry.

**Root cause:** `triggerFallback()` computed the next `VerificationState` and assigned it *inside* the async `Task`, only after `await service.triggerFallback(requestId:)` returned:

```swift
Task {
    try await service.triggerFallback(requestId: requestId)
    switch state {
    case .enteringSmsCode:
        state = .enteringVoiceCode(requestId: requestId)  // only runs after the network call
    ...
    }
}
```

On the simulator this was fast enough to look instant. On a **real device with an active cellular Silent Auth attempt**, the shared `URLSession` was still tearing down from the earlier `VGCellularRequestClient` cellular request (visible in the log as CoreTelephony XPC connection errors and a `bad certificate` TLS failure on the `idlayr.com` redirect chain). That teardown noise appears to have delayed or interfered with the subsequent `/next` POST enough that the state-changing code never visibly executed in a timely way — from the user's perspective, tapping the button did nothing.

**Fix:** Decide the next state from the *current* state synchronously, assign it immediately (before firing any network request), and only use the async `Task` to fire the backend call and handle failure:

```swift
let nextState: VerificationState?
switch state {
case .enteringSmsCode:
    nextState = .enteringVoiceCode(requestId: requestId)
...
}
if let nextState { state = nextState }  // UI updates instantly

Task {
    try await service.triggerFallback(requestId: requestId)  // fire-and-forget from the UI's perspective
}
```

**Why this matters for the blog:** This is a **general SwiftUI/async lesson, not a Vonage-specific one** — it's tempting to treat "call the backend, then update state" as one atomic step, but a state machine driving UI should transition optimistically wherever the transition is a foregone conclusion (tapping "I want to skip to voice" *is* the user's intent regardless of whether the backend confirms in 50ms or 3 seconds). Reserve the awaited result for genuine failure handling, not for gating a UI update the user is already expecting. This bug was invisible in the simulator and only appeared on a real device — a reminder that timing-dependent bugs in async flows often only surface under real network/hardware conditions, which is exactly why AGENTS.md calls out that a real device on cellular is needed to exercise the full Silent Auth path.

**Bonus finding:** the pre-existing flaky test (`testTriggerFallback_fromSms_transitionsToEnteringVoiceCode`, previously passing "with 1.355 seconds" timing on one run) became fully deterministic after this fix, since the state transition no longer depends on `Task` scheduling order.
