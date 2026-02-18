a# WRKT — Axiom Audit Guide

Project analysis based on the current codebase. Each audit below explains what it checks, why it matters for WRKT specifically, and what areas of the codebase are most relevant.

---

## CRITICAL Priority

### 1. Concurrency (`axiom:audit concurrency`)

**What it checks:** Swift 6 data races, unsafe Task captures, actor isolation violations, Sendable conformance, and improper MainActor usage.

**Why it matters for WRKT:**
- **1,064 async/await usages** across 121 files — the most concurrency-heavy part of the codebase.
- WCSession delegate methods are `nonisolated` and dispatch to `@MainActor` via `Task { @MainActor in }`. This pattern is correct but fragile — any missed dispatch creates a data race.
- `VirtualRunManager` is `@Observable @MainActor`, and all calls from WCSession handlers need MainActor dispatch. A missed annotation means silent corruption.
- HealthKit queries use completion handlers bridged to async/await. Incorrect bridging (e.g., double-resuming a continuation) causes crashes.
- Supabase Realtime callbacks fire on background threads and forward to UI — every callback site is a potential isolation violation.

**Key files to audit:**
- `Core/Services/WatchConnectivityManager.swift` (1,400 lines, mixed isolation)
- `WRKT Watch Watch App/WatchConnectivityManager.swift` (nonisolated delegates)
- `Features/Health/Services/HealthKitManager.swift` (85 async/await usages)
- `Features/Social/Services/VirtualRunRepository.swift` (41 async usages)
- `Features/WorkoutSession/Services/WorkoutStoreV2.swift` (40 async usages)
- `WRKT Watch Watch App/VirtualRunManager.swift` (@Observable @MainActor singleton)

---

### 2. Memory (`axiom:audit memory`)

**What it checks:** Retain cycles from closures, leaked Timers, unremoved NotificationCenter observers, strong self captures in async tasks, and delegate reference cycles.

**Why it matters for WRKT:**
- **196 NotificationCenter usages** across 62 files. Any `addObserver` without a corresponding removal leaks the observer and its closure's captured references.
- **18+ Timer instances** — `Timer.scheduledTimer` retains its target. If the target holds the timer, you get a retain cycle. The Watch `VirtualRunFileLogger` flush timer and `VirtualRunManager` publish/heartbeat timers are particularly risky since they run during workouts (long-lived sessions).
- Supabase Realtime subscriptions capture `self` in callbacks — if the view/coordinator is dismissed without unsubscribing, the subscription keeps the object alive.
- `WatchConnectivityManager` uses `[weak self]` in some closures but not all — inconsistency means some paths leak.

**Key files to audit:**
- `Features/Social/Services/VirtualRunInviteCoordinator.swift` (fallback timer + Realtime subscription)
- `WRKT Watch Watch App/Utilities/VirtualRunFileLogger.swift` (flush timer)
- `WRKT Watch Watch App/VirtualRunManager.swift` (multiple timers: publish, heartbeat, snapshot)
- `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift` (timer lifecycle)
- `Core/Services/QueryCache.swift` (cleanup timer every 5 minutes)
- Any file using `NotificationCenter.default.addObserver` without `removeObserver`

---

### 3. Energy (`axiom:audit energy`)

**What it checks:** Timer abuse (too frequent, not invalidated), continuous location tracking, polling instead of push, animation loops that never stop, unnecessary background modes, and HealthKit query frequency.

**Why it matters for WRKT:**
- **CLLocationManager in 12 files** — location tracking is one of the biggest battery drains on iOS. During virtual runs, both the Watch and iPhone may be tracking location simultaneously.
- **Polling patterns** — `VirtualRunInviteCoordinator` polls every 30s as a fallback. `VirtualRunMapComparisonView` polls every 10s for partner routes (up to 6 minutes). These should ideally be push-based.
- **Timer frequency** — Virtual run snapshots publish every 3s during active runs. The file logger flushes every 2s. The rest timer ticks every second. During a virtual run with rest timer active, multiple timers fire concurrently.
- **HealthKit queries** — Route data fetching uses `HKAnchoredObjectQuery` observers that remain active. Heart rate streaming during workouts runs continuously.
- **Watch background modes** — `workout-processing` keeps the Watch app alive during workouts, which is correct but means any inefficiency is amplified.

**Key files to audit:**
- `Features/Health/Services/HealthKitManager.swift` (continuous queries)
- `WRKT Watch Watch App/WatchHealthKitManager.swift` (workout session + HR streaming)
- `Features/Social/Services/VirtualRunInviteCoordinator.swift` (30s polling)
- `Features/Social/Views/VirtualRunMapComparisonView.swift` (10s polling loop)
- `Core/Services/WatchConnectivityManager.swift` (snapshot publishing frequency)

---

## HIGH Priority

