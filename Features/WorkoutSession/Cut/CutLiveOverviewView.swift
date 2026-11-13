//
//  CutLiveOverviewView.swift
//  WRKT
//
//  The live workout overview in the Cut language: the workout name, a very large elapsed
//  clock, slanted segments for the exercises, the current exercise as a big row into set
//  logging, the others as hairline rows, and round minimise and more buttons with a Finish pill.
//  Plain values and closures only; LiveWorkoutOverlayCard wires them to its existing code.
//

import SwiftUI

/// What the overview's controls do. Every closure calls LiveWorkoutOverlayCard's existing code.
struct CutLiveOverviewActions {
    var open: (UUID) -> Void = { _ in }
    var swap: (UUID) -> Void = { _ in }
    var remove: (UUID) -> Void = { _ in }
    var removeFromSuperset: (UUID) -> Void = { _ in }
    var minimise: () -> Void = {}
    /// Runs after the finish dialog is confirmed.
    var finish: () -> Void = {}
    /// Runs after the discard dialog is confirmed.
    var discard: () -> Void = {}
}

/// Where the overview's rest line reads from.
enum CutOverviewRest: Equatable {
    case live
    case fixed(TimeInterval)
    case none
}

/// Which dialog is up.
enum CutLiveDialog: Equatable {
    case finish, discard
}

