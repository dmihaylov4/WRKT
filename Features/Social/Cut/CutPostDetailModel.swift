//
//  CutPostDetailModel.swift
//  WRKT
//
//  One post opened, in the Cut language, as plain values: the same post row the feed shows,
//  then the workout behind it (workouts, exercises with their sets, splits, heart rate,
//  performance), the comments and the composer. Every format and decision is a pure function
//  of facts the host reads from PostDetailViewModel, so each state renders without the network.
//

import Foundation

// MARK: - Facts (what the host reads)

struct CutPostDetailFacts: Equatable {
    struct SetFacts: Equatable {
        /// The set as the app formats it ("90 kg x 8", "1:30", "12 reps").
        var value: String
        var tag: SetTag = .working
        var workSeconds: Double?
        var restSeconds: Int?
    }

    struct ExerciseFacts: Equatable {
        var name: String
        var sets: [SetFacts]
        var volumeKg: Double = 0
        var workSeconds: Double = 0
        var restSeconds: Double = 0
        var totalReps: Int = 0
    }

    struct WorkoutFacts: Equatable {
        var name: String
        /// A cardio session without logged exercises.
        var isCardio = false
        var durationSeconds: Double?
        var calories: Double?
        var sets = 0
        var distanceMeters: Double = 0
        var exercises: [ExerciseFacts] = []
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var minHeartRate: Double?
        var heartRateSamples: [HeartRateSample] = []
        var splits: [KilometerSplit] = []
        var zones: [HRZoneSummary] = []
        var power: Double?
        var cadence: Double?
        var strideLength: Double?
        var groundContact: Double?
        var verticalOscillation: Double?
    }

    struct CommentFacts: Equatable {
        var id: UUID
        var userId: UUID
        var name: String?
        var username: String?
        var avatarURL: String?
        var text: String
        var createdAt: Date
        var replies: [CommentFacts] = []
    }

    struct PersonFacts: Equatable {
        var id: UUID
        var username: String
        var name: String?
        var avatarURL: String?
    }

    /// The post as the feed reads it.
    var post: CutSocialPostFacts
    var battleDetail: String? = nil
    var zoneMethod: String? = nil
    var workouts: [WorkoutFacts] = []
    var currentUserId: UUID?
    /// The author can reload splits and zones from Health.
    var canRefreshCardio = false
    var isRefreshingCardio = false
    var isTogglingLike = false

    var comments: [CommentFacts] = []
    var isLoadingComments = false
    var error: String?

    var replyingTo: PersonFacts?
    var suggestions: [PersonFacts] = []
    var commentText = ""
    var isPostingComment = false
}

// MARK: - Display values

struct CutPostDetailModel: Equatable {
    enum Section: String, CaseIterable { case overview = "Overview", exercises = "Exercises", watch = "Watch" }
    var availableSections: [Section] = []
    var battleDetail: String? = nil
    var visibility: String = "Public"
    var overviewLine: String? = nil
    var showsMedia = true

    struct SetLine: Equatable, Identifiable {
        var id: Int
        var number: String
        var value: String
        /// "Warm-up, work 0:45, rest 2:00"; nil for a plain working set.
        var note: String?
    }

    struct Exercise: Equatable, Identifiable {
        var id: Int
        var title: String
        /// "4 sets, 1,240 kg"
        var line: String
        var sets: [SetLine]
        /// "Work 4:10, rest 8:20", shown when the exercise is open.
        var timing: String?
    }

    struct WorkoutRow: Equatable, Identifiable {
        var id: Int
        var title: String
        var line: String
        var value: String
    }

    struct Split: Equatable, Identifiable {
        var id: Int
        var label: String
        var pace: String
        var duration: String
        var fraction: Double
        var isFastest: Bool
    }

    struct HeartRatePoint: Equatable, Identifiable {
        var id: Int
        var seconds: Double
        var bpm: Double
    }

    struct Zone: Equatable, Identifiable {
        var id: Int
        var label: String
        var detail: String
        var time: String
        var fraction: Double
    }

    struct HeartRate: Equatable, Identifiable {
        var id: Int
        /// The workout's name when the post holds several.
        var title: String?
        var stats: [CutStatColumn]
        var points: [HeartRatePoint] = []
        var zones: [Zone]
        var energy: String? = nil
        var isEstimated: Bool
    }

