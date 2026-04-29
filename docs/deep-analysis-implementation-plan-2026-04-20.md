# Deep Analysis: Implementation Plan

Date: 2026-04-20
Pairs with: [deep-analysis-gaps-mistakes-2026-04-20.md](/Users/dimitarmihaylov/dev/WRKT/docs/deep-analysis-gaps-mistakes-2026-04-20.md)

Goal: fix every finding without breaking existing functionality. Additive, staged, reversible where possible. Each phase ends with a build + targeted test pass before moving on.

## Ground rules

1. One phase per branch/PR. Phases are independent — merge order is C-Bs first, then H-Bs, then M-Bs, then L-Bs.
2. For every SwiftData model change: verify on a device/simulator with an EXISTING store (not a fresh install) before shipping.
3. For every removed `Task {}` strong-self capture: add lifecycle verification where feasible (unit test, deinit probe, bounded-count assertion, or memory-graph check).
4. No silent `try?` swallowing in new code. If existing code uses it, preserve behavior; flag in follow-up.
5. For every moved public API (e.g. `@MainActor` added): grep every call site before merging.
6. For lifecycle and leak fixes, prefer deinit probes, bounded-count assertions, and memory-graph verification over closure-capture unit tests unless a unit test is genuinely straightforward.

---

## Phase 1 — Ship-blockers (C1-C4)

### C1. Wire `.openLiveWorkoutTab` subscriber

Files:

- `App/AppShellView.swift` (add `.onReceive`)
- grep-check `Features/Planner/CalendarMonthView.swift:1083`, `Features/Planner/Components/PlannedWorkoutComponents.swift:284`, `Features/Achievements/Views/AchievementsDexView.swift:435,450` stay as-is.

Decision: the notification's intent is "switch tab to Train and open live overlay". The existing `openLiveOverlay` already flips `showLiveOverlay`. We need BOTH tab switch and overlay.

Steps:

1. In `AppShellView.body` (same place as `.hideShellTabBar`/`.showShellTabBar`), add:
   ```swift
   .onReceive(NotificationCenter.default.publisher(for: .openLiveWorkoutTab)) { _ in
       selectedTab = .train
       withAnimation(ShellAnim.spring) {
           showLiveOverlay = true
           showContent = true
       }
   }
   ```
2. Confirm `.openLiveOverlay` subscriber (lines 682-686) still works for existing callers that post it. Don't delete.
3. Audit whether any poster should switch to `.openLiveOverlay` + explicit tab switch instead — leave unchanged for this phase, just fix the dead notification.

Verification:

- Tap planned workout "Start" from Plan tab → tab flips to Train, live overlay visible, entries populated.
- Tap from Achievements dex → same.
- Tap from PlannedWorkoutComponents card → same.

Rollback: single-commit revert.

### C2. Consolidate `CacheManager` into main `ModelContainer`

Files:

- `App/WRKTApp.swift:243-251` (main `Schema`)
- `Core/Services/CacheManager.swift:12-32` (remove private container)
- `Core/Services/CacheManager.swift` callers (grep for `CacheManager.shared`)

Steps:

1. Add `CachedPost.self, CachedProfile.self, CachedNotification.self` to main `Schema([...])` array in `makeContainer()`.
2. Change `CacheManager` to accept `ModelContext` via init rather than constructing its own:
   ```swift
   @MainActor final class CacheManager {
       static let shared = CacheManager()   // keep shared for compatibility
       private var modelContext: ModelContext?
       private init() {}
       func configure(with context: ModelContext) { self.modelContext = context }
   }
   ```
3. Call `CacheManager.shared.configure(with: modelContext)` from `AppDependencies.configure(with:)`.
4. Replace every `modelContext` access in `CacheManager` with `guard let modelContext` — log-and-return early when unconfigured.
5. First-launch migration: SwiftData will auto-create tables for the three new models. Existing users lose their cached data (acceptable — cache is rebuildable). Verify launch doesn't crash.
6. Delete the private-container code block.
7. Explicitly treat the old cache DB as abandoned cache data:
   - do not read from it during this change
   - do not block shipping on deleting it
   - document that a later cleanup task may remove the orphaned store file if we care about disk hygiene

