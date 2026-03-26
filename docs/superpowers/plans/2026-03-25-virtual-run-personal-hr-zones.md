# Virtual Run Personal HR Zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each virtual run participant's heart rate is shown against their own personal HR zone boundaries (maxHR + restingHR), not the viewer's zones or generic defaults.

**Architecture:** Add a `resting_hr` column to the Supabase `profiles` table so both maxHR (derived from `birth_year`) and restingHR are remotely accessible. At virtual run start the coordinator reads the partner's full zone config from their profile, then passes it through the existing iOS→Watch WCSession message. `PartnerStats` gains a `restingHR` field and `VirtualRunView.PartnerSection` uses it in the zone calculation. The user's own restingHR is also written back to Supabase after being fetched from HealthKit so their partner can read it.

**Tech Stack:** Swift/SwiftUI, watchOS, Supabase (PostgreSQL), WatchConnectivity

---

## Context

### Current zone data flow

```
enterActiveRun (VirtualRunInviteCoordinator.swift ~L520)
  ├── fetchProfile(partnerId)        → partnerMaxHR (from birth_year)
  ├── fetchAverageRestingHeartRate() → myRestingHR  (from HealthKit only)
  └── sendVirtualRunStarted(myMaxHR, myRestingHR, partnerMaxHR)
            ↓ WCSession
      Watch WatchConnectivityManager.swift ~L544
        partnerMaxHR parsed, restingHR: 0 hardcoded
        PartnerStats(maxHR: partnerMaxHR)   ← no restingHR field
            ↓
      VirtualRunView.PartnerSection ~L679
        HRZoneHelper.zone(for: hr, maxHR: p.maxHR)   ← missing restingHR
```

### What's wrong

1. `resting_hr` is not stored in Supabase, so the partner's resting HR (needed for the Karvonen formula) is never available remotely.
2. `PartnerStats` has no `restingHR` field — partner zone display always uses simple %maxHR, even when the partner has Karvonen zones set up.
3. `VirtualRunView.PartnerSection` calls `HRZoneHelper.zone(for:maxHR:)` with `restingHR` defaulting to 0.

---

## File Map

| Action | File | What changes |
|--------|------|-------------|
| Create | `database_migrations/034_add_resting_hr_to_profiles.sql` | Add `resting_hr INT` column to `profiles` |
| Modify | `Features/Social/Models/UserProfile.swift` | Add `restingHR: Int?` field + CodingKey |
| Modify | `Features/Social/Services/SupabaseAuthService.swift` | Add `restingHR` param to `updateProfile` |
| Modify | `Features/Social/Services/VirtualRunInviteCoordinator.swift` | Sync own restingHR to Supabase; fetch partner's `restingHR`; pass `partnerRestingHR` to `sendVirtualRunStarted` |
| Modify | `Core/Services/WatchConnectivityManager.swift` | Add `partnerRestingHR` param to `sendVirtualRunStarted`; include in WCSession payload |
| Modify | `Features/Social/Views/VirtualRunDebugView.swift` | Pass `partnerRestingHR` at the debug call site so simulator testing exercises real code path |
| Modify | `Shared/VirtualRunSharedModels.swift` | Add `restingHR: Int` to `PartnerStats` |
| Modify | `WRKT Watch Watch App/WatchConnectivityManager.swift` | Parse `partnerRestingHR` from message; pass to `PartnerStats` init |
| Modify | `WRKT Watch Watch App/Views/VirtualRunView.swift` | `PartnerSection.zone` uses `p.restingHR` |

---

## Task 1: Supabase migration — add resting_hr column

**Files:**
- Create: `database_migrations/034_add_resting_hr_to_profiles.sql`

- [ ] **Step 1: Create the migration file**

```sql
-- 034_add_resting_hr_to_profiles.sql
-- Stores each user's resting heart rate so virtual run partners can compute
-- accurate personalised HR zones using the Karvonen method.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS resting_hr INT;

COMMENT ON COLUMN profiles.resting_hr IS
  'Resting heart rate in BPM (from HealthKit). Used for Karvonen HR zone calculation.';
```

- [ ] **Step 2: Run in Supabase SQL editor**

Open the Supabase dashboard, go to SQL Editor, paste and run the migration. Confirm the `profiles` table now has a `resting_hr` column (nullable INT).

- [ ] **Step 3: Commit**

```bash
git add database_migrations/034_add_resting_hr_to_profiles.sql
git commit -m "Add resting_hr column to profiles for personalised HR zones"
```

---

## Task 2: UserProfile model — add restingHR field

**Files:**
- Modify: `Features/Social/Models/UserProfile.swift`

- [ ] **Step 1: Add the field and coding key**

In `Features/Social/Models/UserProfile.swift`:

```swift
// Add to stored properties (after `birthYear: Int?`):
var restingHR: Int?

// Add to CodingKeys enum (after `case birthYear = "birth_year"`):
case restingHR = "resting_hr"

// Add to memberwise init parameters (after `birthYear: Int? = nil`):
restingHR: Int? = nil

// Add to init body (after `self.birthYear = birthYear`):
self.restingHR = restingHR

// Add to init(from decoder:) (after `birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)`):
restingHR = try container.decodeIfPresent(Int.self, forKey: .restingHR)
```

The `maxHR` computed var already exists and needs no change — it still uses `birth_year`.

- [ ] **Step 2: Verify**

Build the iOS target (Cmd+B). The `UserProfile` decoder is lenient (uses `decodeIfPresent`) so existing JSON without `resting_hr` continues to decode to `nil`.

- [ ] **Step 3: Commit**

```bash
git add Features/Social/Models/UserProfile.swift
git commit -m "Add restingHR field to UserProfile (maps to resting_hr column)"
```

---

## Task 3: SupabaseAuthService — add restingHR to updateProfile

**Files:**
- Modify: `Features/Social/Services/SupabaseAuthService.swift`

The existing `updateProfile` function (line 333) accepts optional fields and only writes non-nil ones to Supabase.

- [ ] **Step 1: Add `restingHR` parameter to the function signature**

Find:
```swift
func updateProfile(username: String? = nil, displayName: String? = nil, bio: String? = nil, avatarUrl: String? = nil, isPrivate: Bool? = nil, autoPostPRs: Bool? = nil, autoPostCardio: Bool? = nil, birthYear: Int? = nil) async throws {
```

Replace with:
```swift
func updateProfile(username: String? = nil, displayName: String? = nil, bio: String? = nil, avatarUrl: String? = nil, isPrivate: Bool? = nil, autoPostPRs: Bool? = nil, autoPostCardio: Bool? = nil, birthYear: Int? = nil, restingHR: Int? = nil) async throws {
```

- [ ] **Step 2: Write restingHR to the updates dict**

Immediately after:
```swift
        if let birthYear = birthYear {
            updates["birth_year"] = .integer(birthYear)
        }
```

Add:
```swift
        if let restingHR = restingHR {
            updates["resting_hr"] = .integer(restingHR)
        }
```

- [ ] **Step 3: Build and verify**

Build iOS target. All existing call sites use named parameters so they are unaffected by the new optional parameter.

- [ ] **Step 4: Commit**

```bash
git add Features/Social/Services/SupabaseAuthService.swift
git commit -m "Add restingHR param to updateProfile for zone sync"
```

---

## Task 4: VirtualRunInviteCoordinator — sync restingHR and fetch partner's

**Files:**
- Modify: `Features/Social/Services/VirtualRunInviteCoordinator.swift` (around line 520)

The `enterActiveRun` function already:
1. Fetches partner profile to get `partnerMaxHR`
2. Fetches own resting HR from HealthKit

We need to also:
- Save own resting HR to Supabase after fetching from HealthKit
- Read partner's `restingHR` from their profile
- Pass `partnerRestingHR` into `sendVirtualRunStarted`

- [ ] **Step 1: Read partner's restingHR and sync own**

Find (around line 520):
```swift
        // Fetch partner's maxHR and my resting HR for Watch HR zone display
        var partnerMaxHR = 190
        if let partnerProfile = try? await SupabaseAuthService.shared.fetchProfile(userId: partnerId) {
            partnerMaxHR = partnerProfile.maxHR
        }

        let myRestingHR: Int
        if let rhr = try? await HealthKitManager.shared.fetchAverageRestingHeartRate() {
            myRestingHR = Int(rhr)
            HRZoneCalculator.shared.setRestingHR(rhr)
        } else {
            myRestingHR = 0
        }

        // Notify Watch to start the virtual run
        WatchConnectivityManager.shared.sendVirtualRunStarted(
            runId: run.id,
            partnerId: partnerId,
            partnerName: partnerName,
            myUserId: myUserId,
            myRestingHR: myRestingHR,
            partnerMaxHR: partnerMaxHR
        )
```

Replace with:
```swift
        // Fetch partner's zone config and my resting HR for Watch HR zone display
        var partnerMaxHR = 190
        var partnerRestingHR = 0
        if let partnerProfile = try? await SupabaseAuthService.shared.fetchProfile(userId: partnerId) {
            partnerMaxHR = partnerProfile.maxHR
            partnerRestingHR = partnerProfile.restingHR ?? 0
        }

        let myRestingHR: Int
        if let rhr = try? await HealthKitManager.shared.fetchAverageRestingHeartRate() {
            myRestingHR = Int(rhr)
            HRZoneCalculator.shared.setRestingHR(rhr)
            // Sync to Supabase so our partner can read it in their next run
            try? await SupabaseAuthService.shared.updateProfile(restingHR: myRestingHR)
        } else {
            myRestingHR = 0
        }

        // Notify Watch to start the virtual run
        WatchConnectivityManager.shared.sendVirtualRunStarted(
            runId: run.id,
            partnerId: partnerId,
            partnerName: partnerName,
            myUserId: myUserId,
            myRestingHR: myRestingHR,
            partnerMaxHR: partnerMaxHR,
            partnerRestingHR: partnerRestingHR
        )
```