    struct Comment: Equatable, Identifiable {
        var id: UUID
        var name: String
        var initials: String
        var avatarURL: String?
        var text: String
        var time: String
        var isReply: Bool
        var canReply: Bool
        var canDelete: Bool
    }

    enum Comments: Equatable {
        case loading
        case failed(String)
        case empty
        case list([Comment])
    }

    struct Suggestion: Equatable, Identifiable {
        var id: UUID
        var name: String
        var handle: String
        var initials: String
        var avatarURL: String?
    }

    struct Composer: Equatable {
        /// "Replying to @alex"
        var replyingTo: String?
        var suggestions: [Suggestion] = []
        var isPosting = false
        var canSend = false
        /// A post, like or delete that failed while comments are showing.
        var error: String?
    }

    var post: CutSocialPostRow
    /// The like count as the detail shows it: never below 1 while you like it.
    var likes: Int
    /// "12 likes": opens who liked it. Nil with no likes.
    var likesLabel: String?
    var isTogglingLike = false
    var workouts: [WorkoutRow] = []
    var exercises: [Exercise] = []
    var splits: [Split] = []
    var splitAverage: String? = nil
    var zoneMethod: String? = nil
    var heartRate: [HeartRate] = []
    var performance: [[CutStatColumn]] = []
    /// "Load details" or "Refresh details": the author reloading splits and zones.
    var refreshTitle: String?
    var isRefreshing = false
    var comments: Comments
    var composer: Composer
}

// MARK: - Logic

enum CutPostDetailLogic {
    static func model(_ facts: CutPostDetailFacts, now: Date, weightUnit: WeightUnit = .kg, locale: Locale = .current) -> CutPostDetailModel {
        let row = CutSocialLogic.row(facts.post, now: now, weightUnit: weightUnit, locale: locale)
        let likes = displayLikes(facts.post.likes, isLiked: facts.post.isLiked)
        let kind = facts.post.kind
        let showsWorkout: Bool = switch kind {
        case .battle: false
        default: true
        }
        let workouts = showsWorkout ? facts.workouts : []
        let singleCardio = workouts.count == 1 && workouts[0].isCardio ? workouts[0] : nil

        var model = CutPostDetailModel(
            post: row,
            likes: likes,
            likesLabel: likesLabel(likes),
            isTogglingLike: facts.isTogglingLike,
            comments: comments(facts, now: now, locale: locale),
            composer: composer(facts)
        )
        model.showsMedia = showsWorkout
        model.workouts = workoutRows(workouts)
        if !workouts.isEmpty, workouts.allSatisfy({ !$0.isCardio }) {
            model.workouts = workouts.flatMap(\.exercises).prefix(6).enumerated().map { index, exercise in
                .init(id: index, title: exercise.name, line: "\(exercise.sets.count) sets",
                      value: "\(CutSocialLogic.volumeStat(exercise.volumeKg, weightUnit: weightUnit, locale: locale).value) \(weightUnit.label)")
            }
        }
        model.availableSections = showsWorkout ? (singleCardio == nil ? [.overview, .exercises] : [.overview]) : []
        if (facts.canRefreshCardio && singleCardio != nil) || workouts.contains(where: { $0.averageHeartRate != nil || $0.maxHeartRate != nil || $0.minHeartRate != nil || $0.calories != nil || !$0.heartRateSamples.isEmpty || !$0.splits.isEmpty || !$0.zones.isEmpty || $0.power != nil || $0.cadence != nil || $0.strideLength != nil || $0.groundContact != nil || $0.verticalOscillation != nil }) {
            model.availableSections.append(.watch)
        }
        var overview: [String] = []
        let exerciseCount = workouts.flatMap(\.exercises).count
        if exerciseCount > 0 { overview.append("\(exerciseCount) exercises") }
        if workouts.count > 1 { overview.append("\(workouts.count) workouts") }
        let calories = workouts.compactMap(\.calories)
        if !calories.isEmpty { overview.append("\(CutSocialLogic.grouped(calories.reduce(0, +), locale: locale)) kcal") }
        let averages = workouts.compactMap(\.averageHeartRate)
        if !averages.isEmpty { overview.append("\(Int((averages.reduce(0, +) / Double(averages.count)).rounded())) bpm average") }
        if case .weekly = kind {
            let volume = workouts.flatMap(\.exercises).reduce(0) { $0 + $1.volumeKg }
            overview.append("\(CutSocialLogic.volumeStat(volume, weightUnit: weightUnit, locale: locale).value) \(weightUnit.label)")
            overview.append("\(workouts.reduce(0) { $0 + $1.sets }) sets")
            let durations = workouts.compactMap(\.durationSeconds)
            if !durations.isEmpty { overview.append(CutSocialLogic.clock(durations.reduce(0, +))) }
        }
        model.overviewLine = overview.isEmpty ? nil : overview.joined(separator: " · ")
        model.battleDetail = facts.battleDetail
        model.visibility = switch facts.post.visibility { case .everyone: "Public"; case .friends: "Friends"; case .onlyMe: "Only you" }
        model.exercises = exercises(workouts.flatMap(\.exercises), weightUnit: weightUnit, locale: locale)
        if let singleCardio {
            model.splits = zip(CutCardioLogic.splitRows(singleCardio.splits), singleCardio.splits.filter { $0.paceSecPerKm > 0 }).map { row, split in
                .init(id: row.id, label: row.label, pace: row.pace, duration: CutCardioLogic.duration(split.durationSec), fraction: row.fraction, isFastest: row.isFastest)
            }
            if !singleCardio.splits.isEmpty {
                let average = singleCardio.splits.reduce(0) { $0 + $1.paceSecPerKm } / singleCardio.splits.count
                model.splitAverage = CutCardioLogic.duration(average)
            }
        }
        model.zoneMethod = facts.zoneMethod
        model.heartRate = heartRate(workouts)
        model.performance = performance(workouts, singleCardio: singleCardio, locale: locale)
        if facts.canRefreshCardio, let singleCardio {
            model.refreshTitle = singleCardio.zones.isEmpty ? "Load details" : "Refresh details"
            model.isRefreshing = facts.isRefreshingCardio
        }
        return model
    }

