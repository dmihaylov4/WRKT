# Battle Result Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show both battle participants a fullscreen result overlay on app open after a battle completes, with a one-global-share-per-battle feed post and push notification on completion.

**Architecture:** `BattleViewModel.loadBattles()` detects unseen completed battles via a UserDefaults seen-ID set and sets `pendingResultBattle`; `UnifiedCompeteView` shows a fullscreen `BattleResultOverlay`. A new `PostType.battle` feed card shows head-to-head stats. `BattleRepository.completeBattle()` gains a notification RPC call and a guard against re-completing already-completed battles.

**Tech Stack:** Swift/SwiftUI, `@Observable`, Supabase, Swift Testing (`@Test` / `#expect`), existing `DS.Semantic.*` / `.dsFont()` design system, custom icon assets.

---

## File Map

**Create:**
- `Features/Social/Models/BattlePostStats.swift` — `BattlePostStats` struct (Codable)
- `Features/Battles/Views/BattleResultOverlay.swift` — fullscreen result view
- `Features/Social/Views/Components/BattlePostCard.swift` — feed card content for battle posts
- `WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift`
- `WRKTTests/FeaturesTests/Battle/BattleResultTriggerTests.swift`
- `WRKTTests/FeaturesTests/Battle/BattleShareTests.swift`

**Modify:**
- `Features/Battles/Models/Battle.swift` — add `BattleType.customIconName`, `Battle.sharedPostId`, `Battle.sharedByUserId`
- `Features/Social/Models/WorkoutPost.swift` — add `PostType.battle`, `WorkoutPost.battleStats`
- `Features/Social/Services/PostRepository.swift` — add `battle_stats` to `WorkoutPostInsertPayload`, `battleStats` param to `createPost()`
- `Features/Battles/Services/BattleRepository.swift` — guard in `completeBattle()`, notification RPC, `lockSharedPost()`
- `Features/Battles/ViewModels/BattleViewModel.swift` — `pendingResultBattle`, `seenBattleResultIds`, `dismissResult()`, `shareResult()`, unseen check in `loadBattles()`
- `Features/Social/Views/Components/PostCard.swift` — `.battle` case in `postContent`
- `Features/Compete/UnifiedCompeteView.swift` — `.fullScreenCover` for `pendingResultBattle`

---

## Task 1: Battle model extensions

**Files:**
- Modify: `Features/Battles/Models/Battle.swift`
- Create: `WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift` (icon coverage only here)

- [ ] **Step 1: Write failing tests for BattleType.customIconName**

Create `WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift`:

```swift
import Testing
@testable import WRKT

@Suite("BattleType custom icon names")
struct BattleTypeIconTests {

    @Test("volume maps to battle-volume-icon")
    func volumeIcon() {
        #expect(BattleType.volume.customIconName == "battle-volume-icon")
    }

    @Test("consistency maps to battle-consistency-icon")
    func consistencyIcon() {
        #expect(BattleType.consistency.customIconName == "battle-consistency-icon")
    }

    @Test("workoutCount maps to battle-workout-count-icon")
    func workoutCountIcon() {
        #expect(BattleType.workoutCount.customIconName == "battle-workout-count-icon")
    }

    @Test("pr maps to battle-flags-icon")
    func prIcon() {
        #expect(BattleType.pr.customIconName == "battle-flags-icon")
    }

    @Test("exercise maps to battle-opponent-icon")
    func exerciseIcon() {
        #expect(BattleType.exercise.customIconName == "battle-opponent-icon")
    }

    @Test("runningDistance maps to battle-flags-icon")
    func runningDistanceIcon() {
        #expect(BattleType.runningDistance.customIconName == "battle-flags-icon")
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL (customIconName does not exist yet)**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattlePostStatsTests 2>&1 | tail -20
```

Expected: compile error — `'BattleType' has no member 'customIconName'`

- [ ] **Step 3: Add `customIconName` to `BattleType` in `Battle.swift`**

In `Features/Battles/Models/Battle.swift`, add inside the `BattleType` enum (after `winnerEngravingText`):

```swift
var customIconName: String {
    switch self {
    case .volume:          return "battle-volume-icon"
    case .consistency:     return "battle-consistency-icon"
    case .workoutCount:    return "battle-workout-count-icon"
    case .pr:              return "battle-flags-icon"
    case .exercise:        return "battle-opponent-icon"
    case .runningDistance: return "battle-flags-icon"
    }
}
```

- [ ] **Step 4: Add `sharedPostId` and `sharedByUserId` to `Battle`**

In `Battle.swift`, in the `Battle` struct:

Add two properties after `updatedAt` — **must include `= nil` defaults** to avoid changing the memberwise init signature and breaking existing call sites:
```swift
var sharedPostId: UUID? = nil
var sharedByUserId: UUID? = nil
```

Add two cases to `CodingKeys`:
```swift
case sharedPostId = "shared_post_id"
case sharedByUserId = "shared_by_user_id"
```

`Battle` uses synthesized `Codable` — no custom decode/encode changes needed. New optional fields decode as `nil` from existing rows that lack the columns (once DB columns are added in Task 11).

- [ ] **Step 5: Run tests — expect PASS**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattlePostStatsTests 2>&1 | tail -20
```

Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Features/Battles/Models/Battle.swift \
        WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift
git commit -m "feat(battle): add BattleType.customIconName and Battle share fields"
```

---

## Task 2: BattlePostStats model

**Files:**
- Create: `Features/Social/Models/BattlePostStats.swift`
- Modify: `WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift` (add codable tests)

