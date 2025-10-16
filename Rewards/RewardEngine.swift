// WRKT/Features/Rewards/RewardsEngine.swift
import Foundation
import SwiftData
import Combine

// MARK: - Public signal for toasts/banners
extension Notification.Name {
    /// Posted with `object` = Int (delta XP just granted)
    static let rewardDidGrant = Notification.Name("rewardDidGrant")
}



extension RewardsEngine {
    func ensureDexUnlocked(exerciseKey: String, date: Date = .now) {
        ensureSingletons()
        let fd = FetchDescriptor<DexStamp>(predicate: #Predicate<DexStamp> { $0.key == exerciseKey })
        let existing = (try? context.fetch(fd)) ?? []
        guard existing.isEmpty else { return }

        context.insert(DexStamp(key: exerciseKey, unlockedAt: date))
        do { try context.save() } catch { print("⚠️ Dex save failed: \(error)") }
    }

    private func backfillDexStampsIfNeeded() {
        let flag = "dex.backfill.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }

        // Pull historical PR rows
        let prs = (try? context.fetch(FetchDescriptor<ExercisePR>())) ?? []

        for pr in prs {
            // ⚠️ IMPORTANT: use your String field, not pr.id (PersistentIdentifier)
            // If your model is `@Model class ExercisePR { var exerciseId: String }`
            // then do:
            let exerciseKey = canonicalExerciseKey(from: pr.exerciseId) // or pr.name

            // Explicit predicate type to avoid inference errors
            let fd = FetchDescriptor<DexStamp>(
                predicate: #Predicate<DexStamp> { $0.key == exerciseKey }
            )
            let existing = (try? context.fetch(fd)) ?? []
            if existing.isEmpty {
                context.insert(DexStamp(key: exerciseKey, unlockedAt: pr.updatedAt))
            }
        }

        UserDefaults.standard.set(true, forKey: flag)
    }
}

// MARK: - RewardsEngine

@MainActor
final class RewardsEngine: ObservableObject {
    static let shared = RewardsEngine()
    private var isConfigured = false

    private var rules: RewardsRules = .empty

    // Exposed so the app shell can inject after container is ready.
    var context: ModelContext!

    // Cached singletons (created on demand if missing)
    var progress: RewardProgress?
    var wallet: Wallet?
    
    

    // Configure once from the app shell after ModelContainer is ready
    func configure(context: ModelContext) {
        guard !isConfigured else { return }
        self.context = context
        self.rules = RewardsRulesLoader.load(bundleFile: "rewards_rules_v1")
        ensureSingletons()
        backfillDexStampsIfNeeded()   // ← add back
        isConfigured = true
    }
    
    
}

// MARK: - Diagnostics

extension RewardsEngine {
    func debugRulesSummary() -> String {
        "v\(rules.version) xp=\(rules.xp.count) ach=\(rules.achievements.count)"
    }
}

// MARK: - Singletons

extension RewardsEngine {
    /// Ensure `RewardProgress` and `Wallet` exist; create if needed.
    func ensureSingletons() {
        // RewardProgress (id="global")
        if progress == nil {
            let fd = FetchDescriptor<RewardProgress>(predicate: #Predicate { $0.id == "global" })
            if let existing = try? context.fetch(fd).first {
                progress = existing
            } else {
                let created = RewardProgress()
                context.insert(created)
                progress = created
            }
        }

        // Wallet (id="wallet")
        if wallet == nil {
            let fd = FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == "wallet" })
            if let existing = try? context.fetch(fd).first {
                wallet = existing
            } else {
                let created = Wallet()
                context.insert(created)
                wallet = created
            }
        }
    }
}

// MARK: - Activity classification

extension RewardsEngine {
    /// Which events count as "activity" for streaks.
    func countsAsActivity(event: String) -> Bool {
        switch event {
        case "workout_completed", "set_logged", "warmup_completed", "mobility_completed", "pr_achieved":
            return true
        default:
            return false
        }
    }
}

// MARK: - XP rules

extension RewardsEngine {
    struct XPAward { let delta: Int; let ledger: [RewardLedgerEntry] }

