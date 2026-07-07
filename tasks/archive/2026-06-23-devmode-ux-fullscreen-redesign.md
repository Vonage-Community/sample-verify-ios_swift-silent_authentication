## Prompt

ok we have our first big problem! When you toggle on dev mode, a bottom sheet is pulled up. I guess the idea is that this bottom sheet will have the Dev Mode output. Unfortunately the bottom sheet covers the form and its impossible to click "sign in" because its covering the button.

I think a better ux would be that once the form is submitted, a full screen modal is activated, there the dev mode output can be shown. And completed then the user is taken to the verified screen.

---

## Implementation complete ✓

**All 55 iOS tests passing** (50 existing + 5 new `isIdle` tests).

### Changes made:

1. **`VerificationState.swift`** — Added `var isIdle: Bool` computed property
   - Returns `true` for `.idle` and `.enteringPhone`, `false` otherwise ✓

2. **`ContentView.swift`** — Replaced sheet with fullScreenCover
   - Removed `.sheet(isPresented: $viewModel.devModeEnabled)` ✓
   - Added `.fullScreenCover` with custom binding: `devModeEnabled && !viewModel.state.isIdle` ✓
   - Passes `onDismiss` callback to DevConsoleView ✓
   - iPad side panel unchanged (not blocked by anything) ✓

3. **`DevConsoleView.swift`** — Added header + inline code entry
   - Header: state label ("Verifying silently…", "Waiting for SMS code…", "Verified ✓", etc.) + "Hide" button ✓
   - Code entry panels: inline VStack at bottom for SMS/voice states ✓
   - Code input field resets on state change via `.onChange(of: viewModel.state)` ✓
   - Empty state message remains for pre-log moments ✓

4. **`VerificationStateTests.swift`** — Added 5 new tests
   - `testIsIdle_idle` ✓
   - `testIsIdle_enteringPhone` ✓
   - `testIsIdle_awaitingSilentAuth` ✓
   - `testIsIdle_enteringSmsCode` ✓
   - `testIsIdle_verified` ✓

### UX improvements:

✓ Toggle is now a preference ("arm the recorder") — no UI change until Sign In is tapped
✓ Full-screen console appears *during verification* and shows live state + logs
✓ Code entry (SMS/voice) moves into the console, visible alongside logs
✓ "Hide" button dismisses console without interrupting verification
✓ iPhone: toggling Dev Mode while idle does nothing (console won't appear until flow starts)
✓ iPad: side panel layout unchanged and unaffected
✓ Sign Out → state returns to `.idle` → cover auto-dismisses