Verification:

- Clean install: app launches, feed loads, profile loads, notifications load.
- Upgrade install (pre-change build → post-change build): launch doesn't crash; stale cache is repopulated from network on first tab entry.
- Check only one `.store` file for the app group after upgrade.
- Confirm the old private cache store, if present, is no longer opened by the app.

Rollback: restore CacheManager private container; remove the 3 model types from main Schema.

### C3. `BarbellConfig` optional defaults

Files:

- `Features/Rewards/Models/BarbellModels.swift:50-51`

Steps:

1. Change:
   ```swift
   var needsSupabaseSync: Bool
   var backfillCompletedV1: Bool
   ```
   to:
   ```swift
   var needsSupabaseSync: Bool = false
   var backfillCompletedV1: Bool = false
   ```
2. Keep the `init()` defaults for new-instance construction.
3. Grep for every direct property access. Confirm no code path assumes hydration from SwiftData produces the `init()` defaults.

Verification:

- Upgrade install on a device that already has a `BarbellConfig` row (pre-change build) — confirm `ModelContainer` opens without a `SwiftDataError`.

Rollback: trivial revert.

### C4. Program-sharing accept atomicity

Files:

- `Features/Planner/ViewModels/ProgramInviteViewModel.swift:66-81`
- `Features/Planner/ViewModels/ProgramLibraryViewModel.swift:110-126`
- `Features/Planner/Services/ProgramSharingRepository.swift`

Steps:

Decision: split this into a minimum safe fix now and persistence-backed recovery later. Do not add a new SwiftData model in Phase 1.

#### Phase 1 minimum-safe fix

1. Refactor accept flow into an explicit state machine in code:
   - fetch invite
   - fetch shared program payload
   - deserialize locally
   - mark server invite accepted
   - insert local `WorkoutSplit`
2. If the remote API contract requires accept-before-fetch, keep server accept first but immediately persist a lightweight retry marker outside SwiftData:
   - `UserDefaults` or existing file-backed persistence
   - key by `inviteID`
   - store only the minimum data needed to retry or surface recovery UI
3. On successful local insert, clear the retry marker.
4. On next launch, if retry markers exist, attempt import again before clearing them.

#### Phase 3 hardening follow-up

1. Re-evaluate whether a dedicated `PendingProgramImport` SwiftData model is warranted after the minimal recovery path has shipped and been observed.
2. Only add a persisted model if the retry marker proves too limited for real failure cases.
3. Defer UX polish such as "Syncing..." rows and expiration policy until the recovery path is proven necessary.

Verification:

- Force-quit app between server accept and local insert → relaunch completes the import.
- Delete the shared program server-side before relaunch → import fails gracefully, retry marker remains bounded and does not loop forever.

Rollback: revert the retry-marker logic and accept-flow reorder together. No schema rollback needed because Phase 1 does not add a model.

---

## Phase 2 — Swift 6 foundation (H5, H6, M10)

### H5. Add `@MainActor` to three ObservableObjects

Files:

- `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift:25` → `@MainActor class RestTimerManager`
- `Features/WorkoutSession/Views/RestTimer/RestTimerPreferences.swift:11` → `@MainActor class RestTimerPreferences`
- `Core/Services/WatchConnectivityManager.swift:17` → `@MainActor class WatchConnectivityManager`

Steps per class:

1. Add `@MainActor` annotation.
2. Grep every call site. Any `nonisolated` WCSession delegate methods must stay `nonisolated` — they already dispatch via `Task { @MainActor in }`, confirm.
3. Any synchronous call site from a non-MainActor context — wrap in `await MainActor.run { ... }` or make the call site `@MainActor`.
4. Remove now-redundant `Task { @MainActor in }` inside the class body (they become plain code).

Verification:

- Build with `-strict-concurrency=targeted` on the target module. Fix each warning.
- Start workout, see rest timer, toggle preferences — all work identically.
- Watch workout flow: start/pause/end — WCSession delegate hops still land on MainActor.