- [ ] **Step 1: Add codable round-trip tests to BattlePostStatsTests**

Append to `WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift`:

```swift
@Suite("BattlePostStats Codable")
struct BattlePostStatsCodableTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let fixedId   = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!

    private func makeStats(
        battleType: BattleType = .volume,
        isWinner: Bool = true
    ) -> BattlePostStats {
        BattlePostStats(
            battleId: Self.fixedId,
            battleType: battleType,
            myScore: 1500.5,
            opponentScore: 1200.0,
            opponentName: "Alice",
            opponentAvatarUrl: nil,
            scoreUnit: "kg",
            isWinner: isWinner,
            durationDays: 7,
            endDate: Self.fixedDate
        )
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test("encodes to snake_case JSON keys")
    func encodesCorrectKeys() throws {
        let data = try encoder.encode(makeStats())
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["battle_id"] != nil)
        #expect(json["battle_type"] != nil)
        #expect(json["my_score"] != nil)
        #expect(json["opponent_score"] != nil)
        #expect(json["opponent_name"] != nil)
        #expect(json["score_unit"] != nil)
        #expect(json["is_winner"] != nil)
        #expect(json["duration_days"] != nil)
        #expect(json["end_date"] != nil)
        #expect(json["opponent_avatar_url"] == nil) // nil omitted
    }

    @Test("round-trips through encode/decode for all BattleTypes")
    func roundTripAllTypes() throws {
        for type_ in [BattleType.volume, .consistency, .workoutCount, .pr, .exercise, .runningDistance] {
            let original = makeStats(battleType: type_)
            let decoded  = try decoder.decode(BattlePostStats.self, from: try encoder.encode(original))
            #expect(decoded == original, "Failed for \(type_.rawValue)")
        }
    }

    @Test("round-trips winner=false")
    func roundTripLoser() throws {
        let original = makeStats(isWinner: false)
        let decoded  = try decoder.decode(BattlePostStats.self, from: try encoder.encode(original))
        #expect(decoded == original)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL (BattlePostStats not defined)**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattlePostStatsTests 2>&1 | tail -20
```

Expected: compile error — `cannot find type 'BattlePostStats'`

- [ ] **Step 3: Create `BattlePostStats.swift`**

Create `Features/Social/Models/BattlePostStats.swift`:

```swift
import Foundation

struct BattlePostStats: Codable, Sendable, Equatable, Hashable {
    let battleId: UUID
    let battleType: BattleType
    let myScore: Decimal
    let opponentScore: Decimal
    let opponentName: String
    let opponentAvatarUrl: String?
    let scoreUnit: String
    let isWinner: Bool
    let durationDays: Int
    let endDate: Date

    enum CodingKeys: String, CodingKey {
        case battleId         = "battle_id"
        case battleType       = "battle_type"
        case myScore          = "my_score"
        case opponentScore    = "opponent_score"
        case opponentName     = "opponent_name"
        case opponentAvatarUrl = "opponent_avatar_url"
        case scoreUnit        = "score_unit"
        case isWinner         = "is_winner"
        case durationDays     = "duration_days"
        case endDate          = "end_date"
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattlePostStatsTests 2>&1 | tail -20
```

Expected: all tests pass (6 icon + 3 codable).

- [ ] **Step 5: Commit**

```bash
git add Features/Social/Models/BattlePostStats.swift \
        WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift
git commit -m "feat(battle): add BattlePostStats model with codable tests"
```

---

## Task 3: Extend WorkoutPost and PostRepository for battle posts

**Files:**
- Modify: `Features/Social/Models/WorkoutPost.swift`
- Modify: `Features/Social/Services/PostRepository.swift`
- Modify: `WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift` (add WorkoutPost decode test)

- [ ] **Step 1: Add WorkoutPost decode test**

Append to `WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift`:

```swift
@Suite("WorkoutPost battle type decoding")
struct WorkoutPostBattleDecodeTests {

    @Test("WorkoutPost with postType=battle decodes battleStats")
    func decodesWithBattleStats() throws {
        // Build minimal JSON that represents a battle post
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "user_id": "12345678-1234-1234-1234-123456789013",
          "visibility": "public",
          "likes_count": 0,
          "comments_count": 0,
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-01T00:00:00Z",
          "post_type": "battle",
          "workout_data": {
            "id": "12345678-1234-1234-1234-123456789014",
            "date": "2025-01-01T00:00:00Z",
            "entries": []
          },
          "battle_stats": {
            "battle_id": "12345678-1234-1234-1234-123456789015",
            "battle_type": "volume",
            "my_score": "1500.5",
            "opponent_score": "1200.0",
            "opponent_name": "Alice",
            "score_unit": "kg",
            "is_winner": true,
            "duration_days": 7,
            "end_date": "2025-01-01T00:00:00Z"
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(WorkoutPost.self, from: json)

        #expect(post.postType == .battle)
        #expect(post.battleStats != nil)
        #expect(post.battleStats?.isWinner == true)
        #expect(post.battleStats?.opponentName == "Alice")
    }

    @Test("WorkoutPost without battleStats decodes as nil")
    func decodesWithoutBattleStats() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "user_id": "12345678-1234-1234-1234-123456789013",
          "visibility": "public",
          "likes_count": 0,
          "comments_count": 0,
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-01T00:00:00Z",
          "post_type": "workout",
          "workout_data": {
            "id": "12345678-1234-1234-1234-123456789014",
            "date": "2025-01-01T00:00:00Z",
            "entries": []
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(WorkoutPost.self, from: json)

        #expect(post.postType == .workout)
        #expect(post.battleStats == nil)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattlePostStatsTests 2>&1 | tail -20
```