- [ ] **Step 2: Build and verify**

The call to `sendVirtualRunStarted` will fail to compile until Task 5 adds the new parameter. That is expected — fix it in Task 5.

- [ ] **Step 3: Commit after Task 5 builds cleanly** (see Task 5 step 3)

---

## Task 5: iOS WatchConnectivityManager — add partnerRestingHR to WCSession message

**Files:**
- Modify: `Core/Services/WatchConnectivityManager.swift` (around line 1196)

- [ ] **Step 1: Add `partnerRestingHR` parameter to `sendVirtualRunStarted`**

Find:
```swift
    func sendVirtualRunStarted(runId: UUID, partnerId: UUID, partnerName: String, myUserId: UUID, myMaxHR: Int? = nil, myRestingHR: Int = 0, partnerMaxHR: Int = 190) {
```

Replace with:
```swift
    func sendVirtualRunStarted(runId: UUID, partnerId: UUID, partnerName: String, myUserId: UUID, myMaxHR: Int? = nil, myRestingHR: Int = 0, partnerMaxHR: Int = 190, partnerRestingHR: Int = 0) {
```

- [ ] **Step 2: Add `partnerRestingHR` to the payload dict**

Find the `info` dictionary construction (around line 1210):
```swift
        let info: [String: Any] = [
            "runId": runId.uuidString,
            "partnerId": partnerId.uuidString,
            "partnerName": partnerName,
            "myUserId": myUserId.uuidString,
            "myMaxHR": resolvedMaxHR,
            "myRestingHR": myRestingHR,
            "partnerMaxHR": partnerMaxHR
        ]
```

Replace with:
```swift
        let info: [String: Any] = [
            "runId": runId.uuidString,
            "partnerId": partnerId.uuidString,
            "partnerName": partnerName,
            "myUserId": myUserId.uuidString,
            "myMaxHR": resolvedMaxHR,
            "myRestingHR": myRestingHR,
            "partnerMaxHR": partnerMaxHR,
            "partnerRestingHR": partnerRestingHR
        ]
```

- [ ] **Step 3: Update the debug view call site**

In `Features/Social/Views/VirtualRunDebugView.swift` (around line 303), the debug view fetches `partnerProfile` above the call. Update to also pass `partnerRestingHR`:

Find:
```swift
                var partnerMaxHR = 190
                if let partnerProfile = try? await authService.fetchProfile(userId: testUserId) {
                    partnerMaxHR = partnerProfile.maxHR
                    log("Partner maxHR: \(partnerMaxHR) (birth year: \(partnerProfile.birthYear.map { String($0) } ?? "nil"))")
                }
                WatchConnectivityManager.shared.sendVirtualRunStarted(
                    ...
                    partnerMaxHR: partnerMaxHR
                )
```

Replace with:
```swift
                var partnerMaxHR = 190
                var partnerRestingHR = 0
                if let partnerProfile = try? await authService.fetchProfile(userId: testUserId) {
                    partnerMaxHR = partnerProfile.maxHR
                    partnerRestingHR = partnerProfile.restingHR ?? 0
                    log("Partner maxHR: \(partnerMaxHR) (birth year: \(partnerProfile.birthYear.map { String($0) } ?? "nil")), restingHR: \(partnerRestingHR)")
                }
                WatchConnectivityManager.shared.sendVirtualRunStarted(
                    ...
                    partnerMaxHR: partnerMaxHR,
                    partnerRestingHR: partnerRestingHR
                )
```

- [ ] **Step 4: Build both targets and commit**

```bash
git add Features/Social/Services/VirtualRunInviteCoordinator.swift \
        Core/Services/WatchConnectivityManager.swift \
        Features/Social/Views/VirtualRunDebugView.swift
git commit -m "Pass partner restingHR through WCSession message for personalised zones"
```

---

## Task 6: Shared models — add restingHR to PartnerStats

**Files:**
- Modify: `Shared/VirtualRunSharedModels.swift`

`PartnerStats` is a class used on both iOS and Watch.

- [ ] **Step 1: Add `restingHR` stored property**

Find (around line 131):
```swift
    let maxHR: Int
```

Replace with:
```swift
    let maxHR: Int
    let restingHR: Int
```

- [ ] **Step 2: Update the initializer**

Find:
```swift
    init(userId: UUID, displayName: String, avatarUrl: String? = nil, maxHR: Int = 190) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.maxHR = maxHR
    }
```