Rollback: remove `@MainActor`, restore inner `Task { @MainActor in }` where needed.

### H6. HealthKit route observer `@MainActor` hop

Files:

- `Features/Health/Services/HealthKitManager.swift:302`

Steps:

1. Change:
   ```swift
   Task { [weak self] in
       await self?.processRouteFetchQueue()
   }
   ```
   to:
   ```swift
   Task { @MainActor [weak self] in
       await self?.processRouteFetchQueue()
   }
   ```
2. Confirm adjacent observers (`:233`, `:253`) already use the correct form.

Verification: complete a cardio workout with route, confirm route enrichment queue drains (existing behavior).

### M10. `PushNotificationService` add `@MainActor`

Files:

- `Core/Services/PushNotificationService.swift:9`

Steps:

1. Add `@MainActor` to class declaration.
2. Grep call sites; any off-main call must be wrapped.

Verification: push token registration still fires on launch.

---

## Phase 3 — Program-sharing correctness (H1, H12, H13, C4 follow-ups, L items)

### H1. Program-invite payload is routed to Plan tab but not consumed there

Files:

- `Features/Social/Views/SocialView.swift:167`
- Plan-tab container view that owns Program Library presentation
- `Features/Planner/.../ProgramLibraryView.swift` init/presentation path

Steps:

1. Replace `case .programInvite: break` with:
   ```swift
   case .programInvite:
       // SocialView is not on-screen for program invites — shell routes tab elsewhere.
       // Nothing to do here, but ensure we don't accidentally clear the pending notification.
       break
   ```
2. Confirm the shell already routes `.programInvite` to `.plan` tab (AppShellView:529-534).
3. In the Plan-tab container, add pending-notification handling:
   ```swift
   .onChange(of: pendingNotification) { _, new in
       guard let n = new, n.type == .programInvite else { return }
       // Open Program Library with the invite preselected.
       programLibraryPreselectInviteID = n.metadata["invite_id"]
       onProgramLibraryTap()
       pendingNotification = nil
   }
   ```
4. Pass `preselectInviteID` into `ProgramLibraryView` via init; library auto-opens the invite preview sheet on appear if set.
5. Treat `SocialView` as intentionally uninvolved after tab routing. The actual ownership of the deep-link payload is the Plan destination.

Verification:

- Simulate a program-invite push → tap → Plan tab opens → library opens → invite preview sheet visible.

### H12. Notification cleanup on invite terminal transitions

Files:

- `supabase/migrations/` (new migration file)
- `Features/Planner/Services/ProgramSharingRepository.swift` (optional client-side cleanup as safety net)

Steps:

1. New migration `YYYYMMDD_program_invites_cleanup_read.sql`:
   ```sql
   create or replace function public.cleanup_program_invite_notifications()
   returns trigger as $$
   begin
       if new.status in ('accepted', 'declined', 'revoked') then
           delete from public.notifications
           where type = 'programInvite'
             and (metadata->>'invite_id')::uuid = new.id;
       end if;
       return new;
   end;
   $$ language plpgsql security definer;

   -- replace existing trigger (drop+create)
   drop trigger if exists trg_program_invite_cleanup on public.program_invites;
   create trigger trg_program_invite_cleanup
   after update on public.program_invites
   for each row execute function public.cleanup_program_invite_notifications();
   ```
2. Apply locally + remotely per the Supabase workflow documented in the plan.
3. Client safety net: on accept/decline/revoke in `ProgramSharingRepository`, also call `notificationRepository.deleteByMetadata(type: .programInvite, key: "invite_id", value: inviteID.uuidString)`.

Verification:

- Accept an invite → check that both unread AND read notifications for that invite are gone from the notifications list.

### H13. Clear `lastSharedProgramID` on split delete

Files:

- `Features/WorkoutSession/Services/PlannerStore.swift` (delete path)

Steps:

1. Find the split delete method (grep `modelContext.delete(split)` or equivalent).
2. Before delete, nil out `split.lastSharedProgramID`. Since `modelContext.delete` will cascade, the field becomes moot — but also clear any sibling state (e.g. pending sent-invites UI cache).
3. If the sent-invites sheet is showing, `.onChange` of split existence to dismiss.

