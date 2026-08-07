# Full App Review — 2026-07-14

Six-part parallel review of the whole app (core workout flow, state/persistence, timers/Live Activity/Watch, secondary views, design-system audit, monetization/sharing). ~130 findings total. Executive summary first; the six full reports follow verbatim.

## Executive summary — fix order

### Wave 1 — Data safety & trust (do these first)
1. **Opening the cycle builder destroys data before you confirm anything.** `loadProgram` archives the current cycle and wipes logs as a side effect of navigation, before the user commits (CycleBuilderView.swift:225-238, AppState.swift:251-284). Cancel = data already gone.
2. **Corrupt/undecodable save silently resets to empty and is then overwritten.** `loadUserData` uses `try?` → `.empty`, and the next `didSet` save clobbers the store. No backup, no schema version (Persistence.swift:528-534).
3. **Premium stuck after purchase** — two causes: `canImportPRs` passed as a frozen `let` into `StrengthScoresView` (CalculatorsView.swift:74/1552), and `StoreManager.init` awaits the network product fetch *before* checking local entitlements (StoreManager.swift:121-124).
4. **Blank share sheet (first tap)** — `sheet(isPresented:)` + optional `@State` set in the same transaction (HistoryView.swift:616, SettingsView.swift:905). Fix with `sheet(item:)`. Same anti-pattern makes "Program Info" a blank sheet for custom templates (HomeView.swift:177, SettingsView.swift:950).
5. **PR celebration "skips a set"** — not the celebration: the NumberPad ✓ stays tappable during the rep-sheet dismissal and re-runs `onSave` after state has advanced; second path is a stale watch-completion guard. Fix: identity-stamp completions with (exerciseIndex, setNumber) and guard `onSave` (WorkoutView.swift:597-655, 958-1004).

### Wave 2 — Timer coherence (the app's core loop)
6. Tab-switch back to workout **resets Live Activity + notification to full duration** (WorkoutView.swift:1316-1397; same in AccessoryWorkoutView).
7. Pause → tab switch → resume leaves the in-app countdown **frozen** (no Timer restarted; surfaces diverge).
8. Jumping exercises mid-rest **orphans** the Live Activity and pending notification (WorkoutView.swift:288-315, 548-557).
9. Live Activity widget can **crash** on expired timers: `Date()...endTime` range trap (RestTimerLiveActivity.swift:35/80/199) — clamp it.
10. **Watch timer freezes when phone is backgrounded** — driven by 1/s foreground messages; send `endDate` once and render locally.
11. **+15s silently rewrites the default rest-duration setting** to a value the Settings picker can't display (WorkoutView.swift:1287, SettingsView.swift:354-362).
12. Tab-switch wipes **all accessory-workout progress** — `setupAccessories()` re-runs with fresh UUIDs (AccessoryWorkoutView.swift:339-344).
13. Phone + Watch both save HealthKit workouts → **duplicates**; watch writes even with sync off (WorkoutView.swift:914-948, WatchWorkoutManager.swift).

### Wave 3 — Premium feel (systemic, high leverage)
14. **Dynamic Type: zero support.** All of SBSFonts is fixed-size, but 820 call sites go through it — rewriting Theme.swift with text-style-relative fonts fixes most of the app in one file. Then migrate the 411 hardcoded `.font(.system(size:))` sites (WorkoutView 62, WorkoutShareCard 41, CycleBuilderView 38 = 34% in 3 files).
15. **Accessibility: 1 accessibilityLabel in the whole app vs 362 SF Symbol icons.** Sweep the ~79 icon-only buttons; timer skip/pause/±15s first.
16. **Haptic asymmetry:** set-complete buzzes but Complete Set, Skip, ±15s, pause/resume, foreground timer-expiry, and workout-finish are silent. Add a tiny Haptics helper.
17. **Dark mode: cards lose all elevation** (black shadows invisible on dark surfaces) — swap shadow for a subtle border in dark (Theme.swift:120/127).
18. **Asset-catalog colors are dead code** — no colorsets exist; everything uses `*Fallback`. Create real colorsets and rename, or delete the trap (Theme.swift:7-18).
19. **Copy glossary:** "lbs" in Settings vs "lb" everywhere else; "E1RM"/"Estimated 1RM"/"Est. 1RM" on the same screens; "TM" vs "Training Max"; duplicated lift-abbreviation switch statements (HistoryView.swift:2129, PastCyclesView.swift:181).
20. **Hardcoded "20 weeks"** on 12-week programs (HistoryView.swift:2316, CycleBuilderView.swift:444, SettingsView.swift:708); **Settings version says "1.0.0"** (SettingsView.swift:744) — read from the bundle.
21. **Internal/trademarked program names leak** ("Greyskull LP", raw ids like `stronglifts_5x5_12week`) via fallback chains (CycleBuilderView.swift:1699-1705, HomeView.swift:88, SettingsView.swift:111). Add one `programDisplayName` helper.

### Wave 4 — Bugs in planning/secondary surfaces
22. **"Select Lift" shows no options** — Settings exercise editor filters to `.tm/.volume` only, excluding every non-SBS program (SettingsView.swift:1447-1449); day picker hardcodes 1...5 (SettingsView.swift:1355).
23. **TM zeros in cycle builder** — three causes: `?? 0` for missing initial maxes short-circuits the fallback chain which never consults `userData.trainingMaxes` (ProgramEngine.swift:422/442, AppState.swift:1940); swipeable TabView pages bypass initialization (CycleBuilderView.swift:117-176); "Reset to Default Values" is a no-op (CycleBuilderView.swift:1168-1187).
24. **Week not reset on program switch** — unclamped `selectedWeek` getter + reset conditional on `hasLoggedData` (AppState.swift:26, 248-284); `try?` swallows the resulting `invalidWeek` so views render empty.
25. **Swapping a structured main lift destroys its set scheme** — rebuilt DayItem drops `setsDetail`/`sets`/`reps` (CycleBuilderView.swift:857-869).
26. **Metric plate calculator computes plates in lb for kg input** (CalculatorsView.swift:813-930 + PlateCalculator.swift:63-104); bar-weight pickers disagree between Settings and builder (33/44 vs 35/45/55).
27. **Metric rounding drift** — "2.5 kg" is implemented as 5.5 lb; users see 99.8 kg instead of 100 (SettingsView.swift:144-157, Theme.swift:206-214).
28. **nSuns progression can double** — +5 lb rounds to +10 with 10-lb rounding; increments don't scale for kg (ProgramEngine.swift:330-371).
29. **Lift-name canonicalization** — "OHP" lives only in legacy code aliases (JSONs are consistent), but Incline is split three ways and Close-Grip/Rack Pull/plural variants miss the ExerciseLibrary, breaking TM carry-over and body-part volume. Add `canonicalLiftName(_:)` applied at every read/write.
30. Past-cycle detail is SBS-only and hardcodes 20 weeks; duplicate program-metadata maps already diverged (ProgramSelector vs ProgramsView); ExerciseLibrary has duplicate IDs across body parts.

### Wave 5 — Conversion & delight (you have 1 purchase; these matter)
31. **Paywall shows hardcoded fallback prices** ($14.99/$0.99/$2.99) whenever products haven't loaded — trust + App Store review risk (StoreManager.swift:97-109). No retry on load failure; Restore gives zero feedback; Ask-to-Buy pending is silent; subscription group levels inverted in SBS.storekit.
32. **Wrong paywall attribution** — locked Supersets/Apple Fitness rows open a "Plate Calculator" paywall (CycleBuilderView.swift:1641).
33. **Share images always render light-mode** and `drawHierarchy` off-window can produce blanks; use ImageRenderer with explicit colorScheme + scale 3 (WorkoutShareCard.swift:417-437, 1459-1464).
34. **PR celebration renders on an opaque gray screen**, not over the dimmed workout — needs `.presentationBackground(.clear)` (WorkoutView.swift:665-683). No "Share this PR" CTA on the celebration. `recordPRAchieved` review trigger is dead code.
35. **Review-rating dialog fires during the workout-complete celebration** (WorkoutView.swift:1157-1167) — defer it.
36. **Onboarding: killed mid-flow loses everything, no skip path** (ContentView.swift:36-47); quiz can be swiped past without answering; nothing mentions custom templates.
37. Free tier gives away nSuns 5-day + 5/3/1 BBB while the paywall sells "All Training Programs" — the top of the free tier likely cannibalizes upgrades (FeatureAccess.swift:106-112).

### Uncommitted rest-timer-pill work: verdict
Solid. Status transitions published from every path, exits clean up, foreground-banner suppression is right. Follow-ups: pill bottom padding hardcodes 58pt (use `safeAreaInset`); pill tick not aligned to timer second boundaries; `consumeAccessoryEasyFlags` not called on the "Save to Apple Fitness" exit path; PR-celebration cover flips `isWorkoutScreenVisible` false.

---

# Full report 1 — Core in-workout flow

## Known bug 1 — "PR Celebration skips a set" (root cause)

**Severity: HIGH — WorkoutView.swift:597-655 (onSave), :1216-1272 (handleSetComplete), :958-1004 (handleSetCompleteFromWatch)**

The celebration itself is innocent. `completeSetAndStartTimer()` runs *before* the celebration shows (line 641), and the cover's `onDismiss` (lines 674-679) only resets flags — pressing Continue executes no set logic. The skip comes from a **second, unguarded completion landing during the celebration window**, which the user only discovers after tapping Continue:

1. **Re-entrant `onSave` from the rep-input sheet.** In the PR path, `showingRepInput = false` starts the sheet's ~0.4 s dismissal animation, but the NumberPad ✓ key stays fully tappable during it and after the state has already advanced to the next exercise's set 1. A second tap re-runs `onSave`: `logReps` runs again (now `isNewPR == false`, since `newE1RM > previousE1RM` fails on equal values — AppState.swift:933), so it falls through to the *unguarded* `completeSetAndStartTimer()` at line 654 — marking **Bench set 1** complete and moving the timer to "Set 2 of Bench", exactly the reported symptom. Note `handleSetComplete` has an already-completed guard (line 1236); `onSave` has none. The duplicate `logReps` also appends a duplicate `LiftRecord`/workout record to history.
2. **Watch race with a stale guard.** `handleSetCompleteFromWatch` guards with `isSetCompleted(workoutState.currentSetNumber)` (line 962) — but by the time a Watch "Done" for the squat AMRAP arrives, `currentSetNumber` is already Bench set 1 (not completed), so the guard passes and the *next* set is completed. The completion message carries no identity of which set it was for (WatchSessionManager.swift:158).

**Fix:** give every completion an identity. Capture `(exerciseIndex, setNumber)` when the sheet is presented / state is synced to the Watch, and have `completeSetAndStartTimer` no-op if that exact set is already completed. Additionally disable the NumberPad ✓ (or set a local `didConfirm` flag) after the first confirm.

