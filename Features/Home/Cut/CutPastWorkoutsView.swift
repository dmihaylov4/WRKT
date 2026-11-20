//
//  CutPastWorkoutsView.swift
//  WRKT
//
//  Past workouts sheet in the Cut language, presented like the start sheet: a plain system
//  sheet sized to its content with the start sheet's small title row. One workout at a time:
//  its name in condensed capitals with older and newer arrows, its day, its exercises as quiet
//  rows between hairlines, and one lime pill to start it again. Plain values and closures only.
//

import SwiftUI

struct CutPastWorkoutsView: View {
    let model: CutPastWorkoutsModel
    var onStart: (UUID) -> Void = { _ in }
    var onCancel: () -> Void = {}

    /// 0 is the newest workout.
    @State private var index: Int
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: CutPastWorkoutsModel, initialIndex: Int = 0,
         onStart: @escaping (UUID) -> Void = { _ in }, onCancel: @escaping () -> Void = {}) {
        self.model = model
        self.onStart = onStart
        self.onCancel = onCancel
        _index = State(initialValue: CutPastWorkoutsLogic.stepped(initialIndex, by: 0, count: model.workouts.count))
    }

    /// As tall as the tallest workout, so paging does not resize the sheet; a large sheet
    /// when that would pass the top of the screen, and the rows scroll above the button.
    private var detent: PresentationDetent {
        guard headerHeight > 0, contentHeight > 0, footerHeight > 0 else {
            return .height(CutPastWorkoutsLogic.estimatedHeight(model))
        }
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }.first ?? 844
        return CutSheetSizing.resolve(parts: [headerHeight, contentHeight, footerHeight], screen: screen).detent
    }

    private var current: CutPastWorkout? {
        model.workouts.indices.contains(index) ? model.workouts[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            CutStartSheetHeader(title: CutPastWorkoutsLogic.title, onCancel: onCancel)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            ScrollView {
                // Every page is laid out, only the current one is shown: the stack is as tall
                // as the tallest page.
                ZStack(alignment: .topLeading) {
                    ForEach(Array(model.workouts.enumerated()), id: \.element.id) { offset, workout in
                        page(workout)
                            .opacity(offset == index ? 1 : 0)
                            .allowsHitTesting(offset == index)
                            .accessibilityHidden(offset != index)
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            // Horizontal swipes page; vertical drags stay with the list and the sheet.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if let step = CutPastWorkoutsLogic.swipeStep(dx: value.translation.width,
                                                                     dy: value.translation.height) {
                            go(step)
                        }
                    }
            )
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([detent])
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .presentationDragIndicator(.visible)
    }

    // MARK: Page

    private func page(_ workout: CutPastWorkout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CutPastWorkoutTitle(workout: workout, index: index, count: model.workouts.count, step: go)
                .padding(.top, 10)
                .padding(.bottom, 18)
            CutHairline()
            ForEach(workout.exercises) { exercise in
                CutPastWorkoutExerciseRow(exercise: exercise)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Button {
            if let current { onStart(current.id) }
            Haptics.medium()
        } label: {
            // Wraps instead of truncating at the largest text sizes.
            Text(CutPastWorkoutsLogic.startTitle)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(CutPrimaryButtonStyle())
        .disabled(current == nil)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private func go(_ step: Int) {
        let next = CutPastWorkoutsLogic.stepped(index, by: step, count: model.workouts.count)
        guard next != index else { return }
        Haptics.light()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { index = next }
    }
}

/// The workout's name in condensed capitals with its day under it, and the two arrows.
/// At accessibility text sizes the arrows move under the day so the name keeps the width.
private struct CutPastWorkoutTitle: View {
    let workout: CutPastWorkout
    let index: Int
    let count: Int
    let step: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                nameAndDay
                arrows
            }
        } else {
            HStack(alignment: .center, spacing: 16) {
                nameAndDay
                    .frame(maxWidth: .infinity, alignment: .leading)
                arrows
            }
        }
    }

    private var nameAndDay: some View {
        VStack(alignment: .leading, spacing: 6) {
            CutHeroText(CutPastWorkoutsLogic.nameLines(workout.name), hero: .s, minimumScaleFactor: 0.25)
                .accessibilityAddTraits(.isHeader)
            Text(workout.day)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var arrows: some View {
        HStack(spacing: 10) {
            Button(CutPastWorkoutsLogic.olderLabel, systemImage: "chevron.left") { step(1) }
                .disabled(!CutPastWorkoutsLogic.canGoOlder(index: index, count: count))
            Button(CutPastWorkoutsLogic.newerLabel, systemImage: "chevron.right") { step(-1) }
                .disabled(!CutPastWorkoutsLogic.canGoNewer(index: index, count: count))
        }
        .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: 44))
    }
}

