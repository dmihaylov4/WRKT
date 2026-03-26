# WRKT Code Quality Report
Generated: 2026-03-20

---

## Summary by Severity

### Critical / High Priority
1. Duplicate `ExercisePR` model definition (compilation/data integrity risk)
2. `ImageUploadService` instantiated 4x in views instead of DI (broken progress tracking)
3. 5 completely empty `catch {}` blocks swallowing errors in persistence paths
4. `print()` statements throughout `ImageUploadService` and `PostCard` shipping to production
5. Dead files: `HomeView.swift`, `CompeteView.swift`, `MetricExamples.swift`, `ProgressTabView.swift`
6. `USE_MOCK_VIEWS_FOR_SCREENSHOTS = false` dead flag in `SocialView.swift`
7. `getTopCompetition()` always returns nil with a TODO — competition card never shown
8. `CacheManager` calls `fatalError` on SwiftData init failure (should fall back to in-memory)

### Medium Priority
9. 30+ duplicate `formatDuration`/`formatTime`/`formatPace`/`formatVolume` functions across 15+ files
10. Raw `NSNotification.Name("String")` — 9+ names not registered as constants in `AppEvents`
11. `NotificationType.color` returns `"gold"` (unmapped color string, no SwiftUI Color named "gold")
12. `debugFrames = true` flag in `ExcerciseSessionView` without `#if DEBUG`
13. Debug logging in `HomeViewModel.getFriendActivityToday()` shipping to production
14. `fatalError()` in view button handlers — should be graceful error instead
15. `PlannerDebugView` compiled in release without `#if DEBUG`
16. Mixed DI patterns: `@EnvironmentObject` vs `@Environment(\.dependencies)` vs `.shared` coexist
17. Business logic embedded in `ProfileView`, `PostCard`, `FeedView` (should be in view models)
18. `Persistence.swift` legacy actor only used in one place

### Low Priority (housekeeping)
19. Stale TODO comments (`AppModels/Models.swift:9`, `HomeViewNew.swift:6`)
20. `//TestNotificationButton()` commented-out debug code in `SocialView.swift:65`
21. Typo in filename: `ExcerciseSessionView.swift` (should be `ExerciseSessionView.swift`)
22. `didExitCleanly` deprecated property still called in `WorkoutStoreV2` (2 places)
23. `sizeInMB` computed in `ImageUploadService.swift:227` but never used
24. `StreakBanner` struct in `CalendarBanners.swift` marked legacy and never used
25. `StatsDebugView` defined but unreachable from any navigation

---

## 1. Dead Code

### HIGH: `HomeView.swift` — entirely dead, replaced by `HomeViewNew`
- `AppShellView.swift:247` uses `HomeViewNew()`. `HomeView` is never instantiated.
- Fix: Delete `Features/Home/HomeView.swift`.

### HIGH: `CompeteView.swift` — entirely dead, replaced by `UnifiedCompeteView`
- `SocialView.swift` uses `UnifiedCompeteView()`. `CompeteView` is never instantiated.
- Fix: Delete `Features/Compete/CompeteView.swift` (verify `OverviewSection` inside it is also dead).

### HIGH: `MetricExamples.swift` — `BattleExamples` and `ChallengeExamples` have zero usages
- Fix: Delete `Features/Compete/Examples/MetricExamples.swift`.

### HIGH: `ProgressTabView.swift` — never instantiated anywhere in the app
- Fix: Delete `Features/Progress/ProgressTabView.swift`.

### HIGH: `AppModels/Models.swift` — contains only a `private enum Theme` and a TODO comment
- `DS.swift` supersedes it entirely. Cannot even be used outside its own file (`private`).
- Fix: Delete `AppModels/Models.swift`.

### HIGH: Duplicate `ExercisePR.swift` — two `@Model class ExercisePR` definitions
- `Models/ExercisePR.swift` and `Core/Models/ExercisePR.swift` both exist.
- `Core/Models/ExercisePR.swift` has concatenated file headers and duplicate imports.
- Fix: Delete `Models/ExercisePR.swift`, keep `Core/Models/ExercisePR.swift`.

### HIGH: `StatsDebugView` defined but unreachable from any navigation path
- `Features/Statistics/Views/StatsDebugView.swift` has no `#if DEBUG` guard and no entry point.
- Fix: Either wire into Settings debug section or delete.

### MEDIUM: `StreakBanner` struct marked "Legacy" and never used
- `Features/Planner/Components/CalendarBanners.swift` line 10.
- Only `WeeklyStreakBanner` is used. `StreakBanner` is dead code.
- Fix: Delete the `StreakBanner` struct.

