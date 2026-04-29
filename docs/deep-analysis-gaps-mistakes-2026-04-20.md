# Deep Analysis: Gaps & Mistakes

Date: 2026-04-20

Scope: Swift 6 concurrency, memory, SwiftData/storage, in-progress program-sharing feature, and uncommitted hotspot diffs. Skipped issues already tracked in `docs/master-ranked-issues-by-feature-2026-04-14.md` and `docs/storage-safety-plan-2026-04-16.md`.

Method: parallel audit agents (concurrency, memory, SwiftData) plus direct diff inspection of heavily-modified files. 35 findings total.

## Critical (ship-blockers)

### C1. Dead notification `.openLiveWorkoutTab` — planned-workout Start goes nowhere

Posted at:

- `Features/Planner/CalendarMonthView.swift:1083`
- `Features/Planner/Components/PlannedWorkoutComponents.swift:284`
- `Features/Achievements/Views/AchievementsDexView.swift:435,450`

Subscribed: NOWHERE. Shell listens to `openLiveOverlay` / `dismissLiveOverlay` only (`App/AppShellView.swift:682-686`).

Effect: user taps "Start" on today's planned workout, `store.startPlannedWorkout(...)` fires but live tab never opens. Regression from the "Planned workout Start does not start" fix already shipped.

### C2. `CacheManager` has its own `ModelContainer`

`Core/Services/CacheManager.swift:12-32` creates a private container for `CachedPost`/`CachedProfile`/`CachedNotification`. Main container in `App/WRKTApp.swift:244-251` doesn't register them. Two SQLite DBs on disk, zero migration coverage on the cache one.

Effect: next additive field to any of those three models = store-open crash on existing installs — same landmine as `RouteFetchTask.allowAutoPost`.

Fix: register the three cache models in main `Schema` array, remove private container from `CacheManager`, inject app-level `ModelContext`.

### C3. `BarbellConfig` has non-optional Bools without property defaults

`Features/Rewards/Models/BarbellModels.swift:50-51`:

- `var needsSupabaseSync: Bool`
- `var backfillCompletedV1: Bool`

Defaults only in `init()`, which SwiftData doesn't call on hydration. Rows written before these fields existed → container init failure.

Fix: make optional (`Bool?`) OR add `= false` at the property declaration level.

### C4. Program-sharing accept flow is not atomic

`Features/Planner/ViewModels/ProgramInviteViewModel.swift:66-81` + `ProgramLibraryViewModel.swift:110-126`: server invite flips to accepted, then fetch → deserialize → local insert. If last step fails or app suspends between, invite is consumed but no local split appears. No rollback possible on server side.

Fix: add retry-on-launch for "accepted but not imported" state, or local "pending acceptance" marker.

## High

### H1. `SocialView` drops program-invite deep links

`Features/Social/Views/SocialView.swift:167` has `case .programInvite: break`. Push-opened invite notification never routes to library. Shell routes tab correctly (`AppShellView:529-534`) but destination view ignores the payload.

### H2. `FeedViewModel` leaks NotificationCenter observer

`Features/Social/ViewModels/FeedViewModel.swift:54` uses block-based `addObserver` without storing token. No `removeObserver` in `deinit:75`. Every re-entry to Feed adds a permanent listener.

Fix: store the returned opaque token in a property, remove in `deinit`.

### H3. `RealtimeService` leaks `statusChange` monitor Task

`Features/Social/Services/RealtimeService.swift:281` spawns unstructured `Task { for await ... statusChange }`, never stored/cancelled. Re-subscribe on foreground (per project invariant) orphans prior task. Count grows per background/foreground cycle.

Fix: store in `statusMonitorTask: Task<Void, Never>?`, cancel before replacing and in `unsubscribe*`.

### H4. `RealtimeService` observation-token inconsistency

`subscribeToFriendships:372` and `subscribeToNewPosts:54` discard the `onPostgresChange` return value. `subscribeToNotifications` and `subscribeToProgramInvites` correctly store it in `observationTokens[channelId]`.

Effect: either dropped events, or leaked internal SDK state depending on SDK lifetime semantics.

### H5. `RestTimerManager`, `RestTimerPreferences`, `WatchConnectivityManager` (iOS) missing `@MainActor`

Files:

- `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift:25`
- `Features/WorkoutSession/Views/RestTimer/RestTimerPreferences.swift:11`
- `Core/Services/WatchConnectivityManager.swift:17`

ObservableObjects with `@Published` state, UI-bound, no isolation. Swift 6 strict mode = data race. Internal `Task { @MainActor in }` blocks mutate `@Published` state from an unspecified isolation context.

### H6. HealthKit route observer Task missing `@MainActor` hop

`Features/Health/Services/HealthKitManager.swift:302`:

```swift
Task { [weak self] in await self?.processRouteFetchQueue() }
```