struct CutLiveOverviewView: View {
    let model: CutLiveOverviewModel
    var rest: CutOverviewRest = .live
    var actions = CutLiveOverviewActions()
    /// Captures only: a fixed clock and an open dialog.
    var fixedElapsed: TimeInterval?
    @State var dialog: CutLiveDialog?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    clock
                    if !model.segments.isEmpty {
                        CutStateSegments(states: model.segments)
                            .padding(.top, 18)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Exercises")
                            .accessibilityValue(CutLiveOverviewLogic.segmentsAccessibilityValue(model.segments))
                    }
                    nowBlock
                    ForEach(model.sections) { section in
                        CutSectionTitle(section.title)
                            .padding(.top, 30)
                            .padding(.bottom, 10)
                        CutHairlineList {
                            ForEach(section.rows) { row in
                                exerciseRow(row)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .overlay {
            if let dialog {
                dialogView(dialog)
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Minimize workout", systemImage: "chevron.down") {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { actions.minimise() }
            }
            .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: 44))
            Spacer(minLength: 8)
            Text(model.title)
                .cutFont(.title)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Menu {
                Button("Discard workout", systemImage: "trash", role: .destructive) {
                    withAnimation(.easeOut(duration: 0.2)) { dialog = .discard }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 44 * 0.42, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.Cut.Colors.controlFill))
                    .contentShape(Circle())
            }
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Clock

    private var clock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let fixedElapsed {
                    CutElapsedNumeral(seconds: fixedElapsed)
                } else {
                    CutElapsedClock(startDate: model.startDate)
                }
            }
            CutOverviewSummaryLine(summary: model.summaryLine, rest: rest)
        }
        .padding(.top, 8)
    }

    // MARK: Now

    @ViewBuilder
    private var nowBlock: some View {
        if let now = model.now {
            CutSectionTitle("Now")
                .padding(.top, 30)
                .padding(.bottom, 10)
            CutHairline()
            Button {
                actions.open(now.id)
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        let lines = CutHeroText.balancedLines(now.name)
                        CutHeroText(lines, hero: CutTrainLogic.heroSize(forLines: lines) == .xl ? .m : .s,
                                    minimumScaleFactor: 0.3)
                        Text(now.line)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CutTile(systemImage: "arrow.right", side: 60)
                }
                .padding(.vertical, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { rowMenu(now, canRemove: false) }
            // On the button itself, so VoiceOver keeps its action.
            .accessibilityLabel(Text("\(now.name). \(now.line)"))
            .accessibilityHint(Text("Opens set logging"))
            .accessibilityAction(named: "Swap exercise") { actions.swap(now.id) }
            CutHairline()
            ForEach(model.nowPartners) { row in
                exerciseRow(row)
            }
        } else if model.allDone {
            VStack(alignment: .leading, spacing: 8) {
                Text("All exercises done")
                    .cutHero(.s)
                Text("Finish the workout when you are ready.")
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
            }
            .padding(.top, 30)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Rows

    private func exerciseRow(_ row: CutLiveRow) -> some View {
        Button {
            actions.open(row.id)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Group {
                        if row.state == .finished {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(DS.Cut.Colors.lime)
                        } else {
                            SlantedSegmentShape()
                                .fill(row.state == .inProgress ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.segmentTrack)
                                .frame(width: 14, height: 10)
                        }
                    }
                    .frame(width: 18)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .cutFont(.title)
                            .foregroundStyle(row.state == .finished ? DS.Cut.Colors.textSecondary : DS.Cut.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text(row.line)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 50)
                .padding(.vertical, 10)
                CutHairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(row, canRemove: true) }
        .accessibilityLabel(Text("\(row.name). \(row.line)"))
        .accessibilityAction(named: "Swap exercise") { actions.swap(row.id) }
        .accessibilityAction(named: "Remove exercise") { actions.remove(row.id) }
    }

    @ViewBuilder
    private func rowMenu(_ row: CutLiveRow, canRemove: Bool) -> some View {
        Button("Edit exercise", systemImage: "pencil") { actions.open(row.id) }
        Button("Swap exercise", systemImage: "arrow.left.arrow.right") { actions.swap(row.id) }
        if row.isInSuperset {
            Button("Remove from superset", systemImage: "arrow.triangle.2.circlepath") {
                actions.removeFromSuperset(row.id)
            }
        }
        if canRemove {
            Divider()
            Button("Remove exercise", systemImage: "trash", role: .destructive) { actions.remove(row.id) }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.canFinish {
                Text("Complete or remove all exercises to finish.")
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Finish workout") {
                withAnimation(.easeOut(duration: 0.2)) { dialog = .finish }
            }
            .buttonStyle(.cutPrimary)
            .disabled(!model.canFinish)
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    // MARK: Dialogs

    @ViewBuilder
    private func dialogView(_ kind: CutLiveDialog) -> some View {
        switch kind {
        case .finish:
            CutDialog(
                message: "Finish this workout and save it?",
                primaryTitle: "Finish workout",
                primaryRole: nil,
                onPrimary: {
                    dialog = nil
                    actions.finish()
                },
                onCancel: { withAnimation(.easeOut(duration: 0.2)) { dialog = nil } }
            )
        case .discard:
            CutDialog(
                message: "Discard this workout? You can undo this.",
                primaryTitle: "Discard workout",
                primaryRole: .destructive,
                onPrimary: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dialog = nil }
                    // As the legacy dialog: let it close before discarding.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { actions.discard() }
                },
                onCancel: { withAnimation(.easeOut(duration: 0.2)) { dialog = nil } }
            )
        }
    }
}

// MARK: - Segments with explicit states

/// Slanted segments where any segment can be done, current or to do.
struct CutStateSegments: View {
    let states: [CutSegmentState]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                SlantedSegmentShape()
                    .fill(color(state))
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(_ state: CutSegmentState) -> Color {
        switch state {
        case .done: DS.Cut.Colors.lime
        case .current: DS.Cut.Colors.textPrimary
        case .toDo: DS.Cut.Colors.segmentTrack
        }
    }
}

// MARK: - Ticking leaves

/// The very large elapsed clock. Only this view re-renders each second.
struct CutElapsedClock: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { context in
            CutElapsedNumeral(seconds: context.date.timeIntervalSince(startDate))
        }
    }
}

struct CutElapsedNumeral: View {
    let seconds: TimeInterval

    var body: some View {
        Text(CutTrainLogic.elapsed(seconds))
            .font(DS.Cut.Typography.condensed(size: 112, monospacedDigits: true))
            .tracking(-2)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .accessibilityLabel("Elapsed")
            .accessibilityValue(Text(Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.hours, .minutes]))))
    }
}

/// The line under the clock: the workout so far, or the rest countdown while resting.
private struct CutOverviewSummaryLine: View {
    let summary: String
    let rest: CutOverviewRest

    var body: some View {
        switch rest {
        case .none:
            summaryText
        case .fixed(let seconds):
            restText("Resting \(CutTrainLogic.countdown(seconds))")
        case .live:
            CutOverviewRestGate(summary: summaryText)
        }
    }

    private var summaryText: some View {
        Text(summary)
            .cutFont(.title)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
    }