## Known bug 2 — internal program name instead of display name

**Severity: HIGH — CycleBuilderView.swift:1699-1705 (SummaryStepView.programName), fed by AppState.swift:2175-2178**

The "Ready to Begin!" summary resolves the name via:
```swift
return programInfo?.displayName ?? appState.programInfo?.name ?? selectedProgram
```
Both fallbacks leak internals:
- `appState.programInfo` (AppState.swift:2175) returns `programData.name` — the raw JSON `name`, which for several bundled programs deliberately differs from the trademark-safe `displayName` (e.g. `greyskull_lp_12week.json` name "Greyskull LP (Phrak's)" vs displayName "AMRAP Basics"; `sbs_program_config.json` name "SBS Hypertrophy Template - 5 day" vs "Smart Hypertrophy"). It is also the *currently loaded* program, not the one being selected.
- `selectedProgram` is the raw file id (`"stronglifts_5x5_12week"`, `"custom_template_<UUID>"`).

The fallbacks are hit whenever `availablePrograms.first { $0.id == selectedProgram }` misses: `discoverAvailablePrograms()` is async (AppState.swift:161-211) and may not have completed during onboarding, and custom-template ids miss the list whenever the template lookup fails. The same `?? programData?.name` fallback appears at the top of the workout tab (HomeView.swift:88) and SettingsView.swift:111 — displaying the internal/trademarked `name` any time `displayName` is absent.

**Fix:** add a single `AppState.programDisplayName` (displayName → name only, never id) and use it everywhere; in SummaryStepView drop the `appState.programInfo?.name` and `selectedProgram` fallbacks (use a neutral "Your Program" placeholder if lookup misses), and make sure the summary re-resolves once `availablePrograms` populates.

## High

1. **HIGH — AccessoryWorkoutView.swift:339-344 + :435-453 — all accessory progress is wiped by a tab switch.** `setupAccessories()` runs on every `onAppear` with no `guard accessories.isEmpty` (unlike `setupWorkout()`, WorkoutView.swift:828) and rebuilds `AccessoryItem`s with fresh `UUID()`s, orphaning every key in `completedSets`. Switch to another tab mid-accessory-workout (a flow the new RestTimerPill actively encourages) and return: all completed-set checkmarks and the progress bar reset to zero. Fix: `guard workoutState.accessories.isEmpty else { return }`, mirroring WorkoutView.

2. **HIGH — WorkoutView.swift:1323-1338 (and AccessoryWorkoutView.swift:470-501) — Live Activity and rest-complete notification restart at FULL duration on every resume.** `resumeTimerLoopIfNeeded()` → `startTimerLoop()` passes `appState.settings.restTimerDuration` to `LiveActivityManager.startTimer` and `scheduleRestTimerNotification`, ignoring `timerRemaining`. Return to the workout with 40 s left of 120 s and the lock-screen countdown resets to 2:00 and the "Rest Complete!" push fires 80 s late. The correct pattern already exists in the resume/adjust callbacks (WorkoutView.swift:484-490, 1297-1306). Fix: pass `workoutState.timerRemaining` when resuming, or split "start" from "resume" paths.

3. **HIGH — WorkoutView.swift:548-557 + :288-315 — jumping exercises mid-rest orphans the Live Activity and the pending notification.** `jumpToExercise` clears the in-app timer and `RestTimerStatus`, and the picker's `onSelect` calls `stopTimer()` (Timer object only) — but nobody calls `LiveActivityManager.endTimerSync()` or `NotificationManager.cancelRestTimerNotification()`. The Dynamic Island keeps counting a dead timer and a stale "Rest Complete!" banner fires later. Every other timer-kill path (skip, exits, finish) cleans both up.

## Medium

4. **MEDIUM — WorkoutView.swift:1393-1396 — stale timer-end fanfare on return.** If the rest timer expired while you were on another tab, re-entering the workout runs `handleTimerEnd()` → `playTimerEndFeedback()`: full triple-buzz + chime possibly minutes after the rest actually ended, and *in addition to* the foreground banner+sound the new `willPresent` logic (NotificationManager.swift:30-42) already played. Suppress feedback when the expiry wasn't just now (e.g. `endDate` more than a couple of seconds past).

5. **MEDIUM — WorkoutView.swift:665-683 — PR celebration renders over an opaque background, not the dimmed workout.** `.background(Color.clear)` on fullScreenCover content does not make the cover transparent; the `Color.black.opacity(0.7)` scrim composites onto the system background (light mode: a plain gray screen; the workout visibly vanishes behind it). Use `.presentationBackground(.clear)` (iOS 16.4+) so the celebration actually dims the live workout. Also, presenting the cover fires WorkoutView's `onDisappear`, so during the celebration `isWorkoutScreenVisible == false` — if the rest timer expires mid-celebration the user gets a banner+sound *inside the app* (NotificationManager.swift:40) on top of the celebration.

6. **MEDIUM — WorkoutView.swift:1504-1518 — editing a superset accessory's weight erases its "easy" nudge.** `updateAccessoryWeight` rebuilds `SupersetAccessoryData` without `lastWasEasy` and calls `logAccessory` without `wasEasy`, clobbering the stored flag — inconsistent with `updateStandaloneAccessoryWeight` (1567-1584), which the uncommitted diff carefully fixed to preserve it. Pass the flags through here too.

7. **MEDIUM — WorkoutView.swift:199-204, :231-237 — completion/advance logic ignores skipped exercises.** `isWorkoutComplete` only checks the *last* exercise, so finishing the final exercise shows the "Workout Complete!" screen even when an earlier exercise (skipped via the picker) has zero sets done. Likewise `markSetComplete` auto-advances to the next exercise even if it is already fully complete instead of the next *incomplete* one. Advance to the first incomplete exercise, and gate the complete screen (or add a "N sets remaining in Squat" notice) on all exercises.

8. **MEDIUM — AccessoryWorkoutView.swift:132-139 — `selectAccessory` set-resume logic is wrong for non-contiguous completion and inconsistent with WorkoutView.** `currentSetNumber = completedCount + 1` lands on an already-completed set if sets were done out of order, whereas `jumpToExercise` (WorkoutView.swift:300-314) correctly finds the first incomplete set. Also `guard index < accessories.count` doesn't reject negative indices. Reuse the first-incomplete-set scan.

9. **MEDIUM — AccessoryWorkoutView.swift — screen sleeps during accessory workouts.** WorkoutView sets `UIApplication.shared.isIdleTimerDisabled = true` (line 791); AccessoryWorkoutView never does. Mid-set with chalky hands, the accessory flow dims and locks. Mirror the idle-timer handling (and its onDisappear reset).

10. **MEDIUM — TimerView vs AccessoryTimerView/StandaloneTimerView — three diverging copies of the same timer.** The workout timer got ±15 s adjust buttons (WorkoutView.swift:2496-2561) and the "of M:SS" label fix; the accessory and standalone timers have neither, and their color ramps differ: workout uses accentSecondary→accent→warning (WorkoutView.swift:2619-2627 — note `accentFallback` orange and `warning` orange are nearly indistinguishable in the ≤30 s vs ≤10 s states), accessory uses accentSecondary-dim→accentSecondary→warning (AccessoryWorkoutView.swift:922-930). Same concept, three behaviors. Extract one rest-timer component.

11. **MEDIUM — Dynamic Type is systematically absent.** Every font in Theme.swift:38-92 is a fixed point size with no `relativeTo:`, and the workout surfaces add more fixed sizes on top (56 pt weight at WorkoutView.swift:2013/2090/2163, 48 pt timer, 32 pt weight TextField at SessionView.swift:798, 9 pt set labels at WorkoutView.swift:2398, NumberPad keys locked to height 48). At accessibility text sizes nothing scales — a hard gap for a premium app. Convert SBSFonts to `.system(.title, design:…)`-style or `relativeTo:` fonts and audit fixed frames.

12. **MEDIUM — CycleBuilderView.swift:444 — "Ready to start a new 20-week cycle?" is hardcoded** while every non-SBS program is 12 weeks (and custom templates vary). Use the selected program's week count. (Related to the text-wrapping item in bug_report.md for the same block.)

13. **MEDIUM — ContentView diff (MainTabView overlay) — `padding(.bottom, 58)` hardcodes tab-bar clearance** for the RestTimerPill; wrong on devices/orientations where the tab bar isn't 58 pt and at larger text sizes. Use `.safeAreaInset(edge: .bottom)` or read the tab bar via safe-area geometry. Also the pill's tap assumes the workout lives in the Home tab's stack — fine today, but a comment-enforced invariant.

## Low

14. **LOW — WorkoutView.swift:1808 — `.padding(.leading, 40) // Account for navigation bar X button`** — the header hardcodes clearance for a toolbar item that isn't 40 pt in all configurations; the header also isn't under the nav bar, so the offset reads as a misaligned left margin.
15. **LOW — long exercise names truncate with `lineLimit(1)`** in the progress header (1778), NextSetPreview (2677), SupersetAccessoryCard (2766), and ExercisePickerRow (3316). "Single-Arm Dumbbell Row — Left" becomes "Single-Arm Dumbb…". Allow 2 lines with `minimumScaleFactor` on the header.
16. **LOW — NumberPad.swift:61 — `onCancel` parameter is dead** (never used in the body); every caller passes it. Remove or wire it to a pad-level cancel key.
17. **LOW — haptic inconsistency:** NumberPad digits and ±15 s give light impacts, ✓ gives success, timer-end gives a triple pattern — but "Complete Set" (the most-pressed button in the app), Skip, and Pause/Resume give no haptic at all. Add a light/medium impact to set completion for consistency.
18. **LOW — RestTimerPill.swift:35 — `accessibilityLabel` sits outside the `TimelineView`**, so VoiceOver's remaining-seconds text only refreshes when the observable status changes, not each second. Move it inside the timeline closure. (Also consider announcing minutes:seconds instead of raw seconds.)
19. **LOW — SessionView.swift:136-152 — when PR celebrations are disabled, `prResult` is set and never cleared** (harmless stale state, but it means a later unrelated `showingPRCelebration = true` would show the old PR).
20. **LOW — SessionView.swift:449-536 — AccessoryWorkoutCard button says "Start Timer" even when titled "Accessory Workout"**; the button starts the accessory workout flow. Label it "Start Accessory Workout" when `hasAccessories`.
21. **LOW — StandaloneTimerView (AccessoryWorkoutView.swift:1240/1320) — timer-end swaps the whole layout back to the start screen with no transition**; a `withAnimation`/`.transition` would remove the pop. Same abruptness when `showingTimer` flips in WorkoutView (TimerView ↔ CurrentSetView swap is unanimated).
22. **LOW — WorkoutView.swift:1727 — share summary `duration: nil` always**, so the share card can never show workout duration despite the model supporting it; capture a start date in `WorkoutState`.
23. **LOW — Theme.swift:5-18 — the asset-catalog colors (`SBSColors.background`, `.accent`, etc.) are defined but every call site uses the `*Fallback` variants**, so the design system's real palette can never be adopted without a sweep. Either delete the asset-backed set or migrate to it.