### MEDIUM: `USE_MOCK_VIEWS_FOR_SCREENSHOTS = false` — constant never read
- `Features/Social/Views/SocialView.swift:11` — the `if/else` branch it guarded is gone.
- Fix: Delete the constant.

### MEDIUM: `//TestNotificationButton()` commented-out debug code
- `Features/Social/Views/SocialView.swift:65`
- Fix: Remove the comment.

### MEDIUM: `Persistence.swift` — legacy actor with one remaining caller
- `Persistence.shared.wipeAllDevOnly()` is only called from `PreferencesView.swift:510`.
- All other persistence has moved to `WorkoutStorage`.
- Fix: Move wipe logic into `WorkoutStorage`, delete `Persistence/Persistence.swift`.

### MEDIUM: `PlannerDebugView` has no `#if DEBUG` guard — ships to production
- `Features/Planner/PlannerDebugView.swift` has a "Clear All Plans & Workouts" button visible in production builds.
- Fix: Wrap entire file in `#if DEBUG`.

### LOW: `sizeInMB` computed but never used
- `Core/Services/ImageUploadService.swift:227` — assigned, never logged or checked.
- Fix: Delete the line.

### LOW: `didExitCleanly` deprecated property still called
- `Features/WorkoutSession/Services/WorkoutStoreV2.swift:225,261`
- Fix: Replace with `defaults.markBackgrounded(hasActiveWorkout: true)`.

---

## 2. Code Duplication

### HIGH: 30+ private copies of `formatDuration` / `formatTime` / `formatVolume` / `formatPace`
A global `formatDuration(_:)` exists in `Core/Utilities/Utilities.swift:231` but is ignored in favor of identical private copies in at least 15 files:

**`formatDuration` duplicates:**
- `WorkoutDetail.swift:368`, `WatchWorkoutModels.swift:134`, `WorkoutEntry.swift:179`
- `ExerciseStatsAggregator.swift:806`, `CardioView.swift:634`, `CardioView.swift:1148`
- `TimedSetRow.swift:309`, `ExerciseStatisticsView.swift:775`, `VirtualRunSummaryView.swift:193`, `VirtualRunView.swift:777`

**`formatTime` duplicates:**
- `SetRowViews.swift:373`, `SetRowViews.swift:525`, `BodyweightSetRow.swift:307`
- `RestTimerHeroContent.swift:191`, `TimedSetRow.swift:315`, `CardioDetailView.swift:441`
- `PreferencesView.swift:692`, `HealthKitStrengthDetailView.swift:236`, `RestTimerWatchView.swift:194`

**`formatVolume` duplicates:**
- `LastWorkoutCard.swift:212`, `RecentActivityCard.swift:251`, `PostDetailView.swift:1156`
- `PostCard.swift:772`, `ExerciseStatisticsView.swift:549,770`

**`formatPace` duplicates:**
- `PostDetailView.swift:926`, `PostCard.swift:540`, `VirtualRunSummaryView.swift:200`
- `VirtualRunMapComparisonView.swift:606`, `VirtualRunFlowStatusCard.swift:280`, `VirtualRunView.swift:773`

Fix: Consolidate all into `Utilities.swift` or a `FormattingExtensions.swift` file.

### HIGH: `ImageUploadService()` instantiated 4x in views instead of using DI
- `PostDetailView.swift:22`, `PostCard.swift:32`, `EditPostView.swift:22`, `CardioAutoPostService.swift:30`
- `AppDependencies` already holds `self.imageUploadService = ImageUploadService()`.
- Each instantiation creates separate `uploadProgress`/`isUploading` state — progress tracking unreliable.
- Fix: Use `deps.imageUploadService` in all views; delete local `let imageUploadService = ImageUploadService()`.

### HIGH: Hardcoded workout-type string arrays duplicated across files
- `WorkoutStoreV2.swift:36-60` inline `let` arrays in a computed property.
- Same workout type strings appear in `HealthKitWorkoutCategory.swift` and `CardioDataExtractor.swift`.
- Fix: Define a single `WorkoutTypeConstants` enum.

### MEDIUM: `loadImageURLs()` duplicated in `PostCard` and `PostDetailView`
- `PostCard.swift:130-156` and `PostDetailView.swift:1165-1181` are near-identical.
- Fix: Extract to a shared `PostImageLoader` helper.

### MEDIUM: `NSNotification.Name("WorkoutUpdatedFromWatch")` hardcoded 3x
- `WatchConnectivityManager.swift:464,600,695`
- Fix: Add to `AppEvents.swift` as a static constant.

### MEDIUM: 9+ notification name string literals not in `AppEvents`
Raw strings in production code that bypass `AppEvents.swift`:
- `"WorkoutUpdatedFromWatch"` (3x), `"OpenAppFromWatch"`, `"VirtualRunEndedFromWatch"`
- `"VirtualRunWatchConfirmed"`, `"VirtualRunPausedFromWatch"`, `"VirtualRunResumedFromWatch"`
- `"WatchVRLogReceived"`, `"GeneratePendingSetBeforeTimer"`, `"NavigateToNotification"`

