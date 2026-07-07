## Prompt

ok that works good enough for the demo. But now I want to clean up the timeline of the verification. Its really hard to read. I don't understand why there are so many "Step 2/5" when the flow moves between verification methods. Here is how looked through the whole flow: silent auth, sms, voice.

I want you to think about how to make this more obvious, easier to read. To make it clear the different stages of verification while telling the user right away whats happening in each step. I would also like you to make the app "vonage-ified", I have attached the vonage brand guideline. Please create a plan to make these visual changes.

## Why the current timeline is confusing

The "STEP n/m" numbering treats steps as *phases shared across events*, so several events legitimately carry "STEP 2/5" — and when the path grows (5→6) the totals shift mid-scroll. Numbering that made sense per-path reads as duplication and renumbering in a merged timeline. The real mental model of the flow isn't 5 numbered steps — it's **channels tried in order**: Silent Auth → SMS → Voice → Result. So the fix is to *group by channel stage*, not to number individual events.

## Design A — timeline readability: stage-grouped timeline

1. **Drop per-event step badges entirely** (`step` field stays in the API for the blog's sake but the UI stops rendering "STEP n/m" chips).
2. **Group events into stages** derived from each event's label/channel:
   `Request` → `Silent Auth` → `SMS` → `Voice` → `Result`.
   Mapping lives in one place (`LogEvent.stage` computed property + tests): `silent_auth:*` / `webhook:silent_auth:*` → Silent Auth; `verification:fallback(to:sms)` / `webhook:sms:*` / code events while sms → SMS; voice equivalents → Voice; `verification:verified|completed` / `webhook:summary` → Result; everything before the first channel → Request.
3. **Render stage section headers** in the console: a full-width divider row with the stage name, a number chip (① ② ③), and a one-line stage explainer (e.g. *"Silent Auth — verifying via the SIM, no user input"*). Each header shows the stage outcome once known: ✓ succeeded / ✕ failed → fell through / ⏭ skipped.
4. **Quiet down the rows**: the `note` (plain English) becomes the row's primary text; the machine label (`silent_auth:cellular_check`) drops to small mono secondary text; detail key-values stay small mono. Timestamp + source dot stay in the row header.
5. **Live stage tracker pinned at the top of the console** (replaces the current plain state label): three segments `Silent Auth · SMS · Voice` rendered as a progress pill — completed stages filled, current stage pulsing, untouched stages dimmed. Answers "what's happening right now" without reading a single log line.

## Design B — Vonage-ify (from Brand Guidelines 2025)

Palette (exact hex from the guide, as a `VonageBrand` SwiftUI namespace):
- **Purple `#871FFF`** — primary actions (Sign In / Verify buttons), current-stage highlight, device badge
- **Plum `#3D0049`** — nav/headline text, stage headers, server badge
- **Magenta `#D6219C`** — SMS stage accent
- **Orange `#FA7554`** — voice stage accent (guide: orange for solid fills, never peach)
- **Cyan `#80C7F5`** — informational accents (check_url / silent-auth in-flight)
- **Grays `#E8EAEE / #D9DCE3 / #878A91 / #54575E`** — row separators, secondary text, dimmed stages
- Stage colors double as the timeline's visual language: silent auth = purple, sms = magenta, voice = orange, result = plum/green-check.

Typography: brand face is Spezia (licensed, can't bundle). Per the guide's own fallback logic we stay closest with system fonts: SF for body, **SF Mono for labels/eyebrow-style text — uppercase, tracked-out stage headers** (the guide's eyebrow pattern: all-caps mono, +25 tracking). No fake logo anywhere: the guide restricts the lock-up/symbol to provided assets, so we brand through color + type only, with a plain-text "Powered by Vonage" footer on the login screen.

Screens touched:
- `LoginView` — purple CTA buttons (white text, 8pt radius), plum headline, gray field borders, "Powered by Vonage" footer
- `DevConsoleView` — stage tracker pill, stage headers, re-styled rows, plum "Hide" link
- `LogEventRow` — new row layout (note-first), stage accent bar on the leading edge, source dot colors (device purple / server plum)
- `VerifiedView` — purple check seal, plum title, purple Sign Out button
- Dark mode: keep it simple — same hues, system backgrounds (brand colors read fine on dark)

## Checklist

- [ ] `VonageBrand.swift`: Color palette (hex init) + eyebrow/mono text styles
- [ ] `LogEvent.stage`: stage derivation from label + tests (every label family maps correctly; unknown labels → current stage fallback)
- [ ] `DevConsoleView`: stage tracker pill (driven by `path` + stage outcomes), grouped sections with headers, remove step badges
- [ ] `LogEventRow`: note-first layout, stage accent bar, rebranded source badges, no step chip
- [ ] `LoginView` / `VerifiedView`: brand colors, footer, button styles
- [ ] Tests: stage mapping, stage-outcome derivation (e.g. silent_auth stage shows failed once `silent_auth:failed` seen), existing suites stay green
- [ ] Layout check: iPhone SE (375pt), 390pt, iPad side panel — headers and tracker don't clip
- [ ] Blog-worthy notes + archive

## Out of scope

- Bundling Spezia/Montserrat/Roboto font files (licensing + asset weight; system fonts approximate the guide's fallback intent)
- Any use of the Vonage logo lock-up or V symbol (guide requires provided assets + approval)
- Server-side changes — `step`/`note` fields keep flowing; only the iOS rendering changes

## Implementation complete ✓

iOS 69/69 tests passing (62 + 7 new stage-mapping tests). Server untouched.

- [x] `Theme/VonageBrand.swift`: exact-hex palette (Purple/Plum/Magenta/Orange/Cyan + grays), `Color(hex:)`, eyebrow text style
- [x] `Models/LogStage.swift`: `LogStage` enum + `LogEvent.stage` derivation (result wins over channel mention; fallback/advance events follow `detail.to`)
- [x] `LogStageTests`: every label family maps to the right stage
- [x] `LogEventRow`: note-first layout, stage accent bar, source dots (device purple / server plum), step chip removed
- [x] `DevConsoleView`: channel tracker pill (Silent Auth · SMS · Voice with live outcome glyphs), stage-grouped sections with eyebrow headers + outcome labels, `StageOutcome` derivation from path + state
- [x] `LoginView` / `VerifiedView`: purple CTAs, plum headlines, gray field borders, "Powered by Vonage" footers
- [x] Xcode project + script updated for new files/groups; regenerated
- [x] Layouts: tracker segments use minimumScaleFactor so three channels fit iPhone SE width

## Blog-worthy notes

### "STEP n/m" was the wrong abstraction — group by channel, not by step
The confusing part wasn't the numbers being wrong, it was numbering the wrong thing. A merged device+server timeline has multiple events per phase, so repeated "STEP 2/5" is *correct* yet reads as broken. The reader's actual question is "which channel am I on?" — so the fix was to make the channel the primary visual unit: a persistent tracker pill answers it at a glance, and stage section headers answer it as you scroll. The per-event `step` field still ships in the API (useful for the tutorial's data model) but the UI stopped surfacing it. Lesson: when a progress indicator feels noisy, check whether you're numbering events when you should be grouping by phase.

### Deriving stage from label keeps grouping and tracking in sync
Both the section grouping and the tracker pill read from one `LogEvent.stage` computed property (plus `StageOutcome.derive` off the ViewModel's `path`/`state`). There's no separate "what stage is this" bookkeeping to drift — a new log label automatically lands in the right section the moment its prefix matches, and unit tests pin the mapping.

### Branding without the logo
The Vonage guidelines restrict the logo lock-up and "V" symbol to provided assets with sign-off, so the app brands entirely through the palette and type system — purple CTAs, plum headlines, and the channel colors (silent auth = purple, SMS = magenta, voice = orange) doubling as the timeline's legend. A plain-text "Powered by Vonage" footer attributes without touching a restricted asset. Spezia (the brand face) is licensed and can't be bundled, so per the guide's own fallback logic we lean on SF / SF Mono, using the guide's eyebrow pattern (all-caps mono, tracked out) for stage headers to keep the flavor.