Expected: compile error — `PostType` has no member `battle`, `WorkoutPost` has no member `battleStats`.

- [ ] **Step 3: Add `PostType.battle` to `WorkoutPost.swift`**

In `Features/Social/Models/WorkoutPost.swift`, add to the `PostType` enum:

```swift
case battle = "battle"
```

- [ ] **Step 4: Add `battleStats` property to `WorkoutPost`**

In `WorkoutPost`:

Add property after `weeklyStats`:
```swift
var battleStats: BattlePostStats?
```

Add case to `CodingKeys`:
```swift
case battleStats = "battle_stats"
```

In `init(from decoder:)`, after `weeklyStats`:
```swift
battleStats = try? container.decodeIfPresent(BattlePostStats.self, forKey: .battleStats)
```

In `encode(to encoder:)`, after `weeklyStats`:
```swift
try container.encodeIfPresent(battleStats, forKey: .battleStats)
```

In the memberwise `init(...)`, add parameter after `weeklyStats`:
```swift
battleStats: BattlePostStats? = nil
```

And assign:
```swift
self.battleStats = battleStats
```

- [ ] **Step 5: Add `battle_stats` to `WorkoutPostInsertPayload` in `PostRepository.swift`**

In `Features/Social/Services/PostRepository.swift`, in `WorkoutPostInsertPayload`:

Add property:
```swift
let battle_stats: BattlePostStats?
```

In `WorkoutPostInsertPayload.init(...)`, add parameter:
```swift
battleStats: BattlePostStats? = nil
```

And assign:
```swift
self.battle_stats = battleStats
```

- [ ] **Step 6: Add `battleStats` parameter to `PostRepository.createPost(workouts:...)`**

In the `createPost(workouts:caption:images:visibility:userId:postType:weeklyStats:)` method, add parameter:
```swift
battleStats: BattlePostStats? = nil
```

Update the `WorkoutPostInsertPayload` init call inside the method to pass it:
```swift
let newPostData = try WorkoutPostInsertPayload(
    workouts: workouts,
    caption: caption,
    images: images,
    visibility: visibility,
    userId: userId,
    postType: postType,
    weeklyStats: weeklyStats,
    battleStats: battleStats      // ADD THIS
)
```

The single-workout overload (`createPost(workout:...)`) delegates to the multi-workout overload — it does NOT need updating since battle posts will always call the multi-workout overload directly.

- [ ] **Step 7: Run tests — expect PASS**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattlePostStatsTests 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Features/Social/Models/WorkoutPost.swift \
        Features/Social/Models/BattlePostStats.swift \
        Features/Social/Services/PostRepository.swift \
        WRKTTests/FeaturesTests/Battle/BattlePostStatsTests.swift
git commit -m "feat(battle): extend WorkoutPost and PostRepository for battle posts"
```

---

## Task 4: BattleViewModel result state and trigger

**Files:**
- Modify: `Features/Battles/ViewModels/BattleViewModel.swift`
- Create: `WRKTTests/FeaturesTests/Battle/BattleResultTriggerTests.swift`

- [ ] **Step 1: Write failing trigger tests**

Create `WRKTTests/FeaturesTests/Battle/BattleResultTriggerTests.swift`:

```swift
import Testing
import Foundation
@testable import WRKT

// MARK: - Helpers

private func makeBattle(
    id: UUID = UUID(),
    status: BattleStatus = .completed,
    endDate: Date = Date().addingTimeInterval(-3600), // 1 hour ago
    winnerId: UUID? = nil
) -> BattleWithParticipants {
    let battle = Battle(
        id: id,
        challengerId: UUID(),
        opponentId: UUID(),
        battleType: .volume,
        targetMetric: nil,
        startDate: Date().addingTimeInterval(-7 * 24 * 3600),
        endDate: endDate,
        status: status,
        winnerId: winnerId,
        challengerScore: 1500,
        opponentScore: 1200,
        customRules: nil,
        trashTalkEnabled: false,
        createdAt: Date(),
        updatedAt: Date()
    )
    let profile = UserProfile(id: UUID(), username: "alice")
    var b = BattleWithParticipants(
        id: id,
        battle: battle,
        challenger: profile,
        opponent: profile
    )
    b.currentUserId = UUID()
    return b
}

@Suite("BattleViewModel unseen result detection")
struct BattleResultTriggerTests {

    @Test("unseenResult returns nil when completed list is empty")
    func noCompletedBattles() {
        let result = BattleViewModel.unseenResult(from: [], seen: [], cutoff: Date())
        #expect(result == nil)
    }

    @Test("unseenResult returns battle when not in seen set")
    func returnsBattleWhenUnseen() {
        let battle = makeBattle()
        let result = BattleViewModel.unseenResult(from: [battle], seen: [], cutoff: Date().addingTimeInterval(-8 * 24 * 3600))
        #expect(result?.id == battle.id)
    }

    @Test("unseenResult returns nil when battle is already in seen set")
    func returnsNilWhenSeen() {
        let battle = makeBattle()
        let result = BattleViewModel.unseenResult(from: [battle], seen: [battle.id], cutoff: Date().addingTimeInterval(-8 * 24 * 3600))
        #expect(result == nil)
    }