Adjacent workout observer at `:233` and exercise-time observer at `:253` both use `Task { @MainActor [weak self] in }`. Route observer is inconsistent; Swift 6 will flag.

### H7. `WorkoutStoreV2` strong-self capture in toast callbacks

`Features/WorkoutSession/Services/WorkoutStoreV2.swift:316`:

```swift
AppNotificationManager.shared.showWorkoutDiscarded {
    self.undoDiscardWorkout()
}
```

Same pattern at `:1013` (`showWorkoutDeleted`). Callback stored in `AppNotificationManager`, outlives call site → retain cycle.

Fix: `[weak self]` capture list.

### H8. RewardsEngine auto-freeze "backfill" silently rescues stale streaks

`Features/Rewards/Models/StreakResult.swift:~890` new branch: if `oldFreezeUsedAt != nil` and `oldStreak == consecutiveWeeks + 1` and `!hasWeeklyFreezeAvailable`, it retroactively stamps a prior freeze onto the newly-broken week.

Problem: `oldFreezeUsedAt` could be months old. Real regressions get papered over as "freeze protected". Masks data bugs.

Fix: bound the backfill to within current month, or require the freeze-use-at date to be within N weeks of the broken week.

### H9. `validateWeeklyStreakOnAppear` double-called on active phase

`App/AppShellView.swift:371` (unconditional) then `:375` (inside `if healthKit.connected`). Every active transition with HK connected re-rebuilds the streak twice. Also called a third time in bootstrap at `:457`.

Fix: call once at the end of the async block, guarded.

### H10. Shell tab-bar hide has no failsafe

`App/AppShellView.swift:121-126` + `Features/Planner/PlannerSetupCarouselView.swift:131-135`. Hide/show paired only via `onAppear`/`onDisappear`. Any path where `onDisappear` is skipped (modal race, programmatic dismissal) = tab bar stays hidden forever. Nothing resets `isShellTabBarHidden = false` on tab change.

Fix: reset on tab change via `.onChange(of: selectedTab)`, or use a scoped `@Binding` passed into the planner flow instead of NotificationCenter.

### H11. `RewardsEngine.backfillDexStampsIfNeeded` N+1 fetch on launch

`Features/Rewards/Services/RewardEngine.swift:26-50` — one `FetchDescriptor<DexStamp>` per `ExercisePR` row. 100 exercises = 101 main-actor SQL queries at cold start.

Fix:

```swift
let allStampKeys = Set((try? context.fetch(FetchDescriptor<DexStamp>()))?.map(\.key) ?? [])
for pr in prs {
    let key = canonicalExerciseKey(from: pr.exerciseId)
    guard !allStampKeys.contains(key) else { continue }
    context.insert(DexStamp(key: key, unlockedAt: pr.updatedAt))
}
try? context.save()
```

### H12. `ProgramSharingRepository` cleanup misses read notifications

Migration trigger deletes only `read = false` rows on terminal invite transitions. Read notifications become orphans pointing at decided/revoked invites.

Fix: drop the `read = false` filter in the cleanup trigger.

### H13. `lastSharedProgramID` never cleared on split delete

No cleanup in `ProgramSharingRepository` when local split is removed. Sent-Invites UI keeps fetching for a program that no longer exists. Silent failure.

Fix: clear `lastSharedProgramID` when a split is deleted or soft-deleted, or validate before rendering the "Sent" button.

## Medium

### M1. No `VersionedSchema` anywhere

`App/WRKTApp.swift:243-251` uses raw `Schema([...])`. All recent additions happen to have Swift property defaults — first one that doesn't = crash.

Fix: introduce `AppSchemaV1` capturing current state, and `AppMigrationPlan` so future changes are tracked.

### M2. `current_workout_v2.json` still has no rotating backup

`Core/Persistence/WorkoutStorage.swift:262-275`. Already known gap from plan doc — still not closed. Same pattern missing for `ignoredHealthKitUUIDs` (`:334-341`) and `discardedWorkoutWindows` (`:367-374`) — lower stakes.

### M3. `CacheManager.clearExpiredCache` N+1 deletes

`Core/Services/CacheManager.swift:229-255` fetches all rows, deletes one-by-one.

Fix: `modelContext.delete(model: CachedPost.self, where: predicate)` with date predicate.

### M4. `NotificationBadgeManager` strong-self in toast actions

`Features/Social/Services/NotificationBadgeManager.swift:298-314`. Pass `[weak self]` into `NotificationAction` label and `onTap`.

### M5. `NotificationBadgeManager` realtime callback sends self into MainActor Task

`:114`, `:139` — `[weak self]` at outer closure but inner `Task { @MainActor in await self.refreshNotificationCount(...) }` strongly re-captures. Swift 6 "sending self" warning.

Fix: capture values (e.g. `userId`) outside the Task, re-`[weak self]` inside.

### M6. `BarbellAudioBuilder.audioResourceCache` never evicted