Fix: Add all to `AppEvents.swift`.

---

## 3. Architecture Issues

### HIGH: Massive God files
| File | Lines | Issue |
|---|---|---|
| `HealthKitManager.swift` | 2,003 | Auth, observer queries, sync, route fetching, deletion, HR zones, background tasks |
| `WorkoutStoreV2.swift` | 1,752 | CRUD, PR calc, HealthKit sync, competitive hooks, PR auto-post |
| `WatchConnectivityManager.swift` | 1,550 | All WCSession messages, VR flow, route upload, telemetry |
| `ExcerciseSessionView.swift` | 1,421 | UI + tutorial + WatchKit + timer + PR detection |
| `PostDetailView.swift` | 1,307 | Post UI + strength carousel + cardio + HR chart + splits + comments |
| `ProfileView.swift` | 1,258 | Weekly progress + achievement dex + stat syncing + milestone rendering + onboarding |

### HIGH: Mixed dependency injection — three incompatible patterns coexist
1. `@Environment(\.dependencies)` — 22 files (intended pattern)
2. `@EnvironmentObject` — 81 occurrences across 41 files
3. Direct `.shared` singleton access — 591 occurrences across 109 files

`PostCard`, `PostDetailView`, `EditPostView` create `ImageUploadService()` directly (bypasses both patterns).
`CardioDetailView` calls `HealthKitManager.shared` directly instead of going through deps.

Fix: Migrate toward `@Environment(\.dependencies)` consistently. Add `HealthKitManager` to `AppDependencies`.

### HIGH: Business logic embedded in views
- `ProfileView.swift`: `syncHealthKitMinutes()`, `checkWeeklyGoalStreak()`, `refreshStats()`, `updateWeekProgressCache()` — ~200 lines of non-UI logic in a View struct.
- `PostCard.swift`: `runBackfill()` (~100 lines) — fetches HealthKit data, generates map snapshot, uploads to Supabase from a view.
- `FeedView.swift`: Arena loading, battle loading, challenge loading inside the view.

### HIGH: `getTopCompetition()` always returns nil — competition card feature is dead
- `Features/Home/ViewModels/HomeViewModel.swift:220` — `// TODO: Implement when battle/challenge repositories are injected`
- The function is called every home screen refresh; `CompetitionSummary` card type exists but is never shown.
- Fix: Implement it or remove the card type and stub function.

### HIGH: `ExcerciseSessionView.swift` — typo in filename
- Should be `ExerciseSessionView.swift`. File/struct name mismatch.

### MEDIUM: `HomeViewNew.swift` — stale TODO and "New" suffix
- Line 6: `// TODO: Rename to HomeViewNew.swift after testing` — self-referential, stale.
- `HomeView.swift` (the old one) is dead, so `HomeViewNew` can be renamed `HomeView`.

### MEDIUM: `CacheManager` calls `fatalError` on SwiftData init failure
- `Core/Services/CacheManager.swift:30-32`
- Main `ModelContainer` in `WRKTApp.swift` has a 3-level fallback. `CacheManager` has none.
- Fix: Add fallback to in-memory store.

### MEDIUM: `fatalError()` in view button handlers — should be graceful
- `PlannedWorkoutEditor.swift:198,438` — "Exercise not found" / "Set not found"
- `RetrospectiveWorkoutBuilder.swift:244` — "Entry not found"
- `CompletedWorkoutEditor.swift:168` — "Entry not found"
- Fix: Replace with `guard` + `AppLogger.error` + graceful return.

---

## 4. TODOs and FIXMEs

| Location | Severity | Note |
|---|---|---|
| `AppModels/Models.swift:9` | LOW | `// TODO : MOVE TO DS.swift` — file is dead anyway |
| `HomeViewNew.swift:6` | LOW | `// TODO: Rename to HomeViewNew.swift after testing` — self-referential, stale |
| `HomeViewNew.swift:76` | MEDIUM | `// TODO: Open exercise browser or show quick add` — hero tap falls through incorrectly |
| `HomeViewModel.swift:220` | HIGH | `// TODO: Implement when battle/challenge repositories are injected` — stub returns nil |
| `SocialView.swift:136` | MEDIUM | `// Challenge notifications — TODO: implement challenge detail` — tapping does nothing |
| `CustomSplitExercisePicker.swift:89` | MEDIUM | `// TODO: Show configuration sheet` — Configure button has no action |

---

## 5. Debug / Development Artifacts