Verification:

- Share a program, delete the local split, open profile → no "Sent" button for the gone program.

### L items (same phase, small)

- `ProgramLibraryViewModel.pendingInvite(id:)` at `:131-133` — remove, or use in preview binding logic.
- `ProgramSerializer.outgoingAttribution()` — drop optional `creator` override path; derive attribution inside the function.
- `RealtimeService.subscribeToProgramInvites:329` — extend filter to also match `sender_user_id=eq.$userId` so senders' UI auto-refreshes. Verify RLS allows senders to read their own invites.
- `ProgramInviteViewModel:73-75` deserialization fallback — require non-null `creator` at serialization time in `ProgramSerializer.toStructure(...)`; at deserialize time throw instead of falling back to sender.
- `ProgramActivationViewModel.activate(split:)` → make `async`, `await plannerStore.activate(...)` from `async` body. Add validation: `startDate >= today` and `split.isActive == false`.

---

## Phase 4 — Observer / Task leaks (H2, H3, H4, H7, M4, M5)

### H2. `FeedViewModel` observer removal

Files:

- `Features/Social/ViewModels/FeedViewModel.swift:54,75`

Steps:

1. Add property: `@ObservationIgnored private var commentObserverToken: NSObjectProtocol?`
2. Store the token from `addObserver(forName:object:queue:using:)`.
3. In `deinit`:
   ```swift
   if let token = commentObserverToken {
       NotificationCenter.default.removeObserver(token)
   }
   ```
4. Keep existing `cancellables.removeAll()` path unchanged.

Verification:

- Memory Graph Debugger: navigate to Feed and back 10x; confirm exactly one `FeedViewModel` instance alive, observer count doesn't grow.

### H3. `RealtimeService.statusChange` Task lifecycle

Files:

- `Features/Social/Services/RealtimeService.swift:281` and surrounding subscribe/unsubscribe methods

Steps:

1. Add property: `private var statusMonitorTasks: [String: Task<Void, Never>] = [:]` keyed by `channelId`.
2. Before spawning a new monitor, cancel any existing one for that channel.
3. On `unsubscribe(channelId:)` and `unsubscribeAll()`, cancel and clear.
4. Confirm the existing re-subscribe-on-foreground path (from `virtual-run-invariants.md`) still works.

Verification:

- Background + foreground 10 cycles → confirm `statusMonitorTasks.count` stays bounded to at most one per active channel.

### H4. `RealtimeService` observation token storage

Files:

- `Features/Social/Services/RealtimeService.swift:54` (`subscribeToNewPosts`) and `:372` (`subscribeToFriendships`)

Steps:

1. For each method, capture the return of `await channel.onPostgresChange(...)` into `observationTokens[channelId] = changes`, mirroring `subscribeToNotifications` and `subscribeToProgramInvites`.
2. On `unsubscribe(channelId:)`, the existing cleanup path handles token teardown.

Verification:

- Subscribe, send a relevant DB change via Supabase dashboard, confirm event arrives.
- Unsubscribe, send change again, confirm no event.

### H7. `WorkoutStoreV2` toast callbacks weak-self

Files:

- `Features/WorkoutSession/Services/WorkoutStoreV2.swift:316,1013`

Steps:

1. Change to `{ [weak self] in self?.undoDiscardWorkout() }` and `{ [weak self] in self?.undoDeleteWorkout(...) }` (or equivalent).

Verification: discard a workout, tap undo — works. Delete workout, tap undo — works. Memory graph: no retain cycle.

### M4. `NotificationBadgeManager` toast action weak-self

Files:

- `Features/Social/Services/NotificationBadgeManager.swift:298-314`

Steps:

1. Wrap `label`/`onTap` closures in `[weak self]` capture lists.

### M5. `NotificationBadgeManager` realtime callback safe self-hop

Files:

- `Features/Social/Services/NotificationBadgeManager.swift:114,139`

Steps:

1. Replace:
   ```swift
   { [weak self] notification in
       guard let self = self else { return }
       Task { @MainActor in
           await self.refreshNotificationCount(userId: userId)
           await self.showNotificationToast(notification)
       }
   }
   ```
   with:
   ```swift
   { [weak self] notification in
       let capturedUserId = userId
       Task { @MainActor [weak self] in
           guard let self else { return }
           await self.refreshNotificationCount(userId: capturedUserId)
           await self.showNotificationToast(notification)
       }
   }
   ```

Verification:

- Realtime notification arrives → count updates + toast appears.
- Swift 6 strict mode: no "Sending 'self' risks causing data races" warning.

---

## Phase 5 — Rewards engine safety (H8, H9)

### H8. Bound auto-freeze backfill by date window

Files:

- `Features/Rewards/Models/StreakResult.swift` (rebuild branch, ~line 890)

Steps:

1. Define a bound: `weeklyFreezeBackfillMaxAgeWeeks = 6` (configurable; 6 weeks matches "this and last month").
2. In the "Backfilled historical weekly freeze" branch, add a guard:
   ```swift
   guard let lastUsed = oldFreezeUsedAt,
         let weeksAgo = calendar.dateComponents([.weekOfYear], from: lastUsed, to: now).weekOfYear,
         weeksAgo <= weeklyFreezeBackfillMaxAgeWeeks else {
       // Backfill expired — do not retroactively rescue.
       break
   }
   ```
3. Also log when a backfill is skipped because of the bound, so we can measure frequency before/after.

Verification:

- Seed a test case: `oldFreezeUsedAt = 8 weeks ago`, streak breaks → backfill does NOT apply → streak resets honestly.
- `oldFreezeUsedAt = 2 weeks ago` → backfill applies → streak preserved.
- Unit test the `hasWeeklyFreezeAvailable` interaction.

### H9. `validateWeeklyStreakOnAppear` single call on active phase

Files:

- `App/AppShellView.swift:371,375,457`

Steps:

1. Remove the unconditional call at `:371`.
2. Keep the call at `:375` (inside `if healthKit.connected`) — that's the one that needs fresh HK data.
3. For the non-connected case, call `validateWeeklyStreakOnAppear` once at the end of the scene-active block.
4. Remove redundant `:457` call OR keep it as the cold-start call and remove one of the scene-active ones — pick ONE authoritative location.

Decision table:

| Path             | Should validate? | Where                                    |
|------------------|------------------|------------------------------------------|
| Cold start       | Yes              | `AppShellView.bootstrap()` after configure |
| Scene active     | Yes, once        | `.onChange(of: scenePhase) .active` block |
| HK sync finish   | No separate call | Validate already covered by scene-active |

Verification:

- Instrument log output: exactly one "Rebuilt streak" log per app launch, one per foreground transition.

---

## Phase 6 — Performance (H11, M3)

### H11. Fix `backfillDexStampsIfNeeded` N+1

Files:

- `Features/Rewards/Services/RewardEngine.swift:26-50`

Steps:

1. Replace the in-loop fetch with a pre-fetched set:
   ```swift
   let prs = (try? context.fetch(FetchDescriptor<ExercisePR>())) ?? []
   let stampKeys = Set((try? context.fetch(FetchDescriptor<DexStamp>()))?.map(\.key) ?? [])
   for pr in prs {
       let key = canonicalExerciseKey(from: pr.exerciseId)
       guard !stampKeys.contains(key) else { continue }
       context.insert(DexStamp(key: key, unlockedAt: pr.updatedAt))
   }
   try? context.save()
   ```

Verification:

- Launch on a device with 100+ PRs. Instrument with os_signpost on the backfill block before/after change. Expect ~100x fewer SQL queries.

### M3. `CacheManager.clearExpiredCache` batch delete

Files:

- `Core/Services/CacheManager.swift:229-255`

Steps:

1. Compute TTL cutoff date once.
2. For each model type:
   ```swift
   try modelContext.delete(model: CachedPost.self, where: #Predicate { $0.cachedAt < cutoff })
   try modelContext.delete(model: CachedProfile.self, where: #Predicate { $0.cachedAt < cutoff })
   try modelContext.delete(model: CachedNotification.self, where: #Predicate { $0.cachedAt < cutoff })
   try modelContext.save()
   ```
3. Keep error handling explicit — log on failure, do not swallow.

Verification: seed 1000 expired cache rows, measure before/after; confirm one DELETE statement per model via SwiftData logging.

---

## Phase 7 — UX / layout (H10, M13)

### H10. Shell tab-bar hide failsafe

Files:

- `App/AppShellView.swift` (add `.onChange(of: selectedTab)`)
- `Features/Planner/PlannerSetupCarouselView.swift:131-135`

Best-practice alternative: replace the NotificationCenter contract with an `@Environment(\.shellChrome)` or explicit `@Binding`, but that's a bigger refactor. Minimum viable:

Steps:

1. Add failsafe to shell:
   ```swift
   .onChange(of: selectedTab) { _, _ in
       isShellTabBarHidden = false
   }
   ```
2. On root view `.onReceive` of `UIApplication.didBecomeActiveNotification`, reset `isShellTabBarHidden = false` if no presented planner flow.
3. Document the contract in `AppEvents.swift` comment near the notification name: "post hide on presenter appear, show on presenter disappear; shell will auto-reset on tab change as safety net".

Verification:

- Force-quit during planner setup → relaunch → tab bar visible.
- Switch tabs while planner modal open → tab bar returns visible.
- Normal flow: no regression.

### M13. Gesture conflict check

Files:

- `Features/Planner/CalendarMonthView.swift:174`

Steps:

1. Leave as `simultaneousGesture` for now (the change was likely intentional to let tap + swipe coexist).
2. Add explicit test: vertical scroll inside a day cell should not trigger month change.
3. If test fails, revert to `.gesture` or add `minimumDistance` tuning on the swipe `DragGesture`.

Verification: manual on a device — scroll long list in day details, confirm no month jumps.

---

## Phase 8A — Isolated persistence migration work (M1 only)

### M1. Introduce `VersionedSchema` baseline

Files:

- `App/WRKTApp.swift:243-251`
- new `Core/Persistence/AppSchema.swift`

Steps:

1. Create `enum AppSchemaV1: VersionedSchema` listing all current `@Model` types as `models:`.
2. Create `enum AppMigrationPlan: SchemaMigrationPlan` with `schemas: [AppSchemaV1.self]` and empty `stages`.
3. Replace `ModelContainer(for: Schema([...]))` with `ModelContainer(for: AppSchemaV1.self, migrationPlan: AppMigrationPlan.self, ...)`.
4. Document in the new file: "Add a new schema version for every non-optional field addition, rename, or type change."

Verification:

- Fresh install: app launches, all features work.
- Upgrade install (pre-change build → post-change build): app launches, existing SwiftData stores open without migration loss.

This is a foundational container/bootstrap change. Ship it in its own PR after the faster additive fixes have landed. Do not batch it with `C3`.

---

## Phase 8B — Migration hygiene / Swift 6 cleanup (M2, M7, M8, M9, M11, M12, L)

### M2. `current_workout_v2.json` rotating backup

Files:

- `Core/Persistence/WorkoutStorage.swift:262-275`

Steps:

1. Add `createCurrentWorkoutBackupIfNeeded()` mirroring `createWorkoutsBackupIfNeeded()` (debounce, rotation, 5-backup cap).
2. Call at the top of `saveCurrentWorkout(_:)` when the workout is non-nil.
3. Add recovery probe in `loadCurrentWorkout()` — if main file fails to decode, try latest non-empty backup.
4. Optional: extend same pattern to `ignoredHealthKitUUIDs` and `discardedWorkoutWindows` (lower priority — can be rebuilt).

Verification: during an active workout, force-quit, relaunch, confirm current workout restored.

### M7. `setupBackgroundObservers` idempotency

Files:

- `Features/Health/Services/HealthKitManager.swift:220`

Steps:

1. At the top of `setupBackgroundObservers()`, call `stopBackgroundObservers()` first.
2. `stopBackgroundObservers()` already handles nil properties; confirm idempotent.

Verification: re-trigger HK authorization flow mid-session, confirm no orphaned queries (breakpoint on HKObserverQuery init count).

### M8. `WorkoutStoreV2.init` Task with weak self

Files:

- `Features/WorkoutSession/Services/WorkoutStoreV2.swift:114`

Steps:

1. Change to:
   ```swift
   Task { [weak self] in
       guard let self else { return }
       // existing body unchanged
   }
   ```
2. For `self.completedWorkouts = ...` accesses, ensure they happen on MainActor (store is `@MainActor`).

Verification: build with strict concurrency, no warnings on this block.

### M9. `updateCompetitiveFeatures` pre-capture values

Files:

- `Features/WorkoutSession/Services/WorkoutStoreV2.swift:1782`

Steps:

1. Extract all needed fields (`userId`, `workout` snapshot, any other MainActor state) into local constants BEFORE `Task.detached`.
2. Remove `self` from capture list; capture only value types and the two repos already captured.

Verification: strict concurrency build clean; competitive features still update on workout finish.

### M11. `AppDependencies.configure` weak self

Files:

- `Core/Dependencies/AppDependencies.swift:144`

Steps:

1. Add `[weak self]` capture; `guard let self else { return }` inside.

### M12. Remove redundant `Task { @MainActor in }` in `resetAll`

Files:

- `Features/Rewards/Services/RewardEngine.swift:175`

Steps:

1. Replace:
   ```swift
   Task { @MainActor in
       BarbellProgressService.shared.resetAll()
   }
   ```
   with a direct call:
   ```swift
   BarbellProgressService.shared.resetAll()
   ```
2. Confirm `RewardsEngine` is `@MainActor` (it is).
3. Confirm `BarbellProgressService.resetAll()` is sync / MainActor-callable.

Verification: reset all data flow, confirm barbell rack room and plates all clear.

### L items

- **`Persistence/Persistence.swift` legacy actor**: add a `@available(*, deprecated)` annotation, grep for call sites, plan a removal in a follow-up PR. Do not delete yet — the file is referenced by `WorkoutStorage.migrateFromLegacyStorage()` for legacy-file reads.
- **`BarbellAudioBuilder.audioResourceCache` eviction (M6)**: add a public `clearAudioCache()` called from `BarbellRealityView.onDisappear`. Keep the cache for in-scene re-entry performance.

---

## Verification strategy

Per phase:

1. Build iOS + Watch targets. Clean DerivedData first (environment-first per Axiom `ios-build`).
2. Run existing test suites: `WRKTTests`, `WRKT Watch Watch AppTests`, `WRKT Watch Watch AppUITests`.
3. Targeted manual tests listed per item.
4. Memory Graph Debugger + Instruments Leaks for Phase 4.
5. Enable `-strict-concurrency=targeted` incrementally after Phase 2 to catch regressions.

## Ordering rationale

- Phase 1 fixes block a broken user flow (C1) and unship-safe crashes (C2, C3).
- Phase 2 (Swift 6 foundation) is prerequisite for Phases 4-8B which lean on cleaner concurrency semantics.
- Phase 3 is self-contained to one feature.
- Phases 4-5 compound gradually; independent.
- Phases 6-8B are safe to parallelize across contributors once Phase 8A is intentionally scheduled as its own persistence PR.

## What this plan does NOT change

- No WCSession `nonisolated` delegate refactors. Invariant preserved.
- No `CLLocationManager` accuracy changes.
- No `HKSampleQuery` sort descriptor changes.
- No iPhone↔Watch message key unification.
- No `VirtualRunManager` isolation changes.
- No planner/rolling-policy redesign (out of scope — already tracked in master-ranked-issues).

## Rollback strategy

Every phase is a separate branch/PR. Each item inside a phase should be an individual commit where feasible. Reverting any single commit should leave the app in a working state.

For SwiftData model changes (C3, M1): do NOT revert once shipped to TestFlight — the store has already been migrated. Instead, roll forward with a new additive fix.
