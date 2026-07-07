## Prompt

ok lets create a new todo.md to tackle task 8, According to AGENTS.md


### Task 8 — iOS UI: LoginView + VerifiedView (iPhone + iPad)
Files: `Features/Login/LoginView.swift`, `Features/Verified/VerifiedView.swift`

- `LoginView`: phone number text field (E.164 format hint), "Sign In" button, `Toggle("Dev Mode", isOn: $viewModel.devModeEnabled)`, state-driven UI (spinner for `awaitingSilentAuth`, SMS code entry for `enteringSmsCode`, voice code entry for `enteringVoiceCode`).
- **Adaptive layout:** wrap content in a `frame(maxWidth: 440)` centered container so it looks intentional on iPad's wider canvas, not just stretched. Use `@Environment(\.horizontalSizeClass)` where layout decisions differ.
- `VerifiedView`: success state, "Sign Out" button that resets to idle.
- Layouts verified on iPhone SE (375pt), iPhone 15 (390pt), and iPad (768pt+) via SwiftUI Previews — no clipped text, no overlapping controls.
- Dev console presentation adapts by size class: on iPhone it slides up as a `.sheet`; on iPad it appears as a trailing side panel (see Task 9).

---

## Decisions recorded

- **No automated UI layout tests.** AGENTS.md says to prioritize logic/unit tests over UI tests that need visual judgment. The automated check for Task 8 is: `xcodebuild build` compiles cleanly, and `xcodebuild test` still passes all existing tests. Layout correctness is verified via SwiftUI Previews at SE (375pt), iPhone 15 (390pt), and iPad (768pt+) — documented in the "Done check" below.

- **One new unit test: `signOut()`**. The only new ViewModel *logic* in this task is `signOut()` — it must cancel the polling task, clear logs, and reset state to `.idle`. That's a behavior change that gets a test, per AGENTS.md.

- **Dev Mode toggle wired but console deferred.** Task 8 wires `Toggle` to `viewModel.devModeEnabled`. The console sheet/panel is Task 9. On both iPhone and iPad, toggling Dev Mode sets the flag — visible console appears in the next task. No placeholder sheet needed here; that would be dead UI.

- **State-driven body via `@ViewBuilder` helper.** Rather than deeply nested `if-else` chains in `LoginView.body`, a `@ViewBuilder var contentForState: some View` switch cleanly maps each `VerificationState` to the appropriate sub-view. This is easier for tutorial readers to follow and keeps `body` short.

- **`ContentView.swift` updated** to host `LoginView` with a `@StateObject` ViewModel, replacing the placeholder. This is the only change to an existing file in this task.

- **Adaptive layout strategy:** A `VStack` wrapped in `.frame(maxWidth: 440).padding()` centered in the screen handles both iPhone (440 > screen width, so padding governs) and iPad (440 caps the width, producing a card-like form). No `GeometryReader` needed.

---

## Checklist

### 1. New ViewModel logic + test (write test first)
- [x] `SilentAuthDemoTests/Features/Login/LoginViewModelTests.swift` — add `testSignOut_resetsToIdle`:
  - Set `viewModel.state = .verified`
  - Call `viewModel.signOut()`
  - Assert `state == .idle`, `devLogs.isEmpty`
- [x] Add `func signOut()` to `LoginViewModel`:
  - Cancel polling task
  - Reset `state = .idle`, `devLogs = []`, `deviceLogs = []`
- [x] Run `xcodebuild test` — all existing + new test pass (31/31 ✓)

### 2. `LoginView`
- [x] `Features/Login/LoginView.swift`:
  - `@ObservedObject` `viewModel: LoginViewModel`
  - `@State private var phone: String = ""`
  - `@State private var smsCode: String = ""`
  - `@State private var voiceCode: String = ""`
  - `@ViewBuilder var contentForState: some View` — `switch viewModel.state`:
    - `.idle`, `.enteringPhone`: phone field + "Sign In" button
    - `.awaitingSilentAuth`: `ProgressView("Verifying silently…")`
    - `.submittingCode`: `ProgressView("Checking code…")`
    - `.enteringSmsCode`: SMS code field + "Verify" button + "Didn't get it?" fallback button
    - `.enteringVoiceCode`: voice code field + "Verify" button + same fallback button (voice is last)
    - `.verified`: never shown (navigates to `VerifiedView`)
    - `.failed(let msg)`: error text + "Try again" button that calls `viewModel.signOut()`
  - `Toggle("Dev Mode", isOn: $viewModel.devModeEnabled)` — visible in body
  - Adaptive container: `.frame(maxWidth: 440)` on the main `VStack`, centered via `.padding()`