### HIGH: `print()` statements in production code
- `Core/Repositories/BaseRepository.swift` — `logInfo`, `logSuccess`, `logError`, `logWarning` all use `print()` instead of `AppLogger`. Fires in release builds.
- `Core/Services/ImageUploadService.swift` — 15+ `print()` calls across upload pipeline.
- `Features/Social/Views/Components/PostCard.swift` — 12+ `print()` calls in backfill logic.
- `Features/Health/Views/CardioView.swift:351,361,367` — sync path logging.
- `Features/Health/Views/CardioDetailView.swift:96,126` — share tap + delete error.
- `Features/Social/ViewModels/FeedViewModel.swift:228` — like error.
- `Features/Social/Views/PostDetailView.swift:1179` — image URL load failure.

Fix: Replace all with `AppLogger.*` calls.

### HIGH: `private let debugFrames = true` without `#if DEBUG`
- `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift:57`
- Fix: Remove or wrap in `#if DEBUG`.

### MEDIUM: Debug logging in `HomeViewModel.getFriendActivityToday()` ships to production
- `Features/Home/ViewModels/HomeViewModel.swift:258-270` — logs "Debug: Log all posts" per home refresh.
- Fix: Remove or wrap in `#if DEBUG`.

---

## 6. Missing Error Handling

### HIGH: Silent empty `catch {}` blocks swallowing errors
| File | Context |
|---|---|
| `OfflineQueueManager.swift:163-164` | `saveQueue()` discards JSON encoding failures — offline actions silently lost |
| `CacheManager.swift:277-278` | `saveContext()` discards SwiftData save failures — cache writes silently lost |
| `PlannedWorkoutComponents.swift:296-297` | Delete planned workout swallows errors — UI shows success haptic but save may have failed |
| `PlannedWorkoutEditor.swift:275-276` | Save planned workout swallows errors — `dismiss()` called regardless |
| `FeedViewModel.swift:399-400` | Realtime subscription start swallows errors — feed silently stops receiving real-time updates |

Fix: At minimum add `AppLogger.error(...)` in each empty catch.

### HIGH: `try?` silencing critical errors in persistence paths
- `WorkoutStoreV2.swift:130` — `try? await storage.deleteCurrentWorkout()` after force-quit detection
- `WorkoutStoreV2.swift:276,288,305` — `try? await storage.*` in discard/undo paths
- `WatchConnectivityManager.swift:1173,1220,1248,1290` — `try? JSONSerialization` / `try? session.updateApplicationContext()` silently skip WCSession messages

### MEDIUM: Delete failure in `CardioDetailView` shows no user-facing error
- `CardioDetailView.swift:126` — failure logged with `print` but no alert shown to user.
- Fix: Add `@State var deleteError: Error?` and show an alert.

---

## 7. Memory / Retain Cycle Risks

### HIGH: Strong `self` capture in `WorkoutStoreV2.undoDiscardWorkout()`
```swift
// WorkoutStoreV2.swift:292-294
AppNotificationManager.shared.showWorkoutDiscarded {
    self.undoDiscardWorkout()   // strong capture — should be [weak self]
}
```

### MEDIUM: `FeedViewModel` realtime Task captures `self` strongly
- `FeedViewModel.swift:390-396` — inner `Task { ... }` inside `[weak self]` closure holds strong ref until task completes.
- Realtime subscriptions persist after view disappears.

### MEDIUM: `PostCard` and `PostDetailView` create `ImageUploadService()` as a `let` stored property
- `@MainActor final class` inside a `struct View` — new instance on every struct recreation.
- Should be `@StateObject` or use `deps.imageUploadService`.

---

## 8. Inconsistent Patterns

### HIGH: Two notification name systems coexist
- `AppEvents.swift` defines 5 typed `Notification.Name` extensions.
- 9+ other notification names are raw `NSNotification.Name("StringLiteral")` inline.

### MEDIUM: `.cornerRadius(N)` vs `.clipShape(RoundedRectangle(...))` — ~1,000 combined usages
- Both patterns appear in the same files, often the same view.
- Hardcoded magic numbers (8, 12, 14, 16) instead of `DS` radius tokens.

### MEDIUM: `NotificationType.color` returns unmapped strings
- `Features/Social/Models/Notification.swift:79-116` returns `"gold"` which is not a named SwiftUI `Color`.
- Fix: Return `Color` directly or a typed enum.

### MEDIUM: `@ObservedObject` vs `@State` for singletons
- `HomeViewNew.swift:26` — `@ObservedObject private var restTimerManager = RestTimerManager.shared`
- `SocialView.swift:35`, `ProfileView.swift:25` — `@State private var badgeManager = NotificationBadgeManager.shared`
- Mixing patterns for the same conceptual use case.
