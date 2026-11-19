import Foundation

struct CutPostComposeWorkoutFacts: Equatable, Identifiable {
    var id: UUID
    var title: String
    var date: Date
    var icon: String
    var isCardio = false
    var isHealthKitOnlyStrength = false
    var durationSeconds: Int?
    var calories: Double?
    var heartRate: Double?
    var exercises = 0
    var sets = 0
}
struct CutPostComposeWeeklyFacts: Equatable {
    var volumeKg: Double
    var exercises: Int
    var sets: Int
    var strengthDone: Int
    var strengthTarget: Int
    var activeDone: Int
    var activeTarget: Int
    var streak: Int
    var superStreak: Int
}
struct CutPostComposeModel: Equatable {
    enum WorkoutState: Equatable { case loading, empty, choose, selected }
    enum PhotoKind: Equatable { case attached, picked(Int), map }
    struct Photo: Equatable, Identifiable {
        var id: String
        var kind: PhotoKind
        var privacy: Bool?
        var canRemove: Bool
    }
    struct Workout: Equatable, Identifiable {
        var id: UUID
        var title: String
        var date: String
        var icon: String
        var stats: String
    }
    struct Partner: Equatable, Identifiable {
        var id: UUID
        var name: String
        var handle: String
        var initials: String
        var avatarURL: String?
    }
    var title: String
    var isInitializing = false
    var canShare = false
    var workoutState: WorkoutState = .loading
    var workouts: [Workout] = []
    var weeklyStats: [[CutStatColumn]] = []
    var superStreak: String?
    var sessionHint: String?
    var showsPartner = false
    var partner: Partner?
    var isLoadingFriends = false
    var photos: [Photo] = []
    /// Explains the workout a handed-in picture (the year award) rides on, nil otherwise.
    var workoutNote: String?
    var errorTitle: String?
    var errorMessage: String?
    var errorIsRetryable = false
    var overlay: String?
}

enum CutPostComposeLogic {
    static func model(title: String, selected: [CutPostComposeWorkoutFacts], available: [CutPostComposeWorkoutFacts],
                      loadingWorkouts: Bool = false, uploading: Bool = false, generatingMap: Bool = false,
                      weekly: CutPostComposeWeeklyFacts? = nil, partner: CutPostComposeModel.Partner? = nil,
                      loadingFriends: Bool = false, attached: Bool = false, pickedPrivacy: [Bool?] = [], map: Bool = false,
                      errorTitle: String? = nil, errorMessage: String? = nil, errorIsRetryable: Bool = false, unit: WeightUnit = .kg,
                      locale: Locale = .current) -> CutPostComposeModel {
        var model = CutPostComposeModel(title: title, canShare: canShare(selectedCount: selected.count, uploading: uploading),
                                        workoutState: selected.isEmpty ? (loadingWorkouts ? .loading : available.isEmpty ? .empty : .choose) : .selected,
                                        workouts: selected.map { workout($0, locale: locale) },
                                        showsPartner: weekly == nil && !selected.isEmpty, partner: partner, isLoadingFriends: loadingFriends,
                                        photos: photos(attached: attached, pickedPrivacy: pickedPrivacy, map: map),
                                        errorTitle: errorTitle, errorMessage: errorMessage, errorIsRetryable: errorIsRetryable,
                                        overlay: uploading ? "Sharing workout..." : generatingMap ? "Preparing map..." : nil)
        if attached, weekly == nil { model.workoutNote = attachedWorkoutNote }
        if let weekly {
            model.weeklyStats = [[.init(value: unit.formatVolumeValue(weekly.volumeKg), label: "Tonnage", unit: unit.label),
                                  .init(value: "\(weekly.exercises)", label: "Exercises"), .init(value: "\(weekly.sets)", label: "Sets")],
                                [.init(value: "\(weekly.strengthDone)/\(weekly.strengthTarget)", label: "Strength"),
                                 .init(value: "\(weekly.activeDone)/\(weekly.activeTarget)", label: "Active min"),
                                 .init(value: "\(weekly.streak)", label: "Wk streak", isHighlighted: weekly.streak > 0)]]
            if weekly.superStreak > 0 { model.superStreak = "Super Streak: \(weekly.superStreak) week\(weekly.superStreak == 1 ? "" : "s")" }
            if selected.count > 1 { model.sessionHint = "\(selected.count) sessions included" }
        }
        return model
    }
    /// A post always carries a workout, so a handed-in picture goes out with one: say so, so
    /// the award does not read as a post about that run.
    static let attachedWorkoutNote = "Every post goes out with a workout, so your award is attached to your latest one. Change it if you like."
    static func workoutSectionTitle(_ model: CutPostComposeModel) -> String {
        if !model.weeklyStats.isEmpty { return "Weekly Progress" }
        if model.workoutNote != nil { return "Posted with" }
        return model.workouts.count > 1 ? "Session" : "Workout"
    }
    static func canShare(selectedCount: Int, uploading: Bool) -> Bool { selectedCount > 0 && !uploading }
    static func photos(attached: Bool, pickedPrivacy: [Bool?], map: Bool) -> [CutPostComposeModel.Photo] {
        var photos: [CutPostComposeModel.Photo] = []
        if attached { photos.append(.init(id: "attached", kind: .attached, privacy: true, canRemove: false)) }
        photos += pickedPrivacy.enumerated().map { .init(id: "picked-\($0.offset)", kind: .picked($0.offset), privacy: $0.element, canRemove: true) }
        if map { photos.append(.init(id: "map", kind: .map, privacy: true, canRemove: false)) }
        return photos
    }
    static func workout(_ facts: CutPostComposeWorkoutFacts, locale: Locale = .current) -> CutPostComposeModel.Workout {
        var stats: [String] = []
        if facts.isCardio || facts.isHealthKitOnlyStrength {
            // Keep the legacy cardio and HealthKit-only row order.
            if facts.isHealthKitOnlyStrength, let duration = facts.durationSeconds { stats.append("\(duration / 60) min") }
            if let calories = facts.calories { stats.append(String(format: "%.0f cal", calories)) }
            if facts.isCardio, let duration = facts.durationSeconds { stats.append("\(duration / 60) min") }
            if facts.isHealthKitOnlyStrength, let heartRate = facts.heartRate { stats.append(String(format: "%.0f bpm", heartRate)) }
        } else {
            stats = ["\(facts.exercises) exercises", "\(facts.sets) sets"]
        }
        return .init(id: facts.id, title: facts.title, date: facts.date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)),
                     icon: facts.icon, stats: stats.joined(separator: " · "))
    }
    static func visibilityDescription(_ visibility: PostVisibility) -> String {
        switch visibility {
        case .publicPost: "Anyone can see this post"
        case .friends: "Only your friends can see this"
        case .privatePost: "Only you can see this"
        }
    }
    static func toggledSelection(_ ids: Set<UUID>, id: UUID) -> Set<UUID> {
        var next = ids
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next
    }
    static func committedSelection(availableIDs: [UUID], pending: Set<UUID>) -> [UUID] { availableIDs.filter { pending.contains($0) } }
    static func selectionButtonTitle(_ count: Int) -> String {
        "Use \(count) workout\(count == 1 ? "" : "s")"
    }
    static func canFinishSelection(_ pending: Set<UUID>) -> Bool { !pending.isEmpty }
    static func shouldGenerateMaps(initialWorkoutProvided: Bool, attached: Bool, selection: [UUID]) -> Bool {
        !initialWorkoutProvided && !attached && !selection.isEmpty
    }
}