    static func selectedSplit(_ splits: [CutPostDetailModel.Split], id: Int?) -> CutPostDetailModel.Split? {
        splits.first { $0.id == id } ?? splits.last
    }

    // MARK: Likes

    static func displayLikes(_ likes: Int, isLiked: Bool) -> Int {
        max(likes, isLiked ? 1 : 0)
    }

    static func likesLabel(_ likes: Int) -> String? {
        switch likes {
        case ..<1: nil
        case 1: "1 like"
        default: "\(likes) likes"
        }
    }

    // MARK: Workouts

    static func workoutRows(_ workouts: [CutPostDetailFacts.WorkoutFacts]) -> [CutPostDetailModel.WorkoutRow] {
        workouts.enumerated().map { index, workout in
            let value: String
            if let calories = workout.calories, calories > 0 {
                value = "\(Int(calories.rounded())) kcal"
            } else if workout.sets > 0 {
                value = workout.sets == 1 ? "1 set" : "\(workout.sets) sets"
            } else {
                value = ""
            }
            let line: String
            if workout.isCardio, workout.distanceMeters > 0 {
                line = "\(CutSocialLogic.distanceKm(workout.distanceMeters)) km" + (workout.durationSeconds.map { ", \(CutSocialLogic.clock($0))" } ?? "")
            } else {
                line = workout.durationSeconds.map { CutSocialLogic.clock($0) } ?? (workout.isCardio ? "Cardio" : "Strength")
            }
            return .init(id: index, title: workout.name, line: line, value: value)
        }
    }

    static func exercises(_ exercises: [CutPostDetailFacts.ExerciseFacts], weightUnit: WeightUnit, locale: Locale) -> [CutPostDetailModel.Exercise] {
        exercises.enumerated().map { index, exercise in
            let count = exercise.sets.count
            var line = (count == 1 ? "1 set" : "\(count) sets") + ", \(exercise.totalReps) reps"
            if exercise.volumeKg > 0 {
                line += ", \(CutSocialLogic.volumeStat(exercise.volumeKg, weightUnit: weightUnit, locale: locale).value) \(weightUnit.label)"
            }
            return .init(
                id: index,
                title: exercise.name,
                line: line,
                sets: exercise.sets.enumerated().map { setIndex, set in
                    .init(id: setIndex, number: "\(setIndex + 1)", value: set.value, note: setNote(set))
                },
                timing: timing(work: exercise.workSeconds, rest: exercise.restSeconds)
            )
        }
    }