### 4. SwiftUI Performance (`axiom:audit swiftui-performance`)

**What it checks:** Expensive operations in view `body`, DateFormatter/NumberFormatter created inline, whole-collection identity causing full redraws, missing `LazyVStack`/`LazyHStack`, unnecessary `@State` invalidation, and large view hierarchies.

**Why it matters for WRKT:**
- **214 SwiftUI files** — the entire UI layer. Any performance issue in a frequently-visited view (Home, Live Workout, Exercise Session) affects perceived app quality.
- **34 GeometryReader usages** — GeometryReader forces eager evaluation and can cause layout thrashing if used inside scroll views or lazy stacks.
- `ExcerciseSessionView.swift` is a particularly large file with complex view composition — any expensive computation in its body will cause lag during workout logging (the most time-critical flow).
- `HomeViewNew.swift` renders multiple cards (hero button, weekly progress, friend activity) — if any card triggers excessive redraws, the entire home screen stutters.
- The exercise browser (`BodyBrowse.swift`) filters hundreds of exercises with debounced search — the filtering itself is async, but the view updates might cause unnecessary redraws.

**Key files to audit:**
- `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift` (large, complex)
- `Features/Home/HomeViewNew.swift` (multiple dynamic cards)
- `Features/ExerciseRepository/Views/BodyBrowse.swift` (large list with filters)
- `Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutOverlayCard.swift` (1,400+ lines)
- `Features/Health/Views/CardioDetailView.swift` (charts + map rendering)

---

### 5. Modernization (`axiom:audit modernization`)

**What it checks:** `ObservableObject` → `@Observable` migration, `@StateObject` → `@State`, `@Published` → direct properties, `@EnvironmentObject` → `@Environment`, and other deprecated API usage.

**Why it matters for WRKT:**
- **53 `ObservableObject`/`@StateObject` usages** still remain alongside **548 `@Observable`/`@State` usages**. The codebase is mid-migration — mixing both patterns creates inconsistency and subtle bugs.
- `@EnvironmentObject` requires manual injection at every level of the view hierarchy. Missing it causes a runtime crash (not a compile error). `@Environment` with `@Observable` is safer.
- Key services like `ExerciseRepository`, `WorkoutStoreV2`, and `SupabaseAuthService` use `@EnvironmentObject` — these are injected at the app root and passed through dozens of views.
- `@StateObject` has specific initialization semantics (only created once) that `@State` with `@Observable` handles differently. Incorrect migration can cause objects to be recreated on view updates.

**Key files to audit:**
- `Core/Dependencies/AppDependencies.swift` (dependency injection root)
- Any file with `@EnvironmentObject` declarations
- Any file with `ObservableObject` conformance
- `Features/ExerciseRepository/Services/ExerciseRepository.swift`
- `Features/WorkoutSession/Services/WorkoutStoreV2.swift`

---

### 6. Security (`axiom:audit security`)

**What it checks:** Hardcoded API keys, secrets in source control, insecure data storage (UserDefaults for sensitive data), missing Privacy Manifests, App Transport Security exceptions, and insecure network calls.

**Why it matters for WRKT:**
- **Supabase credentials** — `SupabaseConfig.swift` loads keys from `Info.plist`, which is better than hardcoding but the anon key is still bundled in the app binary. The anon key is designed to be public, but if any service-role key leaked, it would be catastrophic.
- **AuthKey_623J5TADK8.p8** — an Apple authentication key file is present in the project root and appears in the git status as untracked. This file should never be committed.
- **UserDefaults for state** — rest timer state, workout data, and user preferences are stored in UserDefaults. If any sensitive health data is stored there, it's unencrypted.
- **285 Supabase network calls** — Row Level Security (RLS) policies are the primary access control. Any misconfigured policy exposes user data. The 29 migration files define these policies.
- **HealthKit data** — health data has strict Apple privacy requirements. Any sharing/uploading of health metrics (like to Supabase for virtual runs) needs explicit user consent.

**Key files to audit:**
- `Core/Configuration/` (Supabase config)
- `AuthKey_623J5TADK8.p8` (should not be in repo)
- `database_migrations/` (RLS policy definitions)
- `Features/Social/Services/` (data shared between users)
- Privacy manifest and `Info.plist` entries

---

## MEDIUM Priority

### 7. SwiftData (`axiom:audit swiftdata`)

**What it checks:** `@Model` struct issues (should be class), missing `VersionedSchema`, relationship defaults, migration timing, N+1 query patterns, and context threading violations.