## Uncommitted rest-timer diff — verdict

The diff itself is solid: `RestTimerStatus` transitions are published from every start/pause/resume/adjust/clear path in both workout states, all exit paths now clear the mirror and cancel the notification, and the `willPresent` foreground-banner logic is the right call. Two follow-ups beyond items 2/5/13 above: (a) `RestTimerStatus.isWorkoutScreenVisible` is also flipped false by the PR-celebration fullScreenCover, which momentarily shows the pill state machine "off-screen" — harmless today but worth a comment; (b) `consumeAccessoryEasyFlags` is only called from `finishAndDismiss`, so exiting via "Save to Apple Fitness" (which does persist a workout) leaves easy flags un-consumed — decide if that's intended.

## Done well

- Wall-clock (`endDate`) based timers with `recalculateTimerIfNeeded` — rest timers survive backgrounding, navigation, and celebration covers correctly.
- `toggleCurrentAccessoryEasy` deliberately avoiding `logAccessory` to prevent note clobbering and spurious history rows — thoughtful, well-commented (WorkoutView.swift:1530-1542).
- `handleSetComplete`'s already-completed guard and the structured-set index bounds checks (`safe` subscript, consistent `0 < n <= count` guards) are careful.
- Live Activity is now ended on the normal-completion path, not just aborts (the orphan fix, with a clear comment).
- The rep NumberPad with live TM-impact preview is a genuinely premium interaction; disabled/enabled states and haptics on it are right.
- ExercisePickerSheet: scroll-to-current, overview summary with PR count, CURRENT/IN PROGRESS/DONE badges — nice.
- WeightOverrideSheet only enables Save when the value is valid *and* different from calculated.
- Light/dark handled uniformly through the `Color(light:dark:)` helper; the pill's `.regularMaterial` + expired-state color flip is a nice touch.

---

# Full report 2 — State, persistence, program logic, monetization gating

## Known bug 1 — "Strength Scores not showing even after premium upgrade"

**Root cause A (Calculators): entitlement passed as a constructor snapshot, not read live.**
- (a) HIGH
- (b) `SBSApp/Views/CalculatorsView.swift:74` and `:1552` (`var canImportPRs: Bool = true`)
- (c) `StrengthScoresView` receives `canImportPRs` as a plain `let` captured when the NavigationLink destination is built, so a purchase made afterwards never unlocks the screen.
- (d) Free user opens Calculators → Strength Scores, taps the locked "From PRs" button (`CalculatorsView.swift:1827-1828`), buys premium in the paywall sheet, sheet dismisses → "From PRs" is still locked with the premium badge (`:1804-1851`), and the `.onAppear`-only mode selection (`:1776-1783`) never re-runs. Persists until they pop and re-push the screen.
- (e) Drop the parameter; read `StoreManager.shared.canAccess(.e1rmChart)` directly inside `StrengthScoresView.body` (StoreManager is `@Observable`, so the view will invalidate on purchase). Audit for the same pattern elsewhere (`ProgramSelector.swift:288/360` passes `isPremiumUser: Bool` down two levels — safe today only because the parent re-renders, but fragile).

**Root cause B (History + app-wide): entitlement refresh is sequenced behind a network product fetch.**
- (a) HIGH
- (b) `SBSCore/StoreManager.swift:121-124`
- (c) `init` runs `Task { await loadProducts(); await updatePurchasedProducts() }` — the local-entitlement check (`Transaction.currentEntitlements`) cannot run until the App Store `Product.products(for:)` call returns or fails, and there is no retry on failure.
- (d) Paid user launches the app offline or on a slow connection: `isPremium` stays `false` for seconds (or the whole session if the fetch hangs), so HistoryView's live gates (`HistoryView.swift:258-270`, badge at `:474-494`, card gate at `:570`) and Calculators show the premium badge despite a completed purchase. This is the only mechanism in the code that keeps *History* locked, since its gates are otherwise computed live per body evaluation.
- (e) Reorder to `await updatePurchasedProducts(); await loadProducts()` (entitlements don't need products), and re-run `updatePurchasedProducts()` on `scenePhase == .active`.

**Contributing: even when unlocked, bench PR import is broken by a lift-name mismatch.**
- (a) MEDIUM — `SBSApp/Views/CalculatorsView.swift:1584` reads `personalRecords["Bench"]`, but every program logs the lift as `"Bench Press"` (all 18 JSONs). Premium users importing "From PRs" get a zero bench, making the feature look still-broken post-purchase. Fix: `personalRecords["Bench Press"] ?? personalRecords["Bench"]` (HistoryView already does this at `HistoryView.swift:280`, `:574`).

## Known bug 2 — "Starting a new program should reset Workout State"

- (a) HIGH
- (b) `SBSApp/AppState.swift:26` (getter), `:248-284` (conditional reset), plus `SBSCore/ProgramEngine.swift:94` + `AppState.swift:407`
- (c) `selectedWeek`'s getter returns `settings.currentWeek` unclamped (only the setter clamps, `:28-29`), and `loadProgram` resets week/day only when `isSwitchingPrograms && hasLoggedData` — so switching programs with no logged main-lift work keeps the stale week.
- (d) User is on week 15 of the 21-week SBS program (browsed or reset, nothing logged — note `hasLoggedData`, `AppState.swift:1996-2031`, ignores accessory logs and `workoutRecords`), switches to a 12-week program. `settings.currentWeek` stays 15; `engine.weekPlan(state:week:15)` throws `invalidWeek` at `ProgramEngine.swift:94`, which `try?` silently swallows at `AppState.swift:407` → `currentDayPlan()` is nil → WorkoutView/Home render empty/stale. Note the asymmetry: `selectedDay`'s *getter* self-heals (`:39-48`) but `selectedWeek`'s does not.
- (e) Clamp in the getter (`settings.currentWeek.clamped(to: 1...(programState?.weeks.max() ?? 20))`), and unconditionally reset `currentWeek/currentDay = 1` whenever `userData.selectedProgram` actually changes in `loadProgram` (not only when `hasLoggedData`).

**Related destructive side effect worth fixing in the same pass:**
- (a) HIGH (data loss)
- (b) `SBSApp/Views/CycleBuilderView.swift:225-238` and `:286-314`; `SBSApp/AppState.swift:251-284` vs validation at `:287-290`/`:338-340`
- (c) `loadProgram` archives the current cycle, wipes `logs/structuredLogs/linearLogs/workoutRecords`, and commits the program switch as a side effect of merely *navigating* the cycle builder (onAppear / "Continue"), before the user confirms — and the destructive work happens *before* the `configNotFound` guards.
- (d) User taps a program in ProgramsView, the builder opens and immediately loads it, then they hit the X (`ProgramsView.swift:246-249`): their cycle has already been archived, logs cleared, and the app is switched to the new program. Or: `loadProgram` is called with a stale/deleted custom-template id → logs wiped, then throws.
- (e) Validate the target program first; defer all destructive archival/clearing to `startNewCycleWithBuilder`/an explicit commit step, loading the candidate program into a scratch `ProgramState` for preview.

## Known bug 3 — "Use current training maxes for new cycle just showing zeros"

- (a) HIGH
- (b) Chain of three: `SBSCore/ProgramEngine.swift:422` and `:442`; `SBSApp/AppState.swift:1898-1908` and fallback at `:1940-1942`; `SBSApp/Views/CycleBuilderView.swift:1168-1177`
- (c) `computeStructuredTrainingMaxes` coalesces a missing initial max to **0 instead of nil** (`state.initialMaxes[lift] ?? 0`); `finalTrainingMaxes` then short-circuits on that non-nil 0 (`if let tm = structuredTMs[targetWeek]?[lift] { result[lift] = tm; continue }`) and **never consults `userData.trainingMaxes`** (the universal TMs) anywhere in its fallback chain; and the "Use Current Training Maxes" button copies that output verbatim into the fields with no `> 0` filter — unlike `initializeTrainingMaxes` (`CycleBuilderView.swift:316-340`), which does have the 4-level fallback.
- (d) Every structured program (5/3/1, nSuns, GZCLP, Greyskull — most of the catalog) ships **no** `initial_maxes` in its JSON (verified: none of the 21 Resources files has the key; decode defaults to `[:]` at `ProgramModels.swift:543`), and `loadProgram` clears `customInitialMaxes` when switching to a program with no saved customizations (`AppState.swift:294-299`, `:342-349`). So in the builder, `finalTrainingMaxes` returns literal 0 for every structured lift even though the user's real TMs sit in `userData.trainingMaxes`; tapping "Use Current Training Maxes" fills every field with 0.
- (e) In `computeStructuredTrainingMaxes`, skip lifts with no initial max instead of emitting 0 (or treat 0 as nil in `finalTrainingMaxes`); add `userData.trainingMaxes[lift]` to `finalTrainingMaxes`' fallback chain (`AppState.swift:1940`); and give the toggle button (`CycleBuilderView.swift:1173-1176`) the same `> 0` + fallback chain as `initializeTrainingMaxes`.

## Known bug 4 — Press/lift terminology inconsistent across programs

- (a) MEDIUM
- (b) Evidence spread: Resources JSONs; `SBSCore/ExerciseLibrary.swift:142-145`, `:173-180`; `SBSApp/Views/HistoryView.swift:88-93`; `SBSApp/Views/CalculatorsView.swift:1584`
- (c) There is no canonical lift-ID layer — TM continuity, PRs, and body-part resolution all key on exact display strings, and those strings drift across programs and code.
- (d) Concrete findings from a full survey of `"lift"` values in all 21 program JSONs:
  - **"Overhead Press" is actually consistent** in all 18 bundled programs that have it — the OHP variants ("OHP", "Press") exist only in *code* as legacy aliases (`HistoryView.swift:92`, abbreviation maps at `HistoryView.swift:2129` / `PastCyclesView.swift:181`), so old logged data or custom templates using "OHP" split into a separate history/TM bucket; the alias table at `HistoryView.swift:88-93` is used **only for sort ordering** in alphabetical mode, never for merging TMs or history.
  - Incline is split three ways: `"Incline Bench"` (nsuns_5day, both nsuns_6day files) vs `"Incline Press"` (sbs_program_config, back_friendly_hypertrophy) vs `"Incline Bench Press"` (phul, basic_ppl). A user moving nSuns → PHUL loses their incline TM (`userData.trainingMaxes` miss → cycle-builder zero, see bug 3).
  - `"Close-Grip Bench"` (3 nsuns files) vs library `"Close Grip Bench Press"` (`ExerciseLibrary.swift:176`); also `"Rack Pull"` vs library `"Rack Pulls"`, `"Paused Squat"` vs `"Pause Squats"`, `"Hang Clean"` vs `"Hang Cleans"`, `"Cable Rows"` vs `"Cable Row"`; `"Spoto Press"`, `"Weighted Dips"`, `"Weighted Pull-Ups"`, `"Incline Press"` are absent from the library entirely. `ExerciseLibrary.bodyPart(for:)` is exact-match (`:142-145`), so all of these fall into "Other" — the stated reason the volume card is feature-flagged off (`HistoryView.swift:79-82`).
  - `personalRecords["Bench"]` in `CalculatorsView.swift:1584` (see bug 1).
- (e) Add a `canonicalLiftName(_:)` normalization (alias map: OHP/Press→Overhead Press, Incline Bench/Incline Press→Incline Bench Press, Close-Grip Bench→Close Grip Bench Press, singular/plural) applied at every read/write of `trainingMaxes`, `personalRecords`, `liftHistory`, and in `ExerciseLibrary.bodyPart(for:)`; align the three nsuns/sbs/back-friendly JSONs to the library names; add the missing library entries.

## Additional findings

**HIGH — silent total data wipe on decode failure, no versioning.**
`SBSCore/Persistence.swift:528-534` — `loadUserData()` does `try? decoder.decode(...)` and returns `.empty` on *any* failure. If a future app version writes a field an older build can't decode, or the blob is corrupt, the user launches to a blank app and the very next `didSet` save (`AppState.swift:20-22`) overwrites the store, permanently destroying all history. There is no schema-version field and no backup copy. Fix: on decode failure, preserve the raw blob under a `sbs_user_data_backup` key before returning `.empty`, log the error, and add a version field. (The custom `init(from:)` at `Persistence.swift:324-343` is good defensive work, but it can't save you from corruption or a type change in a nested Codable.)