    private func restText(_ text: String) -> some View {
        Text(text)
            .font(DS.Cut.Typography.font(.title, monospacedDigits: true))
            .foregroundStyle(DS.Cut.Colors.lime)
    }
}

/// Watches the rest timer's state (transitions only), as the legacy header did.
private struct CutOverviewRestGate<Summary: View>: View {
    let summary: Summary
    @ObservedObject private var manager = RestTimerManager.shared

    var body: some View {
        if manager.isRunning {
            CutOverviewRestCountdown()
        } else if manager.isCompleted {
            Text("Rest done, ready for the next set")
                .cutFont(.title)
                .foregroundStyle(DS.Cut.Colors.lime)
        } else {
            summary
        }
    }
}

/// The only overview view that observes the per-second ticker.
private struct CutOverviewRestCountdown: View {
    @ObservedObject private var ticker = RestTimerManager.shared.ticker

    var body: some View {
        Text("Resting \(CutTrainLogic.countdown(ticker.remainingSeconds))")
            .font(DS.Cut.Typography.font(.title, monospacedDigits: true))
            .foregroundStyle(DS.Cut.Colors.lime)
            .accessibilityLabel("Resting")
            .accessibilityValue(Duration.seconds(max(0, ticker.remainingSeconds)).formatted(.units(allowed: [.minutes, .seconds])))
    }
}

// MARK: - Dialog

/// A plain dialog: one sentence and two buttons, over a dimmed background.
struct CutDialog: View {
    let message: String
    let primaryTitle: String
    let primaryRole: ButtonRole?
    let onPrimary: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 22) {
                Text(message)
                    .font(DS.Cut.Typography.font(.title))
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { buttons }
                    VStack(spacing: 10) { buttons }
                }
            }
            .padding(24)
            .background(
                CutCornerShape(corner: .bottomTrailing, cut: .points(24))
                    .fill(DS.Cut.Colors.darkField)
            )
            .overlay(
                CutCornerShape(corner: .bottomTrailing, cut: .points(24))
                    .stroke(DS.Cut.Colors.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8)) {
                shown = true
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Cancel", action: onCancel)
            .buttonStyle(CutSecondaryButtonStyle(size: .compact))
        if primaryRole == .destructive {
            Button(primaryTitle, role: .destructive, action: onPrimary)
                .buttonStyle(CutDestructiveButtonStyle())
        } else {
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(CutPrimaryButtonStyle(size: .compact))
        }
    }
}

/// Outlined red pill for a destructive choice in a dialog.
struct CutDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Cut.Typography.font(.buttonCompact).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(DS.Status.error)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(Capsule().strokeBorder(DS.Status.error, lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Fixtures

#if DEBUG
enum CutLiveOverviewFixtures {
    static func entry(_ name: String, done: Int, of count: Int, weight: Double, reps: Int,
                      superset: UUID? = nil, order: Int? = nil) -> WorkoutEntry {
        var entry = WorkoutEntry(exerciseID: "fixture-" + name, exerciseName: name, muscleGroups: [],
                                 sets: (0..<count).map { SetInput(reps: reps, weight: weight, isCompleted: $0 < done) })
        entry.supersetGroupID = superset
        entry.orderInSuperset = order
        return entry
    }

    static var entries: [WorkoutEntry] {
        [
            entry("Warm-up Row", done: 2, of: 2, weight: 20, reps: 10),
            entry("Bench Press", done: 2, of: 4, weight: 85, reps: 6),
            entry("Incline DB Press", done: 0, of: 3, weight: 32, reps: 10),
            entry("Overhead Press", done: 0, of: 4, weight: 50, reps: 6),
            entry("Lateral Raise", done: 0, of: 3, weight: 12, reps: 15),
            entry("Triceps Pushdown", done: 0, of: 3, weight: 30, reps: 12)
        ]
    }

    static var allDoneEntries: [WorkoutEntry] {
        [entry("Bench Press", done: 4, of: 4, weight: 85, reps: 6), entry("Row", done: 3, of: 3, weight: 70, reps: 8)]
    }

    static func model(_ entries: [WorkoutEntry] = entries) -> CutLiveOverviewModel {
        CutLiveOverviewLogic.model(title: "Live workout", startDate: .now.addingTimeInterval(-(24 * 60 + 19)),
                                   entries: entries, activeEntryID: entries.dropFirst().first?.id, unit: .kg)
    }
}
#endif
