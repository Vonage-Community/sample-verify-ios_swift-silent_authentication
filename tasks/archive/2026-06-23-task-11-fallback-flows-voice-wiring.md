## Prompt

alright lets archive and write the task 11 plan according to AGENTS.md

---

### Task 11 — Fallback flows + voice wiring
- Ensure voice fallback path in state machine is exercised: after SMS `enteringSmsCode`, user can tap "Didn't get it?" → calls `/next` again → `enteringVoiceCode`.
- UI: voice code entry view with appropriate label ("Check your phone — we're calling you now").
- Backend: `/next` works for both silent_auth→sms and sms→voice transitions (no change needed — `nextWorkflow` is generic).
- Test: state machine test for sms→voice transition.

---

## Audit: what's already done

This task was substantially implemented across Tasks 7, 8, and 3. The plan below documents the gaps discovered via audit, not a repeat of prior work.

**Already complete:**
- `triggerFallback()` in `LoginViewModel` handles both `awaitingSilentAuth→enteringSmsCode` and `enteringSmsCode→enteringVoiceCode` transitions via `default: break` for any other state (Tasks 7)
- Voice code entry UI in `LoginView` with label "Voice Code" and caption "Check your phone — we're calling you now" (Task 8)
- "Didn't get it?" button shown only for `isFallback: true` (SMS state) — hidden for voice, which is the correct terminal fallback behaviour (Task 8)
- Backend `/next` route calls `verifyClient.nextWorkflow(requestId)` — generic, handles any channel transition (Task 3)
- `testTriggerFallback_fromSms_transitionsToEnteringVoiceCode` — passes (Task 7 / already in test suite)
- `testSubmitCode_fromVoiceState_verified` — passes (Task 10)

**Genuine gap — one missing test:**
`triggerFallback()` called from `enteringVoiceCode` should be a no-op: the UI hides the button, but the state machine should not blow up if the method is ever called from voice state. The `default: break` in the switch handles this, but it's untested. A test asserting state is unchanged when `triggerFallback()` is called from `.enteringVoiceCode` closes this gap.

---

## Decisions recorded

- **No code changes required.** The voice fallback path is fully wired. This task is a verification pass + one missing test.

- **Why one test and not UI tests.** The button visibility (`if isFallback`) is a structural condition in `codeEntryView`, not runtime logic — it can't be unit tested without a UI test framework. What *can* be unit tested is the ViewModel's behaviour when `triggerFallback()` is called in voice state, which is what we're adding.

- **`default: break` is the right guard, not a separate state.** When `triggerFallback()` is called in voice state, it calls `service.triggerFallback(requestId:)` on the backend (firing a `/next` call) but doesn't transition the ViewModel state. This could in theory confuse Vonage if the workflow has no more channels, but for a demo app this is acceptable — the backend returns an error and the ViewModel catches it, logging the error. Worth noting in blog notes.

---

## Checklist

### 1. Add missing test
- [x] In `LoginViewModelTests.swift`, added `testTriggerFallback_fromVoiceCode_isNoOp`:
  - Set `viewModel.state = .enteringVoiceCode(requestId: "req-123")`
  - Call `viewModel.triggerFallback()`
  - Assert state is still `.enteringVoiceCode(requestId: "req-123")` after a short delay ✓
  - Assert `mockService.triggerFallbackCalled` is true ✓
  - Added `var triggerFallbackCalled: Bool = false` to `MockVerificationService` ✓

### 2. Run and confirm
- [x] `xcodebuild test -project ios/SilentAuthDemo.xcodeproj -scheme SilentAuthDemoTests -destination 'platform=iOS Simulator,name=iPhone 17'` — all 50 tests pass (49 existing + 1 new) ✓

---

## Blog-worthy notes

### The `default: break` guard in `triggerFallback()`
When voice is reached, it's the terminal state — there's no further fallback channel. The state machine handles this via `default: break` in the state switch inside `triggerFallback()`. The backend call *is* made (calling `/next` on a complete workflow returns a backend error), but the ViewModel state doesn't transition. This defensive approach prevents invalid state transitions without needing a special case.

### UI button visibility encodes the state machine's logic
The "Didn't get it?" button is shown with `if isFallback { ... }`. Since `codeEntryView(isFallback: false)` is called for voice, the button is hidden — a form of "UI-driven state protection." This means even if `triggerFallback()` were called from voice (through some interaction path), the ViewModel would handle it gracefully. The test proves this.

### Mock objects track method calls for behavior verification
`MockVerificationService.triggerFallbackCalled` lets the test assert that the backend *was* invoked even when the ViewModel state didn't change. This is the difference between testing "the state is correct" (what you expect to see) and "the state is correct *and* the backend was called for side effects" (the full contract). Both matter in a demo app where log visibility is important.