**MEDIUM — save-path failures are silently swallowed and saves are heavyweight.**
`SBSApp/AppState.swift:1822-1828` — `try?` on both persist helpers; an encode failure means every subsequent workout is silently unsaved. Also every single mutation re-encodes the *entire* `UserData` (all `liftHistory`, `workoutRecords`, `cycleHistory`) with `.prettyPrinted, .sortedKeys` (`Persistence.swift:503`) synchronously on the main thread — and one `logReps` call mutates `userData` at least 3 times (log write `:882`, `recordLift` `:912`, `recordSetToWorkout` → append + explicit `persistUserData()` `:842`), so 3+ full encodes per tap. This will jank scrolling/tapping as history grows. Fix: at minimum log failures and drop `.prettyPrinted`; ideally debounce/coalesce saves.

**MEDIUM — accessory-only cycles are silently discarded.**
`SBSApp/AppState.swift:1996-2031` — `hasLoggedData` checks only `logs/structuredLogs/linearLogs`. A user who logged only accessories (or whose data lives only in `workoutRecords`) gets no archive on program switch, and `loadProgram:280` still deletes their `workoutRecords` for the cycle window when it *does* archive. Include `workoutRecords`/`accessoryHistory` in the check.

**MEDIUM — ExerciseLibrary duplicate IDs and order-dependent body-part resolution.**
`SBSCore/ExerciseLibrary.swift:211/238` ("Face Pulls" in Back and Shoulders), `:214/331` ("Romanian Deadlift" Back + Hamstrings), `:215/338` ("Good Mornings"), `:273/351` ("Cable Kickbacks"), `:283/382` ("Farmer's Walk"). IDs are name-derived (`:22`), so these are duplicate `Identifiable` IDs (ForEach undefined behavior in any all-exercise list) and `bodyPart(for:)`'s `.first` match (`:144`) silently picks whichever was appended first — RDL volume counts as Back, never Hamstrings. Deduplicate or qualify IDs and decide a primary body part.

**MEDIUM — metric rounding is an approximation that produces un-clean kg values.**
`SBSApp/Views/SettingsView.swift:144,155-157` — "1 / 2.5 / 5 kg" rounding is implemented as 2.2 / 5.5 / 11.0 **lb** (2.5 kg = 5.51155 lb), and `formattedWeight` (`Theme.swift:206-214`) converts the lb-rounded value with `× 0.453592`. Result: a metric user sees 99.8 kg where 100.0 kg is expected, and increments drift (5.5 lb = 2.4948 kg). Bar "20 kg" is 44 lb = 19.96 kg. For a premium feel, either store/round natively in kg when `useMetric`, or use exact conversions (2.20462) and round the *displayed* kg to the chosen kg increment.

**MEDIUM — structured progression increments interact badly with rounding and units.**
`SBSCore/ProgramEngine.swift:330-371` — the +5/+10/+15 lb adjustments are rounded to the user's rounding increment: with 10-lb rounding, +5 rounds to +10 (`roundTo(5, 10)` → 10), doubling nSuns progression; with metric "2.5 kg" (5.5), +5 becomes +5.5. And the constants are pounds regardless of metric setting. Apply progression before rounding the *weight* (don't round the TM delta), and scale constants for kg users.

**LOW — CSV export hardcodes set count.**
`SBSCore/CSVExporter.swift:24` — volume rows always export `Sets = "4"` even though the actual `sets` value is right there in the `PlanItem.volume` case (discarded by `_`). One-line fix.

**LOW — dead second source of truth in gating.**
`SBSCore/FeatureAccess.swift:117-120` — `canAccess(_:)` ignores its `feature` parameter (fine, all-or-nothing), but `FreeTierLimits.e1rmChartEnabled` / `plateCalculatorEnabled` / `visiblePastCycles` (`:174-180`) are never read anywhere — delete them before someone gates against them instead of `canAccess`. `maxSavedTemplates` *is* used (TemplateListView:248, ProgramsView:633) and is consistent.

**LOW — stale saved customizations can't be cleared.**
`SBSCore/Persistence.swift:453-462` — `saveCustomizations` skips saving when empty, so a user who removes all customizations, leaves the program, and returns gets the old customizations restored. Save unconditionally (or remove the key when empty).

**LOW — workout records split across midnight / empty programId.**
`SBSApp/AppState.swift:749-773` — `findOrCreateWorkoutRecord` matches on same-calendar-day, so a session spanning midnight produces two records; `programId` falls back to `""` when `selectedProgram` is nil.

**LOW — unlogged weeks can silently progress TMs.**
`SBSCore/ProgramEngine.swift:71-73` — a week with no log applies the `hitTarget` adjustment. Default is 0, but `hitTarget` is user-editable (`WeightAdjustments`), so a user who sets "hit target = +0.5%" gets TM growth across weeks they skipped entirely. Use a hard 0 for missing logs.

**LOW — singleton listener retain cycle / dead cancel.**
`SBSCore/StoreManager.swift:218-235` — `Task.detached` strongly captures `self`; harmless for a singleton but makes `deinit`'s cancel (`:127-129`) dead code. Also `weekPlan`/`trainingMax`/`finalTrainingMaxes` (`AppState.swift:393-408`, `:485-512`, `:1876+`) mutate `programState` during view-body evaluation — safe only because `ProgramState` isn't observable; worth a comment so nobody makes it `@Observable` later. No actual off-main mutations found: `AppState` mutations occur from MainActor contexts, and `StoreManager`'s published-state writes are all `@MainActor`.

---

# Full report 3 — Rest timer / notifications / Live Activity / Watch

## HIGH severity

**H1. Returning to the workout tab resets the Live Activity and notification to the full duration**
- File: SBSApp/Views/WorkoutView.swift:1386-1397 (`resumeTimerLoopIfNeeded` → `startTimerLoop` at 1316-1338); same pattern in SBSApp/Views/AccessoryWorkoutView.swift:539-550 (→ 466-502)
- Defect: `startTimerLoop()` always starts a fresh Live Activity and schedules the notification with `appState.settings.restTimerDuration` (full duration), but it is also the resume path after `onDisappear`/`onAppear`.
- Scenario: Start a 2:00 rest, switch to the History tab at 1:20 remaining, switch back. In-app timer correctly shows ~1:15 (end-date based), but the Dynamic Island/lock screen restarts at 2:00 and the "Rest Complete" notification is rescheduled to fire a full 2:00 later. All surfaces now disagree, and the background alert fires ~45s late.
- Fix: In `startTimerLoop`, drive Live Activity and notification from `workoutState.timerEndDate`/`timerRemaining`, not from settings. Better: split "start surfaces" (LA + notification, done once in `completeSetAndStartTimer`) from "restart tick loop" (done on reappear), so reappearing never re-creates the LA or reschedules the notification.

**H2. Resuming a paused timer after a tab switch leaves the in-app countdown frozen**
- File: SBSApp/Views/WorkoutView.swift:2510-2517 (pause/resume button never restarts the loop); resume guard at 1391 (`timerIsRunning && ...` skips paused timers); same in AccessoryWorkoutView.swift:~856 and ~1282
- Defect: Resume relies on the 1s `Timer` still running, but `resumeTimerLoopIfNeeded()` doesn't restart the loop for a paused timer, and pause + tab switch invalidates it (`invalidateTimerOnly`).
- Scenario: Pause the rest timer, switch to Settings tab, come back, tap play. `timerIsRunning` becomes true and the notification is scheduled, but no `Timer` exists: the on-screen countdown never moves, `onChange(of: timerRemaining)` never fires, `handleTimerEnd()` never runs, the Live Activity is never ended, and no end haptic/chime plays. Meanwhile the pill and notification (from `RestTimerStatus`/`endDate`) keep counting — surfaces diverge.
- Fix: Have the resume action call the view's resume handler which invokes `startTimerLoop()` (with H1's fix so it doesn't reset surfaces), or make `resumeTimerLoopIfNeeded` also restart the loop when `timerIsPaused`.

**H3. Live Activity widget can crash on an expired timer: `Date()...endTime` with endTime in the past**
- File: RestTimerWidget/RestTimerLiveActivity.swift:35, 80, 199 (`Text(timerInterval: Date()...context.state.endTime, ...)`)
- Defect: `ClosedRange` traps ("lowerBound <= upperBound") when `endTime < Date()`. `endActivity` posts a final state with `endTime: Date()` (LiveActivityManager.swift:80-89), and per-tick updates set `endTime = now + 0` at expiry, so the widget process can evaluate `Date()` microseconds after `endTime` and crash, leaving a frozen/stale activity on the lock screen.
- Fix: Clamp: `Text(timerInterval: min(Date(), context.state.endTime)...context.state.endTime)` or precompute `let end = max(context.state.endTime, Date())`; apply to all three sites.