**Why it matters for WRKT:**
- **30 `@Model` usages** across 12 files — SwiftData is used for local persistence of PRs, cached social data, weekly goals, and health sync anchors.
- `ExercisePR`, `CachedNotification`, `CachedPost`, `CachedProfile` are all `@Model` classes. If relationships between them aren't properly configured, cascade deletes can corrupt data.
- `WeeklyGoal` is queried frequently (home view, profile, rewards engine). N+1 patterns here cause visible lag.
- `RewardEngine` uses SwiftData extensively — if it's performing writes on the main thread during workout completion, it blocks the finish animation.
- No `VersionedSchema` was found in the initial analysis — if the schema has changed between app versions without a migration plan, users updating the app could lose data.

**Key files to audit:**
- `Core/Models/ExercisePR.swift`
- `Core/Models/CachedNotification.swift`, `CachedPost.swift`, `CachedProfile.swift`
- `Features/Profile/Models/WeeklyGoal.swift`
- `Features/Health/Models/HealthSyncAnchor.swift`
- `Features/Rewards/Services/RewardEngine.swift`
- `Persistence/Persistence.swift` (SwiftData container setup)

---

### 8. Database Schema (`axiom:audit database-schema`)

**What it checks:** Unsafe `ALTER TABLE` / `DROP` operations, missing idempotency (`IF NOT EXISTS`), foreign key misuse, missing indexes, transaction safety, and RLS policy gaps.

**Why it matters for WRKT:**
- **37 SQL migration files** (000–029 plus extras) define the entire Supabase schema. These run against a live production database.
- Migration 027 previously failed because columns already existed — fixed with `IF NOT EXISTS`, but other migrations may have the same issue.
- RLS policies are critical — they're the only thing preventing users from reading/modifying each other's data. The virtual run routes bucket had a UUID case mismatch that silently blocked all uploads.
- Foreign key relationships between `virtual_runs`, `virtual_run_snapshots`, and user profiles need proper cascade behavior.
- Some migrations create indexes — missing indexes on frequently-queried columns (like `inviter_id`, `invitee_id`, `status`) cause slow queries at scale.

**Key files to audit:**
- `database_migrations/` (all 37 files)
- `database_indexes.sql`
- `database_views.sql`
- `fix_profile_rls.sql`, `fix_storage_rls.sql`

---

### 9. Networking (`axiom:audit networking`)

**What it checks:** Deprecated APIs (like `SCNetworkReachability`), missing timeout configuration, no retry logic, unhandled HTTP status codes, missing background session support, and certificate pinning.

**Why it matters for WRKT:**
- **Supabase is the entire backend** — every social feature, authentication, and real-time sync goes through Supabase. Network failures need graceful handling.
- Realtime subscriptions (`RealtimeService`) can silently disconnect. If the app doesn't detect and reconnect, virtual run partner updates stop flowing.
- Route uploads use Supabase Storage — large uploads (even downsampled to ~35KB) need proper retry logic and timeout handling.
- The app likely doesn't implement background URLSession for uploads — if the user switches apps during a route upload, it may fail silently.
- Virtual run snapshot publishing happens every 3s. If the network is slow, requests can queue up and create a backlog.

**Key files to audit:**
- `Core/Services/RealtimeService.swift`
- `Features/Social/Services/VirtualRunRepository.swift` (upload/download)
- `Core/Services/SupabaseClientWrapper.swift`
- `Features/Social/Services/PostRepository.swift`
- `Features/Social/Services/FriendshipRepository.swift`

---

## LOW Priority

### 10. Testing (`axiom:audit testing`)

**What it checks:** Flaky tests, slow tests, missing assertions, Swift Testing migration opportunities, test coverage gaps, and mock/stub quality.

**Why it matters for WRKT:**
- **Only 10 test files** for a codebase with 200+ Swift files — significant coverage gaps.
- Tests exist for core models (`CompletedWorkout`, `CurrentWorkout`, `ExerciseDefinition`, `WorkoutEntry`) and storage (`WorkoutStorage`), but no tests for:
  - Virtual run flow (invite → accept → sync → end)
  - Supabase repository methods
  - WatchConnectivity message handling
  - Rest timer state machine
  - Reward engine calculations
  - Progressive overload suggestions
- The most bug-prone areas (virtual runs, Watch communication) have zero test coverage, meaning bugs are only caught through manual testing.
- No UI tests were found — the complex flows (workout session, exercise browser with filters) are untested.

**Key files to audit:**
- `WRKTTests/` (existing tests)
- `WRKT Watch Watch AppTests/` (Watch tests)
- Coverage gaps in `Features/Social/`, `Features/WorkoutSession/`, `Features/Rewards/`

---

## How to Run

Run a single audit:
```
/axiom:audit concurrency
```

Run multiple audits (results written to `scratch/` directory):
```
/axiom:audit concurrency memory energy
```

Recommended batches:
- **Pre-release**: concurrency + memory + energy + security
- **Performance tuning**: swiftui-performance + memory + energy
- **Data safety**: swiftdata + database-schema + security
- **Architecture review**: swiftui-performance + modernization + networking