Replace with:
```swift
    init(userId: UUID, displayName: String, avatarUrl: String? = nil, maxHR: Int = 190, restingHR: Int = 0) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.maxHR = maxHR
        self.restingHR = restingHR
    }
```

- [ ] **Step 3: Build and verify**

All existing `PartnerStats(...)` call sites use `restingHR` default `0` so they continue to compile unchanged. The one new call site in Watch WCM (Task 7) will pass the parsed value.

- [ ] **Step 4: Commit**

```bash
git add Shared/VirtualRunSharedModels.swift
git commit -m "Add restingHR field to PartnerStats"
```

---

## Task 7: Watch WatchConnectivityManager — parse and pass partnerRestingHR

**Files:**
- Modify: `WRKT Watch Watch App/WatchConnectivityManager.swift` (around line 544)

- [ ] **Step 1: Parse `partnerRestingHR` from the incoming message**

Find (around line 544):
```swift
            let myMaxHR = info["myMaxHR"] as? Int ?? 190
            let myRestingHR = info["myRestingHR"] as? Int ?? 0
            let partnerMaxHR = info["partnerMaxHR"] as? Int ?? 190

            logger.info("🏃 Virtual run started with \(partnerName), myMaxHR=\(myMaxHR), myRestingHR=\(myRestingHR), partnerMaxHR=\(partnerMaxHR)")
```

Replace with:
```swift
            let myMaxHR = info["myMaxHR"] as? Int ?? 190
            let myRestingHR = info["myRestingHR"] as? Int ?? 0
            let partnerMaxHR = info["partnerMaxHR"] as? Int ?? 190
            let partnerRestingHR = info["partnerRestingHR"] as? Int ?? 0

            logger.info("🏃 Virtual run started with \(partnerName), myMaxHR=\(myMaxHR), myRestingHR=\(myRestingHR), partnerMaxHR=\(partnerMaxHR), partnerRestingHR=\(partnerRestingHR)")
```

- [ ] **Step 2: Pass `partnerRestingHR` when constructing `PartnerStats`**

Find:
```swift
            let partner = PartnerStats(userId: partnerId, displayName: partnerName, maxHR: partnerMaxHR)
```

Replace with:
```swift
            let partner = PartnerStats(userId: partnerId, displayName: partnerName, maxHR: partnerMaxHR, restingHR: partnerRestingHR)
```

- [ ] **Step 3: Build Watch target and commit**

```bash
git add "WRKT Watch Watch App/WatchConnectivityManager.swift"
git commit -m "Parse and forward partnerRestingHR in Watch WCM"
```

---

## Task 8: VirtualRunView — use partner's restingHR in zone calculation

**Files:**
- Modify: `WRKT Watch Watch App/Views/VirtualRunView.swift` (around line 675)

- [ ] **Step 1: Update PartnerSection zone calculation**

Find (around line 675):
```swift
    private var zone: HRZone {
        guard let p = partner, let hr = p.heartRate, hr > 0 else {
            return HRZone(number: 0, name: "", color: .clear)
        }
        return HRZoneHelper.zone(for: hr, maxHR: p.maxHR)
    }
```

Replace with:
```swift
    private var zone: HRZone {
        guard let p = partner, let hr = p.heartRate, hr > 0 else {
            return HRZone(number: 0, name: "", color: .clear)
        }
        return HRZoneHelper.zone(for: hr, maxHR: p.maxHR, restingHR: p.restingHR)
    }
```

- [ ] **Step 2: Build Watch target**

```bash
xcodebuild -scheme "WRKT Watch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add "WRKT Watch Watch App/Views/VirtualRunView.swift"
git commit -m "Use partner restingHR in Watch zone calculation (Karvonen-aware)"
```

---

## Testing Checklist

Before shipping:
- [ ] **Supabase**: `profiles` table has `resting_hr INT` column, nullable
- [ ] **Own sync**: Start a virtual run → check Supabase dashboard → `profiles.resting_hr` updated to your HealthKit value
- [ ] **Partner zone config**: Check logs for `partnerRestingHR=<non-zero>` when partner has restingHR set in their Supabase profile
- [ ] **Watch zone display**: On Watch split screen, partner's half background color reflects their Karvonen zones when their `restingHR > 0`; simple %maxHR when `restingHR == 0`
- [ ] **My zone display**: Top half zone still uses `myMaxHR + myRestingHR` (unchanged)
- [ ] **Default fallback**: Partner with no `resting_hr` in Supabase → `partnerRestingHR = 0` → `HRZoneHelper` falls back to simple %maxHR. No crash.
- [ ] **Backward compat**: Old Watch app build (before this change) receives the new WCSession message — extra key `partnerRestingHR` is ignored silently. No crash.