**H4. Watch rest timer freezes whenever the phone app is backgrounded**
- Files: SBSApp/Views/WorkoutView.swift:1343-1368 (tick loop is the only sender), SBSCore/WatchConnectivityManager.swift:174-196, SBSWatch/WatchSessionManager.swift:224-231
- Defect: The watch countdown is driven by 1/s `sendMessage` ticks from a foreground `Timer`; no end date is ever sent, and the watch does no local timekeeping.
- Scenario: User completes a set, locks the phone and puts it in the pocket, then glances at the watch: the countdown is frozen at whatever value was last delivered (and the application-context snapshot has no timestamp, so `syncFromApplicationContext` restores a stale `remaining`). The "timer ended" haptic also never arrives until the phone wakes.
- Fix: Send `endDate` (epoch) once (message + application context) and let the watch render with `TimelineView`/local computation, scheduling the end haptic locally. This also removes the 1/s message traffic.

## MEDIUM severity

**M1. Jumping to another exercise leaves the pending notification and Live Activity alive**
- Files: SBSApp/Views/WorkoutView.swift:288-296 (`jumpToExercise` clears only local state) and 552-556 (picker `onSelect` calls only `stopTimer()`); SBSApp/Views/AccessoryWorkoutView.swift:273-276 (menu: `skipTimer` + `stopTimer` only)
- Scenario: Mid-rest, user opens the exercise list and jumps to another lift. The timer UI disappears, but 90s later a "Rest Complete! Time for Set 3..." notification fires (possibly referencing the old exercise), and the Dynamic Island keeps counting to 0:00 and sits there.
- Fix: In both jump paths, also call `NotificationManager.shared.cancelRestTimerNotification()`, `LiveActivityManager.shared.endTimerSync()`, and `WatchConnectivityManager.shared.sendRestTimerEnded()` — i.e., route through a shared `cancelRestSurfaces()` helper.

**M2. Per-second `Activity.update` with a recomputed end time causes countdown jitter and is wasted work**
- Files: SBSCore/LiveActivityManager.swift:162-188 (`endTime = Date().addingTimeInterval(TimeInterval(secondsRemaining))`), called every tick from WorkoutView.swift:1349-1354 and AccessoryWorkoutView.swift:510-515
- Defect: `secondsRemaining` is an already-ceiled Int, so the LA's `endTime` is re-derived each second with up to ~1s of jitter — the system countdown (`Text(timerInterval:)`) can visibly skip/repeat a second. The LA is end-date driven and needs zero updates while running.
- Fix: Remove `updateTimer` from the tick loop; call it only on pause/resume/±15s, and pass the authoritative `workoutState.timerEndDate` instead of recomputing from an Int.