    /// Only what differs from a plain working set: the tag, then work and rest when timed.
    static func setNote(_ set: CutPostDetailFacts.SetFacts) -> String? {
        var parts: [String] = []
        if set.tag != .working { parts.append(set.tag.label) }
        if let work = set.workSeconds, work >= 1 { parts.append("work \(shortDuration(work))") }
        if let rest = set.restSeconds, rest > 0 { parts.append("rest \(shortDuration(Double(rest)))") }
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: ", ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    static func timing(work: Double, rest: Double) -> String? {
        guard work + rest >= 1 else { return nil }
        var parts: [String] = ["Duration \(shortDuration(work + rest))"]
        if work >= 1 { parts.append("work \(shortDuration(work))") }
        if rest >= 1 { parts.append("rest \(shortDuration(rest))") }
        let joined = parts.joined(separator: ", ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    /// "0:45", "2:00", "1:05" (h:mm from an hour).
    static func shortDuration(_ seconds: Double) -> String {
        CutSocialLogic.clock(seconds)
    }

    // MARK: Heart rate

    static func heartRate(_ workouts: [CutPostDetailFacts.WorkoutFacts]) -> [CutPostDetailModel.HeartRate] {
        workouts.enumerated().compactMap { index, workout in
            var stats: [CutStatColumn] = []
            if let avg = workout.averageHeartRate, avg > 0 { stats.append(.init(value: "\(Int(avg.rounded()))", label: "Average")) }
            if let max = workout.maxHeartRate, max > 0 { stats.append(.init(value: "\(Int(max.rounded()))", label: "Max")) }
            if let min = workout.minHeartRate, min > 0 { stats.append(.init(value: "\(Int(min.rounded()))", label: "Min")) }
            let zones = zoneRows(workout.zones)
            let start = workout.heartRateSamples.first?.timestamp ?? .distantPast
            let points = workout.heartRateSamples.enumerated().compactMap { offset, sample -> CutPostDetailModel.HeartRatePoint? in
                guard sample.bpm.isFinite, sample.bpm > 0 else { return nil }
                return .init(id: offset, seconds: sample.timestamp.timeIntervalSince(start), bpm: sample.bpm)
            }
            guard !stats.isEmpty || !points.isEmpty || !zones.isEmpty || workout.calories != nil else { return nil }
            return .init(id: index, title: workouts.count > 1 ? workout.name : nil, stats: stats, points: points, zones: zones, energy: workout.calories.map { "\(Int($0.rounded())) kcal" },
                         isEstimated: !zones.isEmpty && workout.zones.first?.isEstimated == true)
        }
    }

    static func zoneRows(_ zones: [HRZoneSummary]) -> [CutPostDetailModel.Zone] {
        let total = zones.reduce(0) { $0 + $1.minutes }
        guard total > 0 else { return [] }
        return zones.sorted { $0.zone < $1.zone }.map {
            .init(id: $0.zone, label: "Zone \($0.zone)", detail: [$0.name, $0.rangeDisplay].filter { !$0.isEmpty }.joined(separator: " · "), time: CutCardioLogic.duration(Int(($0.minutes * 60).rounded())),
                  fraction: $0.minutes / total)
        }
    }

    // MARK: Performance

    /// Energy (when the top stats do not show it), then speed and the running dynamics of a
    /// single cardio session, two per row.
    static func performance(_ workouts: [CutPostDetailFacts.WorkoutFacts], singleCardio: CutPostDetailFacts.WorkoutFacts?,
                            locale: Locale) -> [[CutStatColumn]] {
        var items: [CutStatColumn] = []
        if let cardio = singleCardio {
            // Indoor cardio already shows energy in its stat columns.
            if cardio.distanceMeters > 0, let kcal = cardio.calories, kcal > 0 {
                items.append(.init(value: CutSocialLogic.grouped(kcal, locale: locale), label: "Energy", unit: "kcal"))
            }
            if cardio.distanceMeters > 0, let seconds = cardio.durationSeconds, seconds > 0 {
                items.append(.init(value: String(format: "%.1f", cardio.distanceMeters / seconds * 3.6), label: "Avg speed", unit: "km/h"))
            }
            if let power = cardio.power { items.append(.init(value: String(format: "%.0f", power), label: "Power", unit: "W")) }
            if let cadence = cardio.cadence { items.append(.init(value: String(format: "%.0f", cadence), label: "Cadence", unit: "spm")) }
            if let stride = cardio.strideLength { items.append(.init(value: String(format: "%.2f", stride), label: "Stride", unit: "m")) }
            if let contact = cardio.groundContact { items.append(.init(value: String(format: "%.0f", contact), label: "Ground contact", unit: "ms")) }
            if let oscillation = cardio.verticalOscillation {
                items.append(.init(value: String(format: "%.1f", oscillation), label: "Oscillation", unit: "cm"))
            }
        } else {
            let calories = workouts.compactMap(\.calories).filter { $0 > 0 }
            if !calories.isEmpty {
                items.append(.init(value: CutSocialLogic.grouped(calories.reduce(0, +), locale: locale), label: "Energy", unit: "kcal"))
            }
        }
        return stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }

    // MARK: Comments

    static func comments(_ facts: CutPostDetailFacts, now: Date, locale: Locale) -> CutPostDetailModel.Comments {
        if facts.comments.isEmpty {
            if facts.isLoadingComments { return .loading }
            if let error = facts.error { return .failed(error) }
            return .empty
        }
        var rows: [CutPostDetailModel.Comment] = []
        for comment in facts.comments {
            rows.append(commentRow(comment, isReply: false, currentUserId: facts.currentUserId, now: now, locale: locale))
            for reply in comment.replies {
                rows.append(commentRow(reply, isReply: true, currentUserId: facts.currentUserId, now: now, locale: locale))
            }
        }
        return .list(rows)
    }

    /// As the legacy CommentRow: a top-level comment can be replied to and, when it is yours,
    /// deleted; replies carry neither action.
    static func commentRow(_ comment: CutPostDetailFacts.CommentFacts, isReply: Bool, currentUserId: UUID?,
                           now: Date, locale: Locale) -> CutPostDetailModel.Comment {
        let isOwn = currentUserId != nil && comment.userId == currentUserId
        let name = comment.username ?? comment.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        return .init(
            id: comment.id,
            name: name,
            initials: CutSocialLogic.initials(comment.name ?? comment.username ?? ""),
            avatarURL: comment.avatarURL,
            text: comment.text,
            time: commentTime(comment.createdAt, now: now, locale: locale),
            isReply: isReply,
            canReply: !isReply,
            canDelete: !isReply && isOwn
        )
    }

    static func commentTime(_ date: Date, now: Date, locale: Locale) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func composer(_ facts: CutPostDetailFacts) -> CutPostDetailModel.Composer {
        let trimmed = facts.commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(
            replyingTo: facts.replyingTo.map { "Replying to @\($0.username)" },
            suggestions: facts.suggestions.map { person in
                .init(id: person.id, name: person.name.flatMap { $0.isEmpty ? nil : $0 } ?? person.username,
                      handle: "@\(person.username)", initials: CutSocialLogic.initials(person.name ?? person.username),
                      avatarURL: person.avatarURL)
            },
            isPosting: facts.isPostingComment,
            canSend: !trimmed.isEmpty && !facts.isPostingComment,
            error: facts.comments.isEmpty ? nil : facts.error
        )
    }

    // MARK: Mentions

    /// The comment split into plain runs and @mentions, in order, for highlighting.
    static func segments(_ text: String) -> [(text: String, isMention: Bool)] {
        guard let regex = try? NSRegularExpression(pattern: "@[A-Za-z0-9_]+") else { return [(text, false)] }
        let ns = text as NSString
        var result: [(String, Bool)] = []
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result.append((ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), false))
            }
            result.append((ns.substring(with: match.range), true))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { result.append((ns.substring(from: cursor), false)) }
        return result.isEmpty ? [(text, false)] : result
    }

    // MARK: Loader

    static let notFoundMessage = "This post may have been deleted or is no longer accessible"
}

/// Media bookkeeping stays testable without resolving remote images or creating a scene.
enum CutPostDetailMediaLogic {
    static func photoIndex(_ url: URL, photos: [URL]) -> Int? { photos.firstIndex(of: url) }
    static func opensMap(_ url: URL, maps: [URL], fullscreenMaps: Bool) -> Bool { fullscreenMaps && maps.contains(url) }
}