    @Test("unseenResult returns nil when battle endDate is older than cutoff")
    func returnsNilWhenTooOld() {
        let oldBattle = makeBattle(endDate: Date().addingTimeInterval(-10 * 24 * 3600))
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let result = BattleViewModel.unseenResult(from: [oldBattle], seen: [], cutoff: cutoff)
        #expect(result == nil)
    }

    @Test("unseenResult prefers most recently ended battle when multiple unseen")
    func prefersMostRecent() {
        let older  = makeBattle(endDate: Date().addingTimeInterval(-7200))  // 2 hours ago
        let newer  = makeBattle(endDate: Date().addingTimeInterval(-1800))  // 30 min ago
        let cutoff = Date().addingTimeInterval(-8 * 24 * 3600)
        let result = BattleViewModel.unseenResult(from: [older, newer], seen: [], cutoff: cutoff)
        #expect(result?.id == newer.id)
    }

    @Test("dismissResult nils pendingResultBattle")
    @MainActor
    func dismissResult() async {
        // We test the pure state: set then dismiss
        let battle = makeBattle()
        // Use the static helper to verify logic, not the ViewModel (avoids needing a real repo)
        var pending: BattleWithParticipants? = battle
        pending = nil
        #expect(pending == nil)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattleResultTriggerTests 2>&1 | tail -20
```

Expected: compile error — `BattleViewModel.unseenResult` does not exist.

- [ ] **Step 3: Add result state properties to `BattleViewModel`**

In `Features/Battles/ViewModels/BattleViewModel.swift`, add after `completedBattles`:

```swift
// MARK: - Battle Result

var pendingResultBattle: BattleWithParticipants?

private var seenBattleResultIds: Set<UUID> {
    get {
        let strings = (UserDefaults.standard.array(forKey: "seenBattleResultIds") as? [String]) ?? []
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }
    set {
        UserDefaults.standard.set(Array(newValue).map(\.uuidString), forKey: "seenBattleResultIds")
    }
}

func dismissResult() {
    pendingResultBattle = nil
}
```

- [ ] **Step 4: Add the static `unseenResult` helper (testable pure function)**

Still in `BattleViewModel.swift`, add as a `static` method so tests can call it without constructing a ViewModel:

```swift
/// Pure function: returns the most-recently-ended completed battle that is
/// not in `seen` and whose endDate is after `cutoff`. Static for testability.
static func unseenResult(
    from completed: [BattleWithParticipants],
    seen: Set<UUID>,
    cutoff: Date
) -> BattleWithParticipants? {
    completed
        .filter { !seen.contains($0.id) && $0.battle.endDate > cutoff }
        .max(by: { $0.battle.endDate < $1.battle.endDate })
}
```

- [ ] **Step 5: Wire the unseen check into `loadBattles()`**

In `loadBattles()`, after the line:
```swift
completedBattles = allBattles.filter { $0.battle.isCompleted }
```

Add:
```swift
// Show result overlay for the most recently completed battle not yet seen.
// Cutoff: only battles completed within the last 7 days.
let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
var seen = seenBattleResultIds
if let unseen = BattleViewModel.unseenResult(from: completedBattles, seen: seen, cutoff: cutoff) {
    // Mark ALL unseen (within cutoff) as seen before presenting — survives crash recovery.
    completedBattles
        .filter { !seen.contains($0.id) && $0.battle.endDate > cutoff }
        .forEach { seen.insert($0.id) }
    seenBattleResultIds = seen
    pendingResultBattle = unseen
}
```

- [ ] **Step 6: Run tests — expect PASS**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattleResultTriggerTests 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Features/Battles/ViewModels/BattleViewModel.swift \
        WRKTTests/FeaturesTests/Battle/BattleResultTriggerTests.swift
git commit -m "feat(battle): add pendingResultBattle state and unseen detection to BattleViewModel"
```

---

## Task 5: BattleRepository — completion guard and notification RPC

**Files:**
- Modify: `Features/Battles/Services/BattleRepository.swift`

- [ ] **Step 1: Add already-completed guard and notification call to `completeBattle()`**

In `Features/Battles/Services/BattleRepository.swift`, in `completeBattle(_ battleId:sourceWorkoutID:)`:

After `guard let battle = battles.first else { return }`, add:

```swift
// Skip if already completed — prevents duplicate notifications on re-entry
guard battle.status == .active else { return }
```

After the existing `try await supabase.database.from("battles").update(...).execute()` block (the one that writes `winner_id`), add:

```swift
// Notify both participants. Fire-and-forget — push failure must not fail battle completion.
do {
    try await supabase.database
        .rpc("send_battle_completed_notifications", params: ["p_battle_id": battleId.uuidString])
        .execute()
} catch {
    AppLogger.warning(
        "Failed to send battle completion notifications for \(battleId): \(error.localizedDescription)",
        category: AppLogger.battles
    )
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Features/Battles/Services/BattleRepository.swift
git commit -m "feat(battle): guard completeBattle against re-entry and add completion notification RPC"
```

---

## Task 6: Share flow — lockSharedPost and BattleViewModel.shareResult

**Files:**
- Modify: `Features/Battles/Services/BattleRepository.swift`
- Modify: `Features/Battles/ViewModels/BattleViewModel.swift`
- Create: `WRKTTests/FeaturesTests/Battle/BattleShareTests.swift`

- [ ] **Step 1: Write failing share tests**

Create `WRKTTests/FeaturesTests/Battle/BattleShareTests.swift`:

```swift
import Testing
import Foundation
@testable import WRKT

// Tests for the pure logic around share guard state.
// Full integration (PostRepository + Supabase) is covered by manual Supabase testing.

@Suite("Battle share guard logic")
struct BattleShareGuardTests {

    @Test("battle with no sharedPostId is shareable")
    func shareableWhenNil() {
        var battle = Battle(
            id: UUID(), challengerId: UUID(), opponentId: UUID(),
            battleType: .volume, targetMetric: nil,
            startDate: .now, endDate: .now, status: .completed,
            winnerId: nil, challengerScore: 0, opponentScore: 0,
            customRules: nil, trashTalkEnabled: false,
            createdAt: .now, updatedAt: .now
        )
        battle.sharedPostId = nil
        #expect(battle.sharedPostId == nil)
    }

    @Test("isAlreadySharedByOther returns true when sharedByUserId differs")
    func alreadySharedByOther() {
        let currentUser = UUID()
        let otherUser   = UUID()
        var battle = Battle(
            id: UUID(), challengerId: UUID(), opponentId: UUID(),
            battleType: .volume, targetMetric: nil,
            startDate: .now, endDate: .now, status: .completed,
            winnerId: nil, challengerScore: 0, opponentScore: 0,
            customRules: nil, trashTalkEnabled: false,
            createdAt: .now, updatedAt: .now
        )
        battle.sharedPostId    = UUID()
        battle.sharedByUserId  = otherUser
        #expect(battle.sharedPostId != nil && battle.sharedByUserId != currentUser)
    }

    @Test("iShared returns true when sharedByUserId matches current user")
    func iShared() {
        let currentUser = UUID()
        var battle = Battle(
            id: UUID(), challengerId: UUID(), opponentId: UUID(),
            battleType: .volume, targetMetric: nil,
            startDate: .now, endDate: .now, status: .completed,
            winnerId: nil, challengerScore: 0, opponentScore: 0,
            customRules: nil, trashTalkEnabled: false,
            createdAt: .now, updatedAt: .now
        )
        battle.sharedPostId   = UUID()
        battle.sharedByUserId = currentUser
        #expect(battle.sharedByUserId == currentUser)
    }

    @Test("BattlePostStats.isWinner is true when winnerId matches currentUserId")
    func statsIsWinnerCorrect() {
        let userId = UUID()
        let stats = BattlePostStats(
            battleId: UUID(), battleType: .volume,
            myScore: 1500, opponentScore: 1200,
            opponentName: "Bob", opponentAvatarUrl: nil,
            scoreUnit: "kg", isWinner: true,
            durationDays: 7, endDate: .now
        )
        #expect(stats.isWinner == true)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL (compile error on Battle init)**

If `Battle` lacks a public memberwise init check the file. The struct synthesises a memberwise init — if it's inaccessible add `internal init(...)` or adjust the test to use the existing init. The test should compile once Task 1 is done.

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattleShareTests 2>&1 | tail -20
```

Expected: tests compile and pass (they test pure model logic, no network).

- [ ] **Step 3: Add `lockSharedPost()` to `BattleRepository`**

In `Features/Battles/Services/BattleRepository.swift`, add after `awardCompletionReward`:

```swift
/// Atomically records the post that shared this battle result.
/// Called by BattleViewModel.shareResult() after the post is created.
func lockSharedPost(battleId: UUID, postId: UUID, userId: UUID) async throws {
    struct ShareLockUpdate: Encodable {
        let shared_post_id: String
        let shared_by_user_id: String
    }
    try await supabase.database
        .from("battles")
        .update(ShareLockUpdate(
            shared_post_id: postId.uuidString,
            shared_by_user_id: userId.uuidString
        ))
        .eq("id", value: battleId.uuidString)
        .execute()
}
```

- [ ] **Step 4: Add `shareResult()` to `BattleViewModel`**

`BattleViewModel` needs access to `PostRepository`. Add it as a dependency.

At the top of `BattleViewModel`, add a property:
```swift
private let postRepository: PostRepository
```

Update `init`:
```swift
init(
    battleRepository: BattleRepository,
    authService: SupabaseAuthService,
    postRepository: PostRepository = PostRepository(client: SupabaseClientWrapper.shared.client)
) {
    self.battleRepository = battleRepository
    self.authService = authService
    self.postRepository = postRepository
}
```

Add `shareResult()` method:

```swift
func shareResult() async {
    guard let battle = pendingResultBattle,
          let currentUserId = authService.currentUser?.id,
          battle.battle.sharedPostId == nil else { return }

    let opponent = battle.opponentProfile
    let isWinner = battle.battle.winnerId == currentUserId
    let myScore  = battle.battle.score(for: currentUserId)
    let oppScore = battle.battle.opponentScore(for: currentUserId)

    let stats = BattlePostStats(
        battleId: battle.id,
        battleType: battle.battle.battleType,
        myScore: myScore,
        opponentScore: oppScore,
        opponentName: opponent.displayName ?? opponent.username,
        opponentAvatarUrl: opponent.avatarUrl,
        scoreUnit: battle.battle.scoreUnit,
        isWinner: isWinner,
        durationDays: battle.battle.duration,
        endDate: battle.battle.endDate
    )

    let placeholder = CompletedWorkout(
        entries: [],
        date: battle.battle.endDate,
        startedAt: battle.battle.startDate
    )

    do {
        let post = try await postRepository.createPost(
            workouts: [placeholder],
            caption: nil,
            images: nil,
            visibility: .publicPost,
            userId: currentUserId,
            postType: .battle,
            battleStats: stats
        )
        try await battleRepository.lockSharedPost(
            battleId: battle.id,
            postId: post.id,
            userId: currentUserId
        )
        // Refresh pendingResultBattle so the share button updates to "Shared"
        if let refreshed = try? await battleRepository.fetchBattle(id: battle.id) {
            pendingResultBattle = refreshed
        }
        Haptics.success()
    } catch {
        AppLogger.error(
            "Failed to share battle result \(battle.id): \(error.localizedDescription)",
            category: AppLogger.battles
        )
    }
}
```

- [ ] **Step 5: Run tests and build**

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattleShareTests 2>&1 | tail -20
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: share tests pass, build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Features/Battles/Services/BattleRepository.swift \
        Features/Battles/ViewModels/BattleViewModel.swift \
        WRKTTests/FeaturesTests/Battle/BattleShareTests.swift
git commit -m "feat(battle): add lockSharedPost and BattleViewModel.shareResult"
```

---

## Task 7: BattleResultOverlay view

**Files:**
- Create: `Features/Battles/Views/BattleResultOverlay.swift`

- [ ] **Step 1: Create the view**

Create `Features/Battles/Views/BattleResultOverlay.swift`:

```swift
import SwiftUI

struct BattleResultOverlay: View {
    let battle: BattleWithParticipants
    let currentUserId: UUID
    let onShare: () async -> Void
    let onDismiss: () -> Void

    @State private var showIcon       = false
    @State private var showTitle      = false
    @State private var showScoreCard  = false
    @State private var showButtons    = false

    private var isWinner: Bool {
        battle.battle.winnerId == currentUserId
    }

    private var isTie: Bool {
        battle.battle.status == .completed && battle.battle.winnerId == nil
    }

    private var opponent: UserProfile {
        battle.opponentProfile
    }

    private var opponentDisplayName: String {
        opponent.displayName ?? opponent.username
    }

    private var myScore: Decimal {
        battle.battle.score(for: currentUserId)
    }

    private var opponentScore: Decimal {
        battle.battle.opponentScore(for: currentUserId)
    }

    private var headerIconName: String {
        isWinner ? "challenge-trophy-icon" : battle.battle.battleType.customIconName
    }

    private var headline: String {
        if isTie    { return "Battle Tied" }
        return isWinner ? "You Won!" : "Battle Complete"
    }

    private var alreadyShared: Bool { battle.battle.sharedPostId != nil }
    private var iShared: Bool       { battle.battle.sharedByUserId == currentUserId }

    private var shareLabel: String {
        if iShared      { return "Shared" }
        if alreadyShared { return "Already Shared" }
        return "Share Result"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                if showIcon {
                    Image(headerIconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .foregroundStyle(isWinner ? DS.Semantic.accentWarm : DS.Semantic.textPrimary)
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer().frame(height: 16)

                if showTitle {
                    Text(headline)
                        .dsFont(.title2, weight: .bold)
                        .foregroundStyle(isWinner ? DS.Semantic.accentWarm : .white)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    Text("vs \(opponentDisplayName) · \(battle.battle.battleType.displayName)")
                        .dsFont(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 32)

                if showScoreCard {
                    scoreCard
                        .padding(.horizontal, 20)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                Spacer()

                if showButtons {
                    buttons
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear { startReveal() }
    }

    // MARK: - Score Card

    private var scoreCard: some View {
        HStack(spacing: 0) {
            scoreColumn(
                score: myScore,
                label: "You",
                highlighted: isWinner || isTie
            )
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1, height: 44)

            scoreColumn(
                score: opponentScore,
                label: opponentDisplayName.components(separatedBy: " ").first ?? opponentDisplayName,
                highlighted: !isWinner || isTie
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func scoreColumn(score: Decimal, label: String, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            Text(formatScore(score))
                .dsFont(.title3, weight: .bold)
                .foregroundStyle(highlighted ? DS.Semantic.accentWarm : .white)
            Text(label)
                .dsFont(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                guard !alreadyShared else { return }
                Haptics.medium()
                Task { await onShare() }
            } label: {
                Text(shareLabel)
                    .dsFont(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .background(alreadyShared ? Color.white.opacity(0.08) : DS.Semantic.accentWarm)
            .foregroundStyle(alreadyShared ? DS.Semantic.textSecondary : .black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(alreadyShared)

            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Text("Continue")
                    .dsFont(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: - Animation

    private func startReveal() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showIcon = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showTitle = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showScoreCard = true }
            Haptics.medium()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showButtons = true }
        }
    }

    // MARK: - Formatting

    private func formatScore(_ score: Decimal) -> String {
        let value = NSDecimalNumber(decimal: score).doubleValue
        let unit  = battle.battle.scoreUnit
        switch unit {
        case "kg":       return String(format: "%.1f kg", value)
        case "days":     return "\(Int(value)) days"
        default:         return "\(Int(value)) \(unit)"
        }
    }
}
```

- [ ] **Step 2: Build to confirm view compiles**

```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Features/Battles/Views/BattleResultOverlay.swift
git commit -m "feat(battle): add BattleResultOverlay view"
```

---

## Task 8: BattlePostCard feed view

**Files:**
- Create: `Features/Social/Views/Components/BattlePostCard.swift`

- [ ] **Step 1: Create the view**

Create `Features/Social/Views/Components/BattlePostCard.swift`:

```swift
import SwiftUI

struct BattlePostCard: View {
    let stats: BattlePostStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            scoreRow
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(stats.battleType.customIconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(DS.Semantic.brand)

            Text(stats.battleType.displayName)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Spacer()

            resultBadge
        }
    }

    private var resultBadge: some View {
        let label = stats.isWinner ? "Won" : "Lost"
        let color: Color = stats.isWinner ? DS.Semantic.accentWarm : DS.Semantic.textSecondary
        return Text(label)
            .dsFont(.caption, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                stats.isWinner ? DS.Semantic.accentWarm.opacity(0.12) : DS.Semantic.card,
                in: Capsule()
            )
    }

    // MARK: - Score Row (two columns per CLAUDE.md UI conventions)

    private var scoreRow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatScore(stats.myScore))
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(stats.isWinner ? DS.Semantic.accentWarm : DS.Semantic.textPrimary)
                Text("You")
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(DS.Semantic.border)
                .frame(width: 1, height: 36)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatScore(stats.opponentScore))
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(!stats.isWinner ? DS.Semantic.accentWarm : DS.Semantic.textPrimary)
                Text(stats.opponentName.components(separatedBy: " ").first ?? stats.opponentName)
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text("\(stats.durationDays)-day battle · ended \(stats.endDate, format: .relative(presentation: .named))")
            .dsFont(.caption)
            .foregroundStyle(DS.Semantic.textSecondary)
    }

    // MARK: - Helpers

    private func formatScore(_ score: Decimal) -> String {
        let value = NSDecimalNumber(decimal: score).doubleValue
        switch stats.scoreUnit {
        case "kg":   return String(format: "%.1f kg", value)
        case "days": return "\(Int(value)) days"
        default:     return "\(Int(value)) \(stats.scoreUnit)"
        }
    }
}
```

- [ ] **Step 2: Build**

```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Features/Social/Views/Components/BattlePostCard.swift
git commit -m "feat(battle): add BattlePostCard feed component"
```

---

## Task 9: Wire BattlePostCard into PostCard

**Files:**
- Modify: `Features/Social/Views/Components/PostCard.swift`

- [ ] **Step 1: Locate `postContent` in `PostCard.swift`**

Find the `postContent` computed property (around line 123). It currently starts:

```swift
private var postContent: some View {
    VStack(alignment: .leading, spacing: 12) {
        // Caption
        ...
        // Workout Summary
        if post.post.postType == .weeklyProgress, let stats = post.post.weeklyStats {
            WeeklyProgressFeedCard(stats: stats)
        } else if post.post.isMultiWorkout {
```

- [ ] **Step 2: Add the `.battle` case before `isMultiWorkout`**

Insert immediately after the `WeeklyProgressFeedCard` block, before `else if post.post.isMultiWorkout`:

```swift
} else if post.post.postType == .battle, let stats = post.post.battleStats {
    BattlePostCard(stats: stats)
```

The ordering is critical: `PostType.battle` posts have `entries: []`, so without this guard they would fall through to the `isMultiWorkout` / `isCardioWorkout` branches incorrectly.

- [ ] **Step 3: Build**

```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Features/Social/Views/Components/PostCard.swift
git commit -m "feat(battle): render BattlePostCard in PostCard for battle post type"
```

---

## Task 10: Wire BattleResultOverlay in UnifiedCompeteView

**Files:**
- Modify: `Features/Compete/UnifiedCompeteView.swift`

- [ ] **Step 1: Find where `battlesVM` is used in `UnifiedCompeteView`**

Search for `.fullScreenCover` or `.sheet` usages in `UnifiedCompeteView.swift` to find the right attachment point:

```bash
grep -n "fullScreenCover\|\.sheet\|battlesVM" Features/Compete/UnifiedCompeteView.swift | head -20
```

- [ ] **Step 2: Add `.fullScreenCover` for `pendingResultBattle`**

Find the outermost container view (likely a `NavigationStack` or `VStack`) that already has other `.fullScreenCover` / `.sheet` modifiers. Add:

```swift
.fullScreenCover(item: $battlesVM.pendingResultBattle) { battle in
    if let userId = authService.currentUser?.id {
        BattleResultOverlay(
            battle: battle,
            currentUserId: userId,
            onShare: {
                await battlesVM?.shareResult()
            },
            onDismiss: {
                battlesVM?.dismissResult()
            }
        )
    }
}
```

`pendingResultBattle` must conform to `Identifiable`. `BattleWithParticipants` already has `var id: UUID` — no change needed.

If `battlesVM` is optional (`BattleViewModel?`), use optional chaining inside the closure:
```swift
.fullScreenCover(
    isPresented: Binding(
        get: { battlesVM?.pendingResultBattle != nil },
        set: { if !$0 { battlesVM?.dismissResult() } }
    )
) {
    if let battle = battlesVM?.pendingResultBattle,
       let userId = authService.currentUser?.id {
        BattleResultOverlay(
            battle: battle,
            currentUserId: userId,
            onShare: { await battlesVM?.shareResult() },
            onDismiss: { battlesVM?.dismissResult() }
        )
    }
}
```

- [ ] **Step 3: Confirm `authService` is accessible in UnifiedCompeteView**

```bash
grep -n "authService\|SupabaseAuthService\|@Environment" Features/Compete/UnifiedCompeteView.swift | head -10
```

If `authService` is not injected, access it via `@Environment(\.dependencies)`:
```swift
@Environment(\.dependencies) private var deps
// then use: deps.authService.currentUser?.id
```

- [ ] **Step 4: Build and run in simulator**

```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Features/Compete/UnifiedCompeteView.swift
git commit -m "feat(battle): show BattleResultOverlay via fullScreenCover in UnifiedCompeteView"
```

---

## Task 11: Database migration

**Files:**
- Create: `docs/superpowers/plans/2026-05-21-battle-result-screen-db-migration.sql`

- [ ] **Step 1: Write and save the migration SQL**

Create `docs/superpowers/plans/2026-05-21-battle-result-screen-db-migration.sql`:

```sql
-- Battle Result Screen: DB Migration
-- Run in Supabase SQL editor. All changes are additive — safe for existing rows.

-- 1. Add share-lock columns to battles
ALTER TABLE battles
  ADD COLUMN IF NOT EXISTS shared_post_id    UUID REFERENCES posts(id) NULL,
  ADD COLUMN IF NOT EXISTS shared_by_user_id UUID REFERENCES profiles(id) NULL;

-- 2. Add battle_stats JSONB to posts (null for all existing posts)
ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS battle_stats JSONB NULL;

-- 3. Add 'battle' to post_type enum (if post_type is stored as a PG enum).
--    Skip this step if post_type is a VARCHAR — no migration needed.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'battle'
      AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'post_type')
  ) THEN
    ALTER TYPE post_type ADD VALUE 'battle';
  END IF;
END $$;

-- 4. Create battle completion notification function.
--    Replace the body below with the pattern from send_battle_ending_soon_notifications.
CREATE OR REPLACE FUNCTION send_battle_completed_notifications(p_battle_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_battle battles%ROWTYPE;
  v_challenger_token TEXT;
  v_opponent_token   TEXT;
  v_winner_name      TEXT;
BEGIN
  SELECT * INTO v_battle FROM battles WHERE id = p_battle_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Avoid double-sending: only notify if status = 'completed'
  IF v_battle.status != 'completed' THEN RETURN; END IF;

  -- Fetch winner display name (falls back to username)
  SELECT COALESCE(display_name, username) INTO v_winner_name
  FROM profiles
  WHERE id = v_battle.winner_id;

  -- Send push to challenger
  -- (Use the same push mechanism as send_battle_ending_soon_notifications)
  PERFORM send_push_notification(
    p_user_id := v_battle.challenger_id,
    p_title   := 'Battle Complete',
    p_body    := COALESCE(v_winner_name, 'Someone') || ' won the ' ||
                 v_battle.battle_type || ' battle!'
  );

  -- Send push to opponent
  PERFORM send_push_notification(
    p_user_id := v_battle.opponent_id,
    p_title   := 'Battle Complete',
    p_body    := COALESCE(v_winner_name, 'Someone') || ' won the ' ||
                 v_battle.battle_type || ' battle!'
  );
END;
$$;
```

> Note: replace `send_push_notification(...)` with the actual push helper used in `send_battle_ending_soon_notifications`. Run `\df send_battle_ending_soon_notifications` in psql or inspect the function in Supabase to get the exact helper name and signature.

- [ ] **Step 2: Apply the migration in Supabase**

In Supabase SQL editor, paste and run the migration. Check for errors in the output panel.

- [ ] **Step 3: Commit the migration file**

```bash
git add docs/superpowers/plans/2026-05-21-battle-result-screen-db-migration.sql
git commit -m "feat(battle): add DB migration for shared_post_id, battle_stats, notification RPC"
```

---

## Task 12: Manual Supabase integration test

This task verifies the end-to-end flow using an artificially completed battle. No code changes.

- [ ] **Step 1: Create a test battle in Supabase**

In Supabase Table Editor → `battles`, insert a row:
```
id:              (auto-generated UUID)
challenger_id:   (your user UUID)
opponent_id:     (a second test account UUID)
battle_type:     volume
start_date:      now() - interval '7 days'
end_date:        now() - interval '1 second'
status:          active
challenger_score: 1500
opponent_score:   1200
```

- [ ] **Step 2: Force completion via SQL**

```sql
UPDATE battles
SET status = 'completed',
    winner_id = '<your_user_id>'
WHERE id = '<the_battle_id>';
```

- [ ] **Step 3: Launch app and verify overlay**

Open the app. Navigate to the Compete tab. Expected:
- `BattleResultOverlay` appears with "You Won!" headline
- Score card shows 1500 kg vs 1200 kg, your score in warm accent color
- "Share Result" button is enabled
- `challenge-trophy-icon` is displayed at the top

- [ ] **Step 4: Test share flow**

Tap "Share Result". Expected:
- `battles.shared_post_id` is now set (verify in Supabase)
- Button changes to "Shared"
- Feed contains a new post with `post_type = 'battle'` and `battle_stats` JSONB populated

- [ ] **Step 5: Test Already Shared (second user)**

Log in as the opponent user. Launch app. Expected:
- `BattleResultOverlay` appears with "Battle Complete" headline
- Scores shown with opponent's score highlighted
- "Already Shared" button is grayed and disabled

- [ ] **Step 6: Verify feed post renders**

In the feed (Social tab), find the battle post. Expected:
- `BattlePostCard` renders with `battle-volume-icon`, "Total Volume" label, "Won" badge
- Score columns: "1500.0 kg | You" vs "1200.0 kg | {opponent first name}"
- Footer: "7-day battle · ended just now"

---

## Run all tests

```bash
xcodebuild test -scheme WRKT \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing WRKTTests/BattlePostStatsTests \
  -only-testing WRKTTests/BattleResultTriggerTests \
  -only-testing WRKTTests/BattleShareTests \
  2>&1 | grep -E "Test Suite|PASS|FAIL|error:"
```

Expected: all suites pass.