**M3. ±15s adjustment silently rewrites the user's default rest duration to a value the Settings picker can't represent**
- Files: SBSApp/Views/WorkoutView.swift:1287-1288 (`appState.settings.restTimerDuration = newDuration`); SBSApp/Views/SettingsView.swift:354-362 (Picker with fixed tags 60/90/120/150/180/240/300)
- Scenario: User taps +15s once during a 2:00 rest → default becomes 135s. The Settings "Rest Timer" picker now shows no selected row (135 matches no tag), and every future set defaults to 2:15 without the user realizing they changed a setting.
- Fix: Either treat ±15s as session-only (don't persist), or persist and replace the picker with a stepper/wheel that supports arbitrary 15s increments.

**M4. Phone and watch each save their own HealthKit workout → duplicates; watch writes even when HealthKit sync is off**
- Files: SBSApp/Views/WorkoutView.swift:914-927 (phone `HKWorkoutBuilder`, gated by premium+setting) vs 932-948 (`setupWatchSync`/`sendWorkoutStarted` unconditional); SBSWatch/WatchWorkoutManager.swift:83-132, 190-212 (watch `HKLiveWorkoutSession` finishes and saves its own workout)
- Scenario: Premium user with the watch app: every session produces two workouts in Apple Fitness (phone estimate + watch live workout), double-counting energy/exercise minutes. Free user (or `healthKitEnabled` off) with a watch: workouts get written to HealthKit anyway via the watch, violating the setting.
- Fix: Skip the phone `HKWorkoutBuilder` when the watch session is running (watch data is strictly better), and gate `sendWorkoutStarted`/the watch session on the same `healthKitEnabled` (send the flag in the message/context).

**M5. Notification permission-denied is a silent dead end**
- Files: SBSApp/Views/SettingsView.swift:366-381; SBSCore/NotificationManager.swift:107-113
- Scenario: User denied the permission prompt once. Later they toggle "Push Notifications" on: `requestAuthorization()` returns false without any prompt, the toggle snaps back off with zero explanation. During workouts, scheduling silently no-ops, so background rest alerts never arrive and nothing tells the user why.
- Fix: When `authorizationStatus == .denied`, show an alert/footer explaining and deep-link to `UIApplication.openNotificationSettingsURLString`.

**M6. Watch stuck on "Starting Workout… Connecting to iPhone…" forever if HealthKit auth fails on the watch**
- File: SBSWatch/WatchSessionManager.swift:174-184 (`isWorkoutActive = true` before `startWorkout()`; catch only logs); SBSWatch/ContentView.swift:10-19
- Scenario: User declines HealthKit on the watch. Every workout start throws in `startWorkout()`, `sessionManager.isWorkoutActive` stays true, and ContentView shows the connecting spinner for the entire workout with no error or retry.
- Fix: Reset `isWorkoutActive = false` in the catch and surface an error state ("Allow Health access on your watch") in ContentView.

**M7. Expired Live Activity lingers indefinitely while the user stays in-app on another tab**
- Files: SBSApp/SBSApp.swift:19-35 (cleanup only on scenePhase→.active); SBSCore/LiveActivityManager.swift:44-56 (`endExpiredActivities` is never called by anyone; `forceCleanup` also dead)
- Scenario: Rest timer running, user switches to the History tab (workout view's tick loop is invalidated). Timer hits 0:00 — the pill flips to "Rest done", the notification banner shows, but the Dynamic Island/lock-screen activity sits at 0:00 until the user re-enters the workout screen or backgrounds/reopens the app.
- Fix: When `RestTimerStatus` expires while `!isWorkoutScreenVisible` (e.g., driven from the pill's timeline or a scheduled task at `endDate`), call `endExpiredActivities()`.

**M8. Live Activity progress ring wrong after ±15s adjustments**
- Files: SBSCore/RestTimerActivity.swift:25-26 (`totalDuration` is a fixed attribute); RestTimerWidget/RestTimerLiveActivity.swift:94-98, 113-117, 100-105
- Defect: `timerRange`/`pausedProgress` divide by the creation-time `totalDuration`; adjustments shift `endTime` but not the total, so the ring fraction (and paused progress, which clamps at 1) disagrees with the in-app ring.
- Scenario: 60s timer, +15s twice → LA ring computes against 60s: `start = end - 60` puts the drain 30s ahead of reality; if paused with 70s remaining, ring pins at 100%.
- Fix: Move `totalDuration` into `ContentState` (it already exists implicitly as `secondsRemaining` at start) and update it on adjust.

**M9. `.timeSensitive` interruption level without the Time Sensitive Notifications entitlement**
- Files: SBSCore/NotificationManager.swift:113; SBSApp/SBSApp.entitlements (only `com.apple.developer.healthkit`)
- Scenario: User trains with a "Fitness"/Do Not Disturb Focus enabled — exactly when a rest alert matters most — and the notification is suppressed because the time-sensitive escalation is ignored without `com.apple.developer.usernotifications.time-sensitive`.
- Fix: Add the entitlement (capability in project.yml/entitlements file), or drop the level to avoid review flak.

## LOW severity

**L1. `LiveActivityManager.startTimer` race can create two activities** — LiveActivityManager.swift:112-118. Two quick calls each spawn a Task; interleaving at `await` points can leave both `Activity.request`s executed (second task's `endAllActivities` runs before the first task's `createNewActivity`). Serialize via a stored `Task` chain (`cleanupTask = Task { await prev?.value; ... }`).

**L2. Watch shows no paused state** — the phone protocol has no `isPaused` (WatchConnectivityManager.swift:174-196); while paused the loop keeps sending the same `remaining`, so the watch countdown just looks stuck. Include `isPaused` and render a pause glyph like the LA does.

**L3. Manual Skip triggers the full "rest complete" fanfare** — WorkoutView.swift:2537-2539 routes Skip through `handleTimerEnd()` → triple haptic + chime + watch `.notification` haptic. Skipping is a deliberate action; a light tap haptic (no chime, no watch buzz) would feel more premium. Split "skip" from "completed".

**L4. Application-context timer snapshot is un-timestamped and can go stale >5s** — WatchConnectivityManager.swift:181-183: `remaining % 5 == 0` can be skipped entirely when wall-clock ticks jump values (e.g., 66→64). Subsumed by H4's endDate fix.

**L5. Context timer restore drops fields** — WatchSessionManager.swift:270-279 rebuilds state without `nextSetInfo`/`isRepOutSet`/`isAMRAPSet`, so a watch waking mid-rest loses the "Next: Set X of Y" line.

**L6. Watch `startWorkout` can stack sessions after `forceInactive()`** — WatchWorkoutManager.swift:83-84 guards on `isWorkoutActive`, which `forceInactive()` (224-230) clears without ending `session`; a quick end→start from the phone can create a second `HKWorkoutSession` while the old one is still finishing. Guard on `session == nil` instead.

**L7. Duplicate launch cleanup / dead code** — `endAllActivities()` runs twice at launch (LiveActivityManager.swift:16-19 and SBSApp.swift:10-12); `endExpiredActivities`/`forceCleanup` are uncalled. Harmless, but remove one and wire `endExpiredActivities` per M7.

**L8. Pill tick alignment** — RestTimerPill.swift:11: `.periodic(from: .now, by: 1)` isn't aligned to the timer's second boundaries, so the pill can lag the workout screen by up to 1s. Cosmetic; aligning the schedule to `endDate` fractional offset fixes it.

**L9. Accessory workout lacks ±15s** — AccessoryTimerView/StandaloneTimerView (AccessoryWorkoutView.swift:804, 1228) have no adjust buttons while the main TimerView does; also `.badge` is requested (NotificationManager.swift:58) but never used. Minor surface inconsistency.

## Done well
- End-date-based in-app timer (`timerTick`/`recalculateTimerIfNeeded`) is drift-free and survives backgrounding; the widget correctly uses system `Text(timerInterval:)`/`ProgressView(timerInterval:)` so the lock screen counts down while the app is suspended.
- `RestTimerStatus` as a single app-wide mirror is a clean design: the pill, foreground-notification suppression (NotificationManager.swift:30-42), and expired-state messaging all hang off it.
- Live Activity end-with-fresh-content + `dismissalPolicy: .immediate` and the nil-staleDate reasoning are carefully documented and correct; orphan cleanup on launch/foreground covers force-quit.
- Notification scheduling uses a single stable identifier (implicit replace) and is consistently cancelled on pause/skip/exit; ±15s correctly reschedules with the new remaining.
- M:SS formatting is consistent across pill, in-app timer, watch, and LA; the watch AMRAP rep-picker flow with optimistic haptics is a nice touch.

---

# Full report 4 — Planning/browsing/settings surfaces

## Verification of reported issues

1. Text-wrapping at CycleBuilderView.swift ~415-425
- Severity: low (mostly fixed) | CycleBuilderView.swift:413-450
- The cited lines now contain the WelcomeStep animated icon circles; the wrap-prone texts directly below (436-449) already carry `.fixedSize(horizontal: false, vertical: true)`, so the originally reported case appears fixed. Remaining fixed-height truncation risks: DayTab subtitle `lineLimit(1)` at CycleBuilderView.swift:995-998 (long day titles like "Chest & Triceps Day" clip inside the tab), DayCard lifts line `lineLimit(1)` (DayCard.swift:23-26), ProgramCard/TemplateRow descriptions `lineLimit(2)` (ProgramSelector.swift:480-483, ProgramsView.swift:798-801). None of these grow with Dynamic Type either.
- Fix: for DayTab, allow 2 lines with a min height instead of lineLimit(1); audit all `lineLimit` + fixed-frame combos.

2. "Select Lift dialog shows no options"
- Severity: high | SettingsView.swift:1447-1449
- ExerciseEditorView (Settings > Edit Exercises) filters main lifts with `dayItems.filter { $0.type == .tm || $0.type == .volume }`. Structured and linear items (5/3/1, nSuns, GZCLP, StrongLifts, Starting Strength, PPL — i.e., every program except SBS) are excluded, so the "Main Lifts" section renders zero rows and the user cannot change a primary lift at all. The library-backed picker itself (AccessoryExercisePickerSheet) is fine — ExerciseLibrary is hardcoded and non-empty.
- Fix: include `.structured` and `.linear` in the filter (match ExerciseReviewStepView's filter at CycleBuilderView.swift:719).
- Related: SettingsView.swift:1355 hardcodes the day picker to `ForEach(1...5)`. 3/4-day programs show phantom Days 4-5; 6-day programs can't edit Day 6. Use `appState.days`/`allDays`.

3. "Rest timer selector should be a dropdown"
- Severity: info | CycleBuilderView.swift:1420-1429 and SettingsView.swift:354-362
- Both in-scope rest-timer selectors are already `Picker(...).pickerStyle(.menu)` / List menu pickers. The button-group variant must live in the workout surfaces. No action needed in these files.

4. "Ready to Begin" summary shows internal program name
- Severity: medium | CycleBuilderView.swift:1700-1706
- `programName` falls back to `appState.programInfo?.name ?? selectedProgram`. Both fallbacks are internal identifiers; `appState.programData?.displayName` is never consulted. During onboarding (before `availablePrograms` lookup resolves) or with any lookup miss, the raw id is shown on the final screen.
- Fix: chain `customTemplate?.name ?? programInfo?.displayName ?? appState.programData?.displayName ?? appState.programData?.name ?? "Your Program"`; never surface the id.

5. "Use current training maxes" shows zeros — three contributing defects found
- Severity: high | CycleBuilderView.swift:316-340 (`initializeTrainingMaxes`)
  (a) TM lookup is keyed by exact lift-name string. Program JSONs disagree on names, so after switching programs, `finalTrainingMaxes` / `customInitialMaxes` / `trainingMaxes` all miss, and the last fallback `appState.initialMax(for:)` (AppState.swift:1524-1526) returns 0 when the new program's `initialMaxes` lacks that lift. Result: 0 in the field. Fix: canonicalize lift names and/or alias-match when carrying TMs across programs.
  (b) Severity: high | CycleBuilderView.swift:117-176 — the builder is a `TabView(.page)` with swipe enabled. Users can swipe directly from Program/Exercises to the Training Maxes or Summary page, bypassing `loadSelectedProgramAndContinue()` and `initializeTrainingMaxes()` entirely — `trainingMaxes` is then empty and every row shows the `?? 100`/zero placeholder. Fix: add `.gesture(DragGesture())` blocker or switch to a ZStack/switch-based step container (TemplateBuilderView.swift:74-105 has the same hole).
  (c) Severity: medium | CycleBuilderView.swift:1168-1187 — the "Reset to Default Values" side of the toggle button is a no-op: it flips `carryOverTMs` but only repopulates values when toggling ON. Fix: when toggling off, repopulate from `appState.programData?.initialMaxes`.

6. Program selector confusing in onboarding
- Severity: medium (UX) | ProgramSelector.swift:200-330
- Contributing factors: two stacked filter rows push content down; families are collapsed by default so most programs are invisible until an extra tap; the quiz card, disclaimer, and template-builder card compete with the list; and the onboarding never mentions custom templates can be built later from Settings. Also `QuizPromptCard` comment says "only show if no programs are selected" but it always shows (ProgramSelector.swift:252-255).
- Fix: single combined filter row, expand the first/free family by default during onboarding, move the disclaimer to a footnote, add "You can also build your own program later in Settings" to WelcomeStepView.

## Other bugs

7. Swapping a structured/linear main lift destroys its set scheme
- Severity: high | CycleBuilderView.swift:857-869 (`swapLift`)
- The replacement `DayItem` is rebuilt with only `type/lift/name/defaultSets/defaultReps`; `setsDetail`, `sets`, `reps`, and `progressionSetIndex` are dropped. Swapping e.g. an nSuns 9-set pyramid lift produces a structured item with no sets — the workout for that day is broken or empty after the cycle starts.
- Fix: copy the full item and change only `lift`/`name` (add a `with(lift:name:)` helper on DayItem).

8. Stale training maxes retained after exercise changes
- Severity: medium | CycleBuilderView.swift:316-340
- `initializeTrainingMaxes()` only adds/overwrites keys for currently configured lifts; if the user goes back and swaps a lift, the removed lift's TM stays in `trainingMaxes`. The Summary "Lifts" count (line 1789) and "Starting Training Maxes" list (1794-1811) then include the removed lift, and it gets persisted via `setInitialMaxes`.
- Fix: rebuild the dict from `actualConfiguredLifts` (drop keys not in the set).

9. Metric plate calculator computes wrong plates
- Severity: high | CalculatorsView.swift:813-930 (StandalonePlateCalculatorView) with PlateCalculator.swift:63-104
- PlateCalculator/BarbellView treat all weights as lb internally (metric plates are defined as 44 lb = 20 kg etc.), but StandalonePlateCalculatorView passes the raw kg text-field value and raw kg bar buttons ([20, 15, 10] at line 836) straight through. A metric user entering 100 (kg) gets the plate breakdown for 100 lb, displayed as "45.4 kg"; the 20 "kg" bar button actually sets a 20 lb bar. Additionally the initial `barWeight` comes from settings in lb (44.0), which matches none of the metric quick buttons.
- Fix: convert input to lb (`/0.453592`) before calling PlateCalculator when `useMetric`, and use [44.0, 33.0, 22.0] with kg labels for the bar buttons.

10. Bar-weight picker values disagree between Settings and Cycle Builder
- Severity: medium | SettingsView.swift:165-173 vs CycleBuilderView.swift:1543-1548
- Settings tags metric bars as 33.0/44.0 (lb-equivalents); the cycle-builder step tags 35.0/45.0/55.0 with labels "35 lb / 15 kg" etc. A metric user with barWeight 44.0 opens the cycle builder and the picker has no matching tag, and selecting there writes a value Settings can't represent. Fix: one shared option list keyed on the same stored lb values.

11. "Program Info" opens a blank sheet for custom-template users
- Severity: medium | HomeView.swift:177-186 and SettingsView.swift:950-959
- Both sheets use `if let programInfo = currentProgramInfo { ... }` inside `.sheet(isPresented:)`. When the active program is a custom template (or lookup misses), `currentProgramInfo` is nil and an empty sheet slides up. Fix: use `.sheet(item:)`, or route custom templates to `CustomTemplateDetailView`, and hide the menu entry when there's nothing to show. (Same conditional-content-in-sheet anti-pattern as the "blank share" bug.)

12. Editing/deleting duplicate accessories hits the wrong row
- Severity: medium | CycleBuilderView.swift:742-757
- `actualIndex` is resolved by `items.firstIndex { $0.type == .accessory && $0.name == item.name }`. If a day contains two accessories with the same name, editing or deleting the second always mutates the first. Fix: enumerate over `items.indices` directly and pass the true index.

13. Past-cycle detail is SBS-only and hardcodes 20 weeks
- Severity: medium | PastCyclesView.swift:284-292, 313-360
- `totalLoggedWorkouts` and "Weekly Rep-Outs" read only `cycle.logs` (SBS-style); cycles run on structured/linear programs show "0 workouts" and empty grids even when fully logged. The grid also iterates `ForEach(1...20)` regardless of program length — a 12-week cycle shows 8 permanently-dashed cells. Fix: fall back to `structuredLogs`/`linearLogs`/`workoutRecords` and bound the grid by the cycle's actual week count.
- Related: CycleRowView (PastCyclesView.swift:114-174) shows "Cycle N" but not the program name even though `cycle.programName` exists.

14. Hardcoded "20 weeks" / "Week X of 20" across variable-length programs
- Severity: medium
- HistoryView.swift:2316 `Text("Week \(currentWeek) of 20")` — wrong for all 12-week programs (should use `appState.weeks.count`; `buildProgressSummary()` two screens later already computes totalWeeks correctly).
- CycleBuilderView.swift:444 "Ready to start a new 20-week cycle?" and SettingsView.swift:708 "Start a new 20-week cycle." — same fix.

15. Settings "Version" is stale
- Severity: medium | SettingsView.swift:744
- Hardcoded "1.0.0" while the project was just bumped to 1.4. Fix: read `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`.

16. Strength Scores calculator can't import PRs stored under canonical lift names
- Severity: medium | CalculatorsView.swift:1579-1589
- PR lookup uses only `personalRecords["Squat"/"Bench"/"Deadlift"]`. Programs store the lifts as "Bench Press" and some as "Trap Bar Deadlift"; HistoryView's own lookup falls back to those (HistoryView.swift:280-282, 574-575) but the calculator does not. Fix: reuse the alias fallbacks.

17. `extension Int: @retroactive Identifiable` is a global footgun
- Severity: medium | TemplateBuilderView.swift:617-619
- Conforming Int to Identifiable app-wide silently changes behavior of every `ForEach`/`sheet(item:)` over Ints and can collide with future stdlib conformance. Fix: wrap the editing index in a tiny `struct EditingIndex: Identifiable`.

18. Reducing "Days per Week" silently deletes configured days
- Severity: medium | TemplateBuilderView.swift:365-379
- `ensureDayStructure()` removes day entries above the new count with no confirmation and no undo. Fix: confirm destructive shrink, or retain the data and only hide days beyond `daysPerWeek`.

19. Default TM for new template lifts is unit-blind
- Severity: low | TemplateBuilderView.swift:1908-1911
- `template.initialMaxes[lift] = 135.0` regardless of metric setting (a metric user sees 61.2 kg). Fix: pick 135 lb / 60 kg based on `useMetric`, or leave nil and require entry in the cycle builder.

20. SetDesignerRow state desyncs after deleting a set
- Severity: low | TemplateBuilderView.swift:981-1001, 1263-1283 with 1424-1451
- Rows are `ForEach(..., id: \.offset)` and each row copies `setDetail` into local @State in `init`. After deleting a middle set, remaining rows keep the previous offset's local state. Fix: give SetDetail a stable `id` and key the ForEach on it.

21. Cycle-builder progress bar omits the Settings step
- Severity: low | CycleBuilderView.swift:364-399
- `steps` = [program, exercises, trainingMaxes, summary] but the flow includes `.settings`; while on Settings the indicator appears stalled on "Training Maxes". Fix: include the step or collapse the enum.

22. Dead QuickStatsCard contains fabricated data
- Severity: low | HomeView.swift:373-428
- `tmGains` returns hardcoded "+1.2%" and `totalSets` is `completedDays * 8`. Currently unreferenced, but one accidental use ships fake stats. Fix: delete or implement.

23. Free-user history rows get the wrong date
- Severity: low | HistoryView.swift:678-692
- `currentCycleLogsOnly` discards `log.date` and stamps every entry with `currentCycleStartDate`. Harmless today (LogHistoryRow doesn't render the date) but a latent trap. Fix: pass `log.date` through.

## Consistency

24. Duplicated, already-diverged program metadata
- Severity: medium | ProgramSelector.swift:30-171 vs ProgramsView.swift:38-170
- Two hand-maintained copies of `programMetadata` and the family sort order. ProgramsView's copy is already missing `back_friendly_hypertrophy_12week`; FreeBadge logic differs: selector adds `&& !isPremiumUser` (ProgramSelector.swift:471), ProgramsView doesn't (ProgramsView.swift:789). Fix: one shared `ProgramCatalog` source of truth.

25. Duplicated program color/level maps, both stale
- Severity: low | HomeView.swift:200-228 and SettingsView.swift:1038-1066
- Identical switch statements that omit gzclp_3day, 531_fsl, phul, basic_ppl, back_friendly, both nsuns 6-day variants. Fix: derive from the shared metadata (finding 24).

26. Lift-abbreviation maps diverge
- Severity: low | HistoryView.swift:2124-2139 vs PastCyclesView.swift:176-187
- HistoryView knows "bench press"/"trap bar deadlift"; PastCyclesView only "bench"/"deadlift", so past-cycle rows show "BEN"/"TRA" while the TM card shows "BP"/"DL" for the same lifts. Fix: one shared `liftAbbreviation` helper.

27. Rating thresholds and score formulas duplicated
- Severity: low | HistoryView.swift:2590-2682 vs CalculatorsView.swift:1638-1722, 2156-2186
- WILKS/DOTS/IPF coefficient blocks and rating buckets are copy-pasted in two places. Fix: move to SBSCore (e.g., `StrengthScore.swift`).

28. Section-header and card styles bypass the design system
- Severity: low
- Two different "SectionHeader" conventions; many cards hand-roll `RoundedRectangle.fill(SBSColors.surfaceFallback)` instead of `.sbsCard()` (FeatureRow, ExerciseItemRow, SettingsCard, SummaryCard, ProgramCard, VolumeByBodyPartCard...) — these lack the standard shadow so identical-looking cards sit "flat" next to shadowed ones on the same screens. Dozens of raw `.system(size:)` fonts bypass SBSFonts. Fix: add `sbsCardFlat()`/`SBSFonts.micro()` tokens and sweep.

29. Terminology drift
- Severity: low
- "Edit Starting TMs" (SettingsView.swift:543) vs "Set Training Maxes" (CycleBuilderView.swift:1123) vs "TM Progress" (HistoryView.swift:2211); ChartDisplayMode shows "Est. 1RM" while toggles say "E1RM" and cards say "Estimated 1RM"; "Bench" vs "Bench Press", "OHP" vs "Overhead Press" in user-facing strings. Pick one style per term.

## Premium-feel gaps

30. No haptics anywhere on these surfaces — program selection, step transitions, "Start Training", TM steppers, cycle completion card. The completion moment especially deserves `.sensoryFeedback(.success, ...)`.

31. Destructive actions audit — mostly good, two gaps: (a) removing an accessory in ExerciseReviewStepView (CycleBuilderView.swift:754-756) and ExerciseEditorView (SettingsView.swift:1391-1394) deletes instantly with no confirm/undo; (b) template-builder day shrink (finding 18).

32. TM input rows accept 0/garbage silently — CycleBuilderView.swift:1258-1360, SettingsView.swift:1107-1175. `parseInput` silently ignores non-numeric text, a 0 TM is accepted and flows to the summary/start. Fix: clamp to > 0 on commit, red border via the existing `isFocused` stroke pattern, disable Continue when any TM is 0.

33. Rest-timer/settings pickers duplicated between builder and Settings but not shared — CycleBuilderView.swift:1406-1643 vs SettingsView.swift:352-404. Extract shared row components so options can't drift.

34. WeekProgressBar reads as completion but tracks selection — HomeView.swift:322-368. "Program Progress 25%" is `selectedWeek/totalWeeks` — tapping a future week instantly claims progress. Fix: base on completed weeks or relabel.

35. VolumeBarChart uses UIScreen.main.bounds — CycleBuilderView.swift:3437-3440. Wrong width in iPad split view/Stage Manager. Fix: GeometryReader.

36. AddCustomExerciseSheet leaves stale state — AccessoryExercisePickerSheet.swift:185-199, 558-575. After adding, `customExerciseName` is never cleared; reopening pre-fills the previous name. Fix: clear name in `onAdd` and set `showingAddCustom = false`.

## Dynamic Type & accessibility

37. Entire type system is fixed-size — Theme.swift:38-92 (see design-system report).

38. Icon-only buttons lack accessibility labels — CycleBuilderView.swift:183-191, TemplateBuilderView.swift:113-119 (xmark close), ProgramSelector.swift:532-539, ProgramsView.swift:838-845 (info.circle), CycleBuilderView.swift:1072-1078, SettingsView.swift:1550-1565 (trash/pencil), TMInputRow plus/minus (CycleBuilderView.swift:1294-1318), HomeView.swift:118-121 (ellipsis menu).
- Also: LiftSelector pills use `.onTapGesture` on a Text (HistoryView.swift:1370-1380) — not a button to VoiceOver, no selected state exposed. StepProgressView conveys progress by color only.

---

# Full report 5 — Design-system consistency audit

## Sweep 1 — Hardcoded styling bypassing the theme
Severity: HIGH (fonts), MEDIUM (colors/padding), LOW (cornerRadius)

- `.font(.system(size:))` direct in views: 411 call sites vs 820 SBSFonts.* uses — a third of all typography bypasses the theme. Worst: WorkoutView.swift (62), WorkoutShareCard.swift (41), CycleBuilderView.swift (38), HistoryView.swift (28), AccessoryWorkoutView.swift (23). Sizes used include 8, 9, 10, 11, 12, 14, 16, 28, 36, 48, 56 — none in SBSFonts, so an ad-hoc parallel type scale has grown beside the official one.
- Raw `.padding(<number>)`: 234 call sites vs 926 SBSLayout.* uses. Worst: CycleBuilderView (32), HistoryView (31), CalculatorsView (28), SettingsView (18), WorkoutView (17).
- Hardcoded `cornerRadius:`: 33 sites; real offenders SettingsView.swift:822/:849 (10pt, off-scale), CycleBuilderView.swift:3484 and PastCyclesView.swift:135 (6pt).
- `Color(red:...)`: PlateCalculator.swift:32-48 (defensible plate colors), RestTimerWidget/RestTimerLiveActivity.swift:170-171 (hand-rolled dark gradient).
- Named colors (~80 sites): SettingsView.swift:446/450, ProgramSelector.swift:603/623 (status dots), HistoryView.swift:321/326 (streak pill), WorkoutView.swift:3203/3206, SBSWatch/ContentView.swift throughout (`.orange` approximating the accent).

Remediation: add missing small sizes to SBSFonts (caption2 ~11, label ~10) + `display()`; migrate worst 3 files first (141 sites = 34%). Add SBSColors.gold/celebration (improvised in 5+ files). Replace status colors with SBSColors.success/warning/error. Add cornerRadiusXSmall = 4.

## Sweep 2 — Asset catalog colors: dead code confirmed
Severity: MEDIUM (latent trap)

- Assets.xcassets contains NO colorsets at all. Theme.swift:7-18 defines `Color("Background")` etc. against colorsets that don't exist — would resolve to clear if used.
- Zero usage of non-Fallback base palette outside Theme.swift; all 1,479 SBSColors call sites use `*Fallback` or semantic success/warning/error.
- Naming is inverted: the "fallback" is the real design system; the primary names are landmines.

Remediation: create the eight colorsets with current Fallback values and migrate `*Fallback` → base names (gets free light/dark/high-contrast + shared catalog for widget/Watch), or delete lines 7-18 and rename. Don't leave both.

## Sweep 3 — Dynamic Type: completely unsupported
Severity: HIGH

- Every SBSFonts function is fixed `.system(size:)` (Theme.swift:40-91). Zero `relativeTo:`, zero text styles, zero `dynamicTypeSize` anywhere.
- 11 `lineLimit(1)` sites on user-variable text (DayCard.swift:26, WorkoutShareCard.swift:134, WorkoutView.swift:1778/2677/2766/3316, CycleBuilderView.swift:998, SBSWatch/ContentView.swift:148) with only ONE `minimumScaleFactor` in the codebase (RestTimerLiveActivity.swift:204).

Remediation: rewrite SBSFonts with text styles — e.g. `title3() -> .system(.title3, design: .rounded).weight(.semibold)`; monospaced weights via `.system(.title2, design: .monospaced, weight: .bold)`. 820 call sites already go through SBSFonts, so this one-file change fixes most of the app. Then cap layout-critical surfaces with `.dynamicTypeSize(...accessibility2)` and pair `lineLimit(1)` with `minimumScaleFactor(0.75)`.

## Sweep 4 — Haptics: right pattern, asymmetric coverage
Severity: MEDIUM

Present: set completion (WorkoutView.swift:1423, AccessoryWorkoutView.swift:567/1055), PR celebration cascade (PRCelebration.swift:187-210), NumberPad (126/142/179), quiz (ProgramRecommendationQuiz.swift:257), Watch (WatchSessionManager.swift:154-236 — most complete surface).

Gaps: rest-timer pause/play, Skip (WorkoutView.swift:2537), +15s (2551) — no haptic on any; foreground timer expiry (WorkoutView.swift:1399) buzzes the Watch but not the phone; workout finish (no-PR path) silent; RestTimerPill tap silent.

Remediation: tiny `Haptics` enum in SBSCore; adopt at timer skip (light), ±15s (light), pause/resume (light), foreground expiry (success), workout finish (success).

## Sweep 5 — Animations: one de facto standard plus a long tail
Severity: LOW-MEDIUM

- Standard exists: `.easeInOut(duration: 0.2)` (26 of 63 withAnimation sites) + 0.15 for presses.
- Long tail: 15+ one-off recipes, five distinct spring personalities (0.4/0.8 ×6, 0.6/0.7 ×3, 0.5/0.6 ×2, 0.4/0.7 ×2, 0.5/0.7, 0.3/0.8), assorted easeOut/linear/1s one-offs.

Remediation: add `SBSAnimation.quick/.standard/.springy/.entrance` tokens to Theme.swift; migrate the 82 sites; keep PRCelebration's intentional choreography.

## Sweep 6 — Terminology & copy
Severity: MEDIUM

- "Training Max" (27 sites) vs "TM" (54), both in the same component (ExerciseCard.swift:38 vs :23/:104/:354). CalculatorsView.swift:1323 has the correct spell-out-then-abbreviate pattern.
- 1RM family: "Estimated 1RM" (PRCelebration.swift:115, CalculatorsView.swift:390/609), "E1RM" (WorkoutShareCard.swift:293/927, CalculatorsView.swift:616/721), "one-rep max" (CalculatorsView.swift:497/1153, FeatureAccess.swift:65), "Actual 1RM" (CalculatorsView.swift:1132).
- OHP: canonical "Overhead Press" (ExerciseLibrary.swift:173) but ad-hoc abbreviations duplicated in PastCyclesView.swift:181 and HistoryView.swift:2129; WorkoutShareCard.swift:1174 hardcodes "OHP"; HistoryView.swift:92 accepts three aliases.
- lb vs lbs: Theme.swift:208 emits "lb"; 5 "lbs" literals contradict (SettingsView.swift:186/209, AccessoryWorkoutView.swift:1126, SessionView.swift:808/1175).
- Button capitalization: consistently Title Case — keep as documented convention.

Remediation: one-page copy glossary; "lb"/"kg" only via formattedWeight; centralize lift abbreviation in ExerciseLibrary (`shortName`).

## Sweep 7 — Dark/light mode
Severity: MEDIUM (app supports both modes — ContentView.swift:18-24)

- 85 hardcoded `.white`/`Color.black` sites; ~60% benign (white-on-accent, scrims, previews, always-dark widget/Watch).
- Suspect: CycleBuilderView.swift:199 `Color.black.opacity(0.3)` scrim (muddy in light mode); PlateCalculator.swift:333 white stroke invisible on white plates in light mode; WorkoutShareCard fixed gradient renders identically in both modes (arguably intentional for export).
- Theme.swift:120/127: sbsCard black shadows are nearly invisible in dark mode — cards lose all elevation. Premium apps swap shadow for a subtle border/highlight in dark.

Remediation: audit ~25 non-benign sites; add `SBSColors.scrim`/`SBSColors.onAccent`; give sbsCard a dark-mode elevation treatment (1px border or higher-elevation surface).

## Sweep 8 — Accessibility
Severity: HIGH (worst single metric)

- Exactly ONE `accessibilityLabel` in the codebase (RestTimerPill.swift:35) vs 362 `Image(systemName:)` sites, ~79 inside buttons.
- Confirmed unlabeled: SessionView.swift:670 (delete set), :693 (add set), :924/:942/:1652; WorkoutView.swift ~2526 (pause/play), ~2540 (Skip — VoiceOver reads nothing meaningful for the most important in-workout control).
- No accessibilityHint/Value/element(children:) anywhere else.

Remediation: sweep the ~79 glyph-buttons (mechanical); priority: WorkoutView timer controls and set rows, SessionView set editing, NumberPad, nav chrome. Add `.accessibilityValue` to the countdown.

## Top 5 — highest impact for premium feel
1. Dynamic Type via SBSFonts rewrite (one file, 820 sites).
2. Accessibility labels on icon-only controls (esp. timer skip/pause/+15s — unlabeled AND unhaptic).
3. Haptic symmetry in the workout loop (20-line helper).
4. Asset-catalog/Fallback inversion + dark-mode card elevation.
5. Copy discipline: TM/e1RM/lb glossary + centralized lift abbreviations.

---

# Full report 6 — Monetization, onboarding, sharing, delight

## Bug 1 root cause — "Share opens a blank screen first time"
**Severity: HIGH**

`.sheet(isPresented:)` whose content depends on an optional `@State` set in the same transaction:

1. HistoryView.swift:616-620 — `if let image = shareImage { ShareSheet(items: [image]) }`; trigger at :669-674 sets `shareImage` and `showingShareSheet = true` together. First tap → nil → empty sheet. Matches the report exactly.
2. SettingsView.swift:714-716 + 905-912 — same pattern for data export. Compounding: `ShareSheet` (SettingsView.swift:1573-1580) has an empty `updateUIViewController`, so UIActivityViewController can never recover from stale items.
3. WorkoutView.swift:712-718 and HistoryView.swift:2220-2226 aren't blank, but render via `snapshot()` behind a fixed 0.1s sleep (WorkoutShareCard.swift:518-525) — a race, not a fix.

**Fix:** `sheet(item:)` with an Identifiable wrapper everywhere.

## Bug 2 root cause — "Strength Scores still gated after upgrade"
**Severity: HIGH**

- CalculatorsView.swift:9-11, 70-75 — `canAccessStrengthScores` read inside the lazy NavigationLink destination, not body; CalculatorsView never re-renders on purchase.
- Frozen into `let` Bool: `StrengthScoresView(canImportPRs:)` (CalculatorsView.swift:74, :1552); the view never consults StoreManager (locked UI at :1804-1848). Purchase in the sheet → still locked for the session.
- UpgradePrompt.swift:294 works only by accident of placement.

**Fix:** delete the parameter; read `StoreManager.shared.canAccess(.e1rmChart)` in body; replace onAppear-cached `inputMode` (:1776-1783) with `onChange(of: storeManager.isPremium)`.

## Paywall & StoreKit
1. HIGH — Hardcoded fallback prices ($14.99/$0.99/$2.99), StoreManager.swift:97-109 — shown whenever products haven't loaded. App Store review risk. Fix: redacted state while loading, disable purchase until Product is non-nil, never render literal prices.
2. HIGH — Restore gives zero feedback (PaywallView.swift:376-384, StoreManager.swift:197-206). Fix: surface errors; "No purchases found" when restore succeeds without entitlement.
3. MEDIUM — Ask-to-Buy pending is silent (StoreManager.swift:186-188). Show "Purchase pending approval."
4. MEDIUM — No offer/redeem code entry (no offerCodeRedemption; SBS.storekit codeOffers empty). Cheap growth lever.
5. MEDIUM — No load-failure retry on the paywall (products load once in init). Fix: `task { if products.isEmpty { await loadProducts() } }` + error/retry row.
6. MEDIUM — Subscription group levels inverted in SBS.storekit (weekly level 1, monthly level 2 — StoreKit treats monthly→weekly as an upgrade).
7. LOW — familyShareable: false on all products; cheap premium win for lifetime.
8. LOW — Raw `error.localizedDescription` in alert (PaywallView.swift:371).
9. LOW — Terms/Privacy links rendered twice (PaywallView.swift:306-309, 331-340); Restore not disabled while purchasing.
10. LOW — Free tier gives away nSuns 5-day + 5/3/1 BBB (FeatureAccess.swift:106-112) while todo.md says 2 free programs and the paywall sells "All Training Programs".

## Upgrade prompts / gates
11. MEDIUM — CycleBuilderView.swift:1641 — one shared paywall sheet always passes `.plateCalculator`, so locked Supersets/Apple Fitness rows open a "Plate Calculator" paywall. Fix: `sheet(item:)` with the tapped feature.
12. LOW — CalculatorsView.swift:7, 95-97 — dead `showingPaywall` state.
13. Note: todo item "superset and plate calculator in onboarding shown as pro features" is already implemented (CycleBuilderView.swift:1434-1470, 1516-1573) — modulo finding 11.

## Share card / PR celebration rendering
14. MEDIUM — Share images render light-mode regardless of theme (WorkoutShareCard.swift:417-437 off-window snapshot; :1459-1464 ImageRenderer without colorScheme). `drawHierarchy` off-window can also produce blanks. Fix: ImageRenderer everywhere, scale = 3, inject `.environment(\.colorScheme, ...)`.
15. MEDIUM — PR celebration fullScreenCover has opaque background (`Color.clear` doesn't work) — flat gray screen in light mode. Fix: `.presentationBackground(.clear)`.
16. LOW — No "Share this PR" CTA on the celebration (WorkoutShareCard supports PR styling).
17. LOW — HistoryView.swift:640-645 — silent no-op share button when < 1 data point.

## Review request timing
18. MEDIUM — WorkoutView.swift:1157/1160-1167 — rating request fires during dismiss/celebration; AccessoryWorkoutView.swift:407 mid-session. Defer to next HomeView appear or ~2s after summary dismissed with no sheet up.
19. LOW — `recordPRAchieved` (ReviewRequestManager.swift:53-65) has no call sites — dead trigger.

## Onboarding
20. MEDIUM — ContentView.swift:36-47 + AppState.swift:2160-2168 — `hasCompletedOnboarding` persisted only at the end; `onCancel: nil`; kill mid-flow = start over; no skip path. Fix: "Skip for now" with sensible defaults + persist builder progress.
21. LOW — ProgramRecommendationQuiz.swift:102-115 — TabView(.page) lets users swipe past questions unanswered; `isComplete` (:230-232) never checks `days`; unanswered scores as "novice" (:1016-1022).
22. LOW — Nothing in onboarding mentions custom templates (todo item).