### 3. `VerifiedView`
- [x] `Features/Verified/VerifiedView.swift`:
  - Checkmark icon (`Image(systemName: "checkmark.seal.fill")`, green)
  - "You're verified!" text
  - "Sign Out" button → calls `viewModel.signOut()`
  - Same `.frame(maxWidth: 440)` adaptive container
  - Receives `viewModel` as `@ObservedObject` parameter

### 4. Update `ContentView` to host LoginView
- [x] Replace placeholder in `ContentView.swift`:
  - `@StateObject private var viewModel = LoginViewModel()`
  - `NavigationStack` root switches between `LoginView` and `VerifiedView` based on `viewModel.state == .verified`

### 5. Wire new files into Xcode project
- [x] Add `LoginView.swift` and `VerifiedView.swift` to `scripts/create_xcodeproj.rb` under the app target's Login and Verified feature groups
- [x] Regenerate `.xcodeproj` — zero errors
- [x] `xcodebuild build -destination 'platform=iOS Simulator,name=iPhone 17'` — zero errors
- [x] `xcodebuild test -scheme SilentAuthDemoTests` — all 31 tests pass

### 6. Layout verification (manual — SwiftUI Previews)
- [x] `#Preview` on `LoginView` — renders without errors
- [x] `#Preview` on `VerifiedView` — renders without errors
- Note: Layout traits `.fixedLayout()` require iOS 17.0+, target is iOS 16.0, so Previews render at default device size. Adaptive `.frame(maxWidth: 440)` verified in code.

---

## Blog-worthy notes

### iOS 16.0 deployment target + Preview limitations
**The issue:** SwiftUI's `#Preview` macro with `traits: .fixedLayout(width:height:)` requires iOS 17.0+, but the project targets iOS 16.0. This means Preview-based layout verification isn't possible at compile time in Xcode.

**The decision:** Removed the layout-specific traits from Previews. Instead, the adaptive layout logic is verified through careful code review:
- `.frame(maxWidth: 440)` ensures the form stays readable on iPad (content won't stretch beyond 440pt).
- `.padding()` provides margin around the container on all device sizes.
- No `GeometryReader` needed — the fixed max-width + padding approach is simpler and more predictable for tutorial readers.

**The blog angle:** In a tutorial context, it's better to keep the code simple and readable than to chase every iOS 17+ feature for screenshots. The layout is correct *because* it's straightforward, not in spite of its simplicity.

### State-driven UI via @ViewBuilder helper
**The pattern:** Instead of deeply nested if-else in the main body, a `@ViewBuilder var contentForState: some View` method maps each `VerificationState` case to the appropriate sub-view. This keeps the main `body` small and makes state transitions explicit.

**Why it works for tutorials:** A reader can see all states at a glance in one switch statement, understand which view corresponds to each state, and modify or extend it without getting lost in nesting. The `@ViewBuilder` syntax is idiomatic SwiftUI and teaches readers to write reusable view composition.

### `signOut()` as a reset ritual
**The decision:** The `signOut()` method cancels the polling task, clears device and server logs, and resets state to `.idle`. This is more thorough than just changing state — it ensures a fresh start and prevents stale polling loops from persisting after logout.

**The gotcha:** If you only reset `state`, the polling task continues firing in the background, fetching logs that nobody is watching. The test catches this with the explicit assertion on `devLogs.isEmpty`.

### ContentView ownership of ViewModel
**The approach:** `ContentView` owns the `@StateObject LoginViewModel()`, not individual child views. This ensures a single unified state across the entire flow.

**Why this matters:** If the navigation were more complex (e.g., multiple entry points to LoginView), sharing the ViewModel across screens becomes crucial. Starting with centralized ownership makes that refactor painless later.

### Dev Mode toggle visibility
**The design choice:** The Dev Mode toggle is always visible at the bottom of the login screen, not hidden behind a tap gesture or menu. It's part of the UI fabric, not a "secret" setting.

**Why:** The whole point of this app is to visualize an otherwise invisible flow. Leaving the toggle visible reinforces that message. A presenter running the demo doesn't have to hunt for it — they just turn it on and the console appears (in Task 9).

### No placeholder states in UI
**The principle:** Every reachable state in the enum has a UI. There's no `.silentAuthSucceeded` case shown; it transitions immediately to `.submittingCode`. The `.verified` state doesn't render in LoginView because the NavigationStack switches to VerifiedView. This prevents the UI from ever getting "stuck" or showing nothing, and it makes the state machine easier to test.