`Features/Rewards/Views/BarbellAudioBuilder.swift:68` — file-scope dict of Metal-backed `AudioFileResource`. Bounded today by key space (~8), but design lets it grow without eviction.

Fix: add `clearAudioCache()` called from `BarbellRealityView.onDisappear`, or bound size.

### M7. `HealthKitManager.setupBackgroundObservers` not idempotent

`Features/Health/Services/HealthKitManager.swift:220` — if called twice (re-auth path), old `HKObserverQuery` objects are orphaned on `HKHealthStore`, new ones overwrite properties → originals unstoppable.

Fix: call `stopBackgroundObservers()` at top.

### M8. `WorkoutStoreV2.init` `Task {}` without `[weak self]`

`Features/WorkoutSession/Services/WorkoutStoreV2.swift:114`. Singleton-ish so benign today. Swift 6 strict will flag sending partially-initialized self.

### M9. `WorkoutStoreV2.updateCompetitiveFeatures` strong-self via re-guard in `Task.detached`

`:1782` — `[weak self]` then `guard let self` — then accesses MainActor state from detached task. Swift 6 will reject.

Fix: pre-capture `userId`/`snapshot` as values before detaching:

```swift
let userId = authService?.currentUser?.id
let snapshot = workout
Task.detached(priority: .utility) { [battleRepository, challengeRepository] in
    guard let userId else { return }
    // use snapshot, userId directly
}
```

### M10. `PushNotificationService` missing `@MainActor`

`Core/Services/PushNotificationService.swift:9`. ObservableObject, no isolation.

### M11. `AppDependencies.configure` Task strong-self

`Core/Dependencies/AppDependencies.swift:144`. Singleton so benign. Flagged for Swift 6 hygiene.

### M12. `RewardsEngine.resetAll` inner `Task { @MainActor in }` is redundant

`Features/Rewards/Services/RewardEngine.swift:175` — already on MainActor. Unnecessary indirection and creates shared-singleton capture.

### M13. `CalendarMonthView` gesture changed from `.gesture` to `.simultaneousGesture`

`Features/Planner/CalendarMonthView.swift:174`. Month-swipe may now fire alongside interior scroll/tap gestures. Worth testing for unintended horizontal swipes during vertical scroll.

## Low / Hygiene

- `Persistence/Persistence.swift` legacy actor still coexists with `WorkoutStorage`. Dead-code trap: any caller hitting it will overwrite the legacy files that `WorkoutStorage.migrateFromLegacyStorage()` treats as migration source.
- `Features/Planner/ViewModels/ProgramLibraryViewModel.swift:131-133` `pendingInvite(id:)` helper unused.
- `Features/Planner/Services/ProgramSerializer.swift:17-28` `outgoingAttribution()` override path (`creator` param) never passed explicitly.
- Program-invite realtime subscription (`RealtimeService.swift:329`) filters recipient-only; senders' Sent-Invites list won't auto-refresh on accept/decline.
- `Features/Planner/ViewModels/ProgramInviteViewModel.swift:73-75` deserialization fallback credits current sender if `SharedProgramStructure.creator` missing — re-share loses attribution.
- `ProgramActivationViewModel.activate(split:)` is synchronous but calls blocking SwiftData writes. UI freezes during `replanUpcomingWorkouts`. Make async.
- `ProgramActivationViewModel` doesn't validate `startDate >= today` or `split.isActive == false` before activation.

## Suggested fix order

1. **C1** — dead notification, user-visible broken feature on main planner flow
2. **C3** — `BarbellConfig` optional fix, one-line change, prevents crash on existing installs
3. **C2** — consolidate `CacheManager` into main container
4. **H5** + **H6** — `@MainActor` on timer/preferences/WC, route observer hop (Swift 6 prep)
5. **C4** + **H1** + **H12** + **H13** — program-sharing correctness before shipping feature
6. **H2** + **H3** + **H4** — observer/Task leaks (grow over session time)
7. **H8** — auto-freeze backfill (hides real streak bugs going forward)
8. **H11** — launch perf (N+1 on main actor)

## Not flagged (investigated and ruled out)

- WCSession delegate methods being `nonisolated` with `Task { @MainActor in }` dispatch — intentional project invariant, correct.
- `VirtualRunManager` as `@Observable @MainActor` — correct.
- `CLLocationManager.desiredAccuracy = kCLLocationAccuracyBest` — intentional, do not lower.
- `HKSampleQuery` with `sortDescriptors: nil` for `HKWorkoutRoute` — intentional, sort silently returns empty.
- `ProgramLibraryViewModel` `[weak self]` capture in realtime callbacks — correct.
- Most recently-added `@Model` fields with inline `= value` property defaults — SwiftData-safe additive migration.
- `PlannerModels.WorkoutSplit` 8 new fields all `Optional` — additive migration safe.
- `streakFrozen` vs `weeklyStreakFrozen` split — two separate properties by design (daily vs weekly), diff is a BUG FIX not a rename.