    func applyXPRules(event name: String, payload: [String:Any]) -> XPAward {
        guard let rule = rules.xp[name] else { return .init(delta: 0, ledger: []) }

        var grant = rule.amount

        // Per-day maximum for this event type
        if let maxPerDay = rule.max_per_day {
            let awardedToday = xpAwardedToday(forEvent: name)
            let room = max(0, maxPerDay - awardedToday)
            grant = min(grant, room)
        }

        // Once per workout
        if rule.once_per_workout == true, let workoutId = payload["workoutId"] as? String {
            if hasEventRecordedToday(event: name, contains: #""workoutId":"\#(workoutId)""#) {
                grant = 0
            }
        }

        // Per-workout cap
        if let cap = rule.cap_per_workout, let workoutId = payload["workoutId"] as? String {
            let alreadyForWorkout = xpAwardedForWorkoutToday(event: name, workoutId: workoutId)
            let room = max(0, cap - alreadyForWorkout)
            grant = min(grant, room)
        }

        // Per-exercise daily (e.g., PRs)
        if let maxPerExerciseDaily = rule.max_per_exercise_daily,
           let exerciseId = payload["exerciseId"] as? String {
            let awarded = countEntriesToday(event: name, contains: #""exerciseId":"\#(exerciseId)""#)
            if awarded >= maxPerExerciseDaily { grant = 0 }
        }

        guard grant > 0 else { return .init(delta: 0, ledger: []) }

        let entry = RewardLedgerEntry(
            event: name,
            ruleId: name,                     // keep ruleId equal to event for XP rules
            deltaXP: grant,
            deltaCoins: 0,
            metadataJSON: encodeJSON(payload)
        )
        return .init(delta: grant, ledger: [entry])
    }
}

// MARK: - Achievements (static + dynamic PRs)

extension RewardsEngine {
    struct AchievementAward { let deltaXP: Int; let deltaCoins: Int; let ledger: [RewardLedgerEntry] }

    func applyAchievementRules(event name: String, payload: [String:Any]) -> AchievementAward {
        var totalXP = 0
        var totalCoins = 0
        var entries: [RewardLedgerEntry] = []

        // 1) Dynamic per-exercise PR achievement (always considered)
        if name == "pr_achieved",
           let exId = payload["exerciseId"] as? String,
           let exName = payload["exerciseName"] as? String {
            let achId = "ach.pr.\(exId)"
            let ach = fetchOrCreateAchievement(
                id: achId,
                title: "PR: \(exName)",
                desc: "Set a personal record in \(exName).",
                target: 1,
                tier: nil
            )
            if ach.unlockedAt == nil {
                ach.progress = 1
                ach.unlockedAt = .now
                entries.append(
                    RewardLedgerEntry(
                        event: "achievement_unlocked",
                        ruleId: achId,
                        deltaXP: 0, deltaCoins: 0,
                        metadataJSON: encodeJSON(["achievementId": achId])
                    )
                )
            }
        }

        // 2) Static JSON-driven achievements for this trigger
        let triggered = rules.achievements.filter { $0.trigger == name }
        for rule in triggered {
            // Fetch or create this achievement
            let ach = fetchOrCreateAchievement(
                id: rule.id, title: rule.title, desc: rule.desc,
                target: rule.threshold, tier: rule.tier
            )

            // Increment progress (prefer explicit "amount" from payload if present)
            if let inc = payload["amount"] as? Int {
                ach.progress += inc
            } else {
                ach.progress += 1
            }
            ach.lastUpdatedAt = .now

            // Unlock and reward if threshold reached
            if ach.unlockedAt == nil, ach.progress >= ach.target {
                ach.unlockedAt = .now
                let dxp = rule.reward.xp ?? 0
                let dcn = rule.reward.coins ?? 0
                totalXP += dxp
                totalCoins += dcn
                entries.append(
                    RewardLedgerEntry(
                        event: "achievement_unlocked",
                        ruleId: rule.id,
                        deltaXP: dxp,
                        deltaCoins: dcn,
                        metadataJSON: encodeJSON(["achievementId": rule.id])
                    )
                )
            }
        }

        return .init(deltaXP: totalXP, deltaCoins: totalCoins, ledger: entries)
    }