/// Exercise name on the left, last time's sets on the right; the sets move under the name
/// when the two do not fit on one line. One VoiceOver phrase.
private struct CutPastWorkoutExerciseRow: View {
    let exercise: CutPastWorkoutExercise

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    name.fixedSize()
                    Spacer(minLength: 12)
                    summary.fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    name.fixedSize(horizontal: false, vertical: true)
                    summary.fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            CutHairline()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(exercise.accessibilityLabel))
    }

    private var name: some View {
        Text(exercise.name)
            .cutFont(.body)
            .foregroundStyle(DS.Cut.Colors.textPrimary)
    }

    private var summary: some View {
        Text(exercise.summary)
            .cutFont(.secondary)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
    }
}

// MARK: - Fixtures

#if DEBUG
enum CutPastWorkoutsFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    static func set(_ reps: Int, _ kg: Double, tag: SetTag = .working, mode: TrackingMode = .weighted,
                    seconds: Int = 0, meters: Double = 0, done: Bool = true) -> SetInput {
        SetInput(reps: reps, weight: kg, tag: tag, isCompleted: done,
                 durationSeconds: seconds, distanceMeters: meters, trackingMode: mode)
    }

    static func entry(_ name: String, _ sets: [SetInput], muscles: [String] = ["Chest"]) -> WorkoutEntry {
        WorkoutEntry(exerciseID: name.lowercased().replacingOccurrences(of: " ", with: "-"),
                     exerciseName: name, muscleGroups: muscles, sets: sets)
    }

    static func workout(_ name: String?, daysAgo: Int, _ entries: [WorkoutEntry], now: Date = .now) -> CompletedWorkout {
        CompletedWorkout(date: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
                         entries: entries, workoutName: name)
    }

    static func fullBody(now: Date = .now) -> CompletedWorkout {
        workout("Full Body", daysAgo: 2, [
            entry("Back Squat", (0..<3).map { _ in set(8, 100) }, muscles: ["Quads"]),
            entry("Bench Press", [set(8, 80), set(6, 85), set(5, 87.5)]),
            entry("Barbell Row", (0..<3).map { _ in set(10, 60) }, muscles: ["Back"]),
            entry("Overhead Press", (0..<3).map { _ in set(8, 45) }, muscles: ["Shoulders"]),
            entry("Pull-Up", [set(10, 0, mode: .bodyweight), set(8, 0, mode: .bodyweight)], muscles: ["Back"]),
            entry("Plank", (0..<3).map { _ in set(0, 0, mode: .timed, seconds: 60) }, muscles: ["Abs"])
        ], now: now)
    }

    static func upperBody(now: Date = .now) -> CompletedWorkout {
        workout(nil, daysAgo: 4, [
            entry("Incline Dumbbell Press", (0..<3).map { _ in set(10, 30) }),
            entry("Lat Pulldown", [set(12, 55), set(10, 60), set(8, 65)], muscles: ["Back"]),
            entry("Lateral Raise", (0..<4).map { _ in set(15, 10) }, muscles: ["Shoulders"])
        ], now: now)
    }

    static func lowerBody(now: Date = .now) -> CompletedWorkout {
        workout("Legs and Conditioning", daysAgo: 6, [
            entry("Romanian Deadlift", [set(5, 60, tag: .warmup)] + (0..<3).map { _ in set(8, 110) }, muscles: ["Hamstrings"]),
            entry("Walking Lunge", (0..<3).map { _ in set(12, 20) }, muscles: ["Quads"]),
            entry("Rowing Machine", [set(0, 0, mode: .distance, seconds: 240, meters: 1000),
                                     set(0, 0, mode: .distance, seconds: 120, meters: 500)], muscles: ["Back"]),
            entry("Wall Sit", [set(0, 0, mode: .timed, seconds: 45), set(0, 0, mode: .timed, seconds: 60)], muscles: ["Quads"])
        ], now: now)
    }

    static func long(now: Date = .now) -> CompletedWorkout {
        let names = ["Back Squat", "Bench Press", "Barbell Row", "Overhead Press", "Romanian Deadlift",
                     "Incline Dumbbell Press", "Lat Pulldown", "Leg Press", "Seated Cable Row",
                     "Lateral Raise", "Triceps Pushdown", "Hammer Curl", "Leg Curl", "Calf Raise",
                     "Face Pull", "Cable Crunch"]
        return workout("Everything Day", daysAgo: 1, names.enumerated().map { offset, name in
            entry(name, (0..<3).map { _ in set(10, Double(20 + offset * 5)) })
        }, now: now)
    }

    static func model(_ workouts: [CompletedWorkout], unit: WeightUnit = .kg, now: Date = .now) -> CutPastWorkoutsModel {
        CutPastWorkoutsLogic.model(workouts, unit: unit, now: now, calendar: calendar)
    }

    static var three: CutPastWorkoutsModel { model([fullBody(), upperBody(), lowerBody()]) }
}

#Preview("Past workouts") {
    Color.black.sheet(isPresented: .constant(true)) {
        CutPastWorkoutsView(model: CutPastWorkoutsFixtures.three)
    }
}
#endif