    func fetchOrCreateAchievement(id: String, title: String, desc: String, target: Int, tier: String?) -> Achievement {
        let fd = FetchDescriptor<Achievement>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(fd).first { return existing }
        let ach = Achievement(id: id, title: title, desc: desc, target: target)
        if let tier { ach.tier = AchievementTier(rawValue: tier) }
        context.insert(ach)
        return ach
    }
}

// MARK: - PR helpers and dynamic achievement entrypoint

extension RewardsEngine {
    /// Fetch a stored PR row for an exercise, if any.
    func fetchPR(for exerciseId: String) -> ExercisePR? {
        let fd = FetchDescriptor<ExercisePR>(predicate: #Predicate { $0.exerciseId == exerciseId })
        return try? context.fetch(fd).first
    }

    /// Create or update the PR row; returns whether the E1RM improved and the final PR row.
    @discardableResult
    func upsertPR(
        exerciseId: String,
        name: String,
        e1rm: Double,
        weightKg: Double,
        reps: Int
    ) -> (improved: Bool, pr: ExercisePR) {
        if let pr = fetchPR(for: exerciseId) {
            // Use E1RM as canonical PR; small tolerance to avoid noise
            if e1rm > pr.bestE1RM + 0.25 {
                pr.bestE1RM = e1rm
                pr.bestWeightKg = max(pr.bestWeightKg, weightKg)
                pr.bestReps = max(pr.bestReps, reps)
                pr.exerciseName = name
                pr.updatedAt = Date.now
                return (true, pr)
            } else {
                return (false, pr)
            }
        } else {
            let pr = ExercisePR(id: exerciseId, name: name, e1rm: e1rm, weightKg: weightKg, reps: reps)
            context.insert(pr)
            return (true, pr)
        }
    }

    /// Call this when a set may be a PR. It updates PRs, ensures a per-exercise achievement,
    /// then routes through your existing pipeline via `process(event:payload:)`.
    func recordPR(exerciseId: String, exerciseName: String, reps: Int, weightKg: Double) {
        ensureSingletons()

        // Epley formula (good 1–12 reps): E1RM ≈ w * (1 + reps/30)
        let e1rm = weightKg * (1.0 + Double(reps) / 30.0)

        let upd = upsertPR(
            exerciseId: exerciseId,
            name: exerciseName,
            e1rm: e1rm,
            weightKg: weightKg,
            reps: reps
        )
        guard upd.improved else { return } // not a new PR—bail

        // Ensure per-exercise PR achievement row exists & unlocked once
        let achId = "ach.pr.\(exerciseId)"
        let ach = fetchOrCreateAchievement(
            id: achId,
            title: "PR: \(exerciseName)",
            desc: "Set a personal record in \(exerciseName).",
            target: 1,
            tier: nil
        )
        if ach.unlockedAt == nil {
            ach.progress = 1
            ach.unlockedAt = .now
        }

        // Route via pipeline (awards XP per rules, streak, summary, etc.)
        process(
            event: "pr_achieved",
            payload: [
                "exerciseId": exerciseId,
                "exerciseName": exerciseName,
                "reps": reps,
                "weightKg": weightKg,
                "e1rm": e1rm,
                "count": 1
            ]
        )
    }
}

// MARK: - Wallet & Leveling

extension RewardsEngine {
    func applyWalletAndLevel(deltaXP: Int, deltaCoins: Int) {
        ensureSingletons()
        guard let prog = progress, let wal = wallet else { return }

        // Wallet
        if deltaCoins != 0 {
            wal.coins = max(0, wal.coins + deltaCoins)
        }

        // Level progression curve (gentle early, slower later).
        if deltaXP != 0 {
            prog.xp = max(0, prog.xp + deltaXP)
            let (lvl, nextXP) = levelCurve(for: prog.xp)
            let didLevelUp = (lvl > prog.level)
            prog.level = lvl
            prog.nextLevelXP = nextXP

            if didLevelUp {
                let entry = RewardLedgerEntry(
                    event: "level_up",
                    ruleId: "level_\(lvl)",
                    deltaXP: 0,
                    deltaCoins: 0,
                    metadataJSON: encodeJSON(["level": lvl, "xp": prog.xp])
                )
                context.insert(entry)
            }
        }
    }

    /// Example curve: level = floor(sqrt(xp / 150)) + 1; nextLevelXP = ((level+1)^2 - 1) * 150
    func levelCurve(for xp: Int) -> (level: Int, nextLevelXP: Int) {
        let denom: Double = 150.0
        let lvl = Int(floor(sqrt(Double(xp) / denom))) + 1
        let nextTarget = Int(((Double(lvl + 1) * Double(lvl + 1)) - 1.0) * denom)
        return (max(lvl, 1), nextTarget)
    }
}

// MARK: - Ledger/query helpers

extension RewardsEngine {
    func startOfDay(_ date: Date = .now) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    func endOfDay(_ date: Date = .now) -> Date {
        let sod = startOfDay(date)
        return Calendar.current.date(byAdding: .day, value: 1, to: sod)!
    }

    func xpAwardedToday(forEvent event: String) -> Int {
        let sod = startOfDay(); let eod = endOfDay()
        let fd = FetchDescriptor<RewardLedgerEntry>(
            predicate: #Predicate { $0.event == event && $0.occurredAt >= sod && $0.occurredAt < eod }
        )
        let items = (try? context.fetch(fd)) ?? []
        return items.reduce(0) { $0 + $1.deltaXP }
    }

    func countEntriesToday(event: String, contains token: String) -> Int {
        let sod = startOfDay(); let eod = endOfDay()
        let fd = FetchDescriptor<RewardLedgerEntry>(
            predicate: #Predicate {
                $0.event == event &&
                $0.occurredAt >= sod && $0.occurredAt < eod &&
                ($0.metadataJSON?.contains(token) ?? false)
            }
        )
        return (try? context.fetch(fd).count) ?? 0
    }

    func hasEventRecordedToday(event: String, contains token: String) -> Bool {
        countEntriesToday(event: event, contains: token) > 0
    }

    func xpAwardedForWorkoutToday(event: String, workoutId: String) -> Int {
        let sod = startOfDay(); let eod = endOfDay()
        let token = #""workoutId":"\#(workoutId)""#
        let fd = FetchDescriptor<RewardLedgerEntry>(
            predicate: #Predicate {
                $0.event == event &&
                $0.occurredAt >= sod && $0.occurredAt < eod &&
                ($0.metadataJSON?.contains(token) ?? false)
            }
        )
        let items = (try? context.fetch(fd)) ?? []
        return items.reduce(0) { $0 + $1.deltaXP }
    }
}

// MARK: - Utilities

extension RewardsEngine {
    func encodeJSON(_ dict: [String:Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}
