//
//  CutTrainView.swift
//  WRKT
//
//  The Train tab in the Cut language: lime field with the hero and its actions, the weekly
//  goal on the V mark, and up to three hairline rows. Takes plain values and closures only,
//  so every state can be rendered without the app's services (see CutTrainHost for live data).
//

import SwiftUI

/// What the Train tab's controls do. Every closure calls an existing flow.
struct CutTrainActions {
    var startWorkout: () -> Void = {}
    var chooseWorkout: () -> Void = {}
    var browseExercises: () -> Void = {}
    var setUpPlan: () -> Void = {}
    var viewWorkout: () -> Void = {}
    var addExercise: () -> Void = {}
    var extendRest: () -> Void = {}
    var skipRest: () -> Void = {}
    var openRow: (CutTrainRow.Kind) -> Void = { _ in }
    /// Rows that navigate; the others are plain text, as their legacy elements were.
    var tappableRows: Set<CutTrainRow.Kind> = []
}

struct CutTrainView: View {
    let model: CutTrainModel
    var actions = CutTrainActions()

    var body: some View {
        // The reader keeps the safe area, so it reports the status bar height the field's
        // content has to clear once the scroll view runs under it.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CutTrainField(hero: model.hero, topInset: proxy.safeAreaInsets.top, actions: actions)
                    if let goal = model.weeklyGoal {
                        CutTrainWeeklyGoalView(goal: goal)
                    }
                    if !model.rows.isEmpty {
                        CutTrainRows(rows: model.rows, actions: actions)
                            .padding(.top, model.weeklyGoal == nil ? 30 : 0)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            .cutHidesTopScrollEdge()
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}

// MARK: - Field

private struct CutTrainField: View {
    let hero: CutTrainHero
    let topInset: CGFloat
    let actions: CutTrainActions

    private var tone: CutField<EmptyView>.Tone {
        if case .restDay = hero { return .dark }
        return .lime
    }

    private var fieldColor: Color {
        tone == .lime ? DS.Cut.Colors.lime : DS.Cut.Colors.darkField
    }

    var body: some View {
        CutField(tone: tone == .lime ? .lime : .dark,
                 // 84 at the bottom keeps a two-pill row ("Start workout", "Set up a plan")
                 // clear of the 112 pt cut on a 402 pt wide screen.
                 padding: EdgeInsets(top: topInset + 2, leading: DS.Cut.Metrics.gutter,
                                     bottom: 84, trailing: DS.Cut.Metrics.gutter)) {
            topRow
            heroBlock
            CutTrainHeroActions(hero: hero, actions: actions)
                .padding(.top, 22)
        }
        // Keeps the field colour above the top when the scroll view bounces.
        .background(alignment: .top) {
            Rectangle()
                .fill(fieldColor)
                .frame(height: 600)
                .offset(y: -600)
                .accessibilityHidden(true)
        }
    }

    private var topRow: some View {
        HStack(alignment: .center) {
            VMarkShape()
                .fill(tone == .lime ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
                .frame(width: 40, height: 24)
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            switch hero {
            case .live(_, _, _, let startDate):
                CutTrainElapsedClock(startDate: startDate)
            case .resting:
                Button("Add exercise", systemImage: "plus", action: actions.addExercise)
                    .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: 44))
            default:
                EmptyView()
            }
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var heroBlock: some View {
        let line = CutTrainLogic.heroLine(hero)
        VStack(alignment: .leading, spacing: 0) {
            switch hero {
            case .resting(_, let countdown):
                CutTrainRestCountdown(countdown: countdown)
                    .padding(.top, 20)
            default:
                let lines = CutHeroText.balancedLines(CutTrainLogic.heroTitle(hero))
                CutHeroText(lines, hero: CutTrainLogic.heroSize(forLines: lines), minimumScaleFactor: 0.25)
                    .padding(.top, 36)
            }
            if let line {
                Text(line)
                    .cutFont(.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
            if case .live(_, let done, let count, _) = hero, count > 0 {
                CutSegmentProgress(total: count, filled: done, current: done < count ? done : nil)
                    .frame(maxWidth: 300)
                    .padding(.top, 14)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .modifier(HeroAccessibilityLabel(hero: hero, line: line))
    }
}

/// Hero plus line as one VoiceOver element. The resting countdown keeps its own live value,
/// so its label is left to the combined children.
private struct HeroAccessibilityLabel: ViewModifier {
    let hero: CutTrainHero
    let line: String?

    func body(content: Content) -> some View {
        if case .resting = hero {
            content
        } else {
            let title = CutTrainLogic.heroTitle(hero)
            content.accessibilityLabel(Text(line.map { "\(title). \($0)" } ?? title))
        }
    }
}

// MARK: - Hero actions

private struct CutTrainHeroActions: View {
    let hero: CutTrainHero
    let actions: CutTrainActions

    var body: some View {
        // Side by side when they fit; stacked at large Dynamic Type sizes.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(alignment: .leading, spacing: 10) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch hero {
        case .planned:
            Button("Start workout", systemImage: "arrow.right") {
                Haptics.medium()
                actions.startWorkout()
            }
            .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
            CutTrainMoreMenu(actions: actions)
        case .restDay:
            Button("Start workout", systemImage: "arrow.right") {
                Haptics.medium()
                actions.startWorkout()
            }
            .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
            Button("Browse exercises", systemImage: "magnifyingglass", action: actions.browseExercises)
                .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: 56))
        case .noPlan:
            Button("Start workout", systemImage: "arrow.right") {
                Haptics.medium()
                actions.startWorkout()
            }
            .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
            Button("Set up a plan", action: actions.setUpPlan)
                .buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
        case .live:
            Button("View workout", systemImage: "arrow.right") {
                Haptics.light()
                actions.viewWorkout()
            }
            .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
            Button("Add exercise", systemImage: "plus") {
                Haptics.medium()
                actions.addExercise()
            }
            .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: 56))
        case .resting:
            Button("View", systemImage: "arrow.right") {
                Haptics.light()
                actions.viewWorkout()
            }
            .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
            .accessibilityLabel("View workout")
            Button("+15 s", action: actions.extendRest)
                .buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
                .accessibilityLabel("Add 15 seconds")
            Button("Skip") {
                Haptics.medium()
                actions.skipRest()
            }
            .buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
            .accessibilityLabel("Skip rest")
        }
    }
}

/// The round more button on a lime field. A Menu draws its own label, so the outline icon
/// button look is reproduced here rather than through CutIconButtonStyle.
private struct CutTrainMoreMenu: View {
    let actions: CutTrainActions

    var body: some View {
        Menu {
            Button("Start a different workout", systemImage: "list.bullet", action: actions.chooseWorkout)
            Button("Browse exercises", systemImage: "magnifyingglass", action: actions.browseExercises)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 56 * 0.42, weight: .semibold))
                .foregroundStyle(DS.Cut.Colors.ink)
                .frame(width: 56, height: 56)
                .overlay(Circle().strokeBorder(DS.Cut.Colors.ink, lineWidth: 2))
                .contentShape(Circle())
        }
        .accessibilityLabel("More options")
    }
}

// MARK: - Ticking leaves

/// Elapsed workout time. Only this view re-renders each second.
private struct CutTrainElapsedClock: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            HStack(spacing: 8) {
                SlantedSegmentShape()
                    .fill(DS.Cut.Colors.ink)
                    .frame(width: 12, height: 10)
                    .accessibilityHidden(true)
                Text(CutTrainLogic.elapsed(elapsed))
                    .font(DS.Cut.Typography.condensed(size: 24, relativeTo: .title3, monospacedDigits: true))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elapsed")
            .accessibilityValue(Text(Duration.seconds(max(0, elapsed)).formatted(.units(allowed: [.hours, .minutes]))))
        }
    }
}

/// The rest countdown as the hero numeral.
private struct CutTrainRestCountdown: View {
    let countdown: CutTrainCountdown

    var body: some View {
        switch countdown {
        case .live: CutTrainLiveRestCountdown()
        case .fixed(let seconds): CutTrainCountdownNumeral(seconds: seconds)
        }
    }
}

/// Observes the rest ticker; only this leaf re-renders each second (see RestTimerFanoutTests).
private struct CutTrainLiveRestCountdown: View {
    @ObservedObject private var ticker = RestTimerManager.shared.ticker

    var body: some View {
        CutTrainCountdownNumeral(seconds: ticker.remainingSeconds)
    }
}

private struct CutTrainCountdownNumeral: View {
    let seconds: TimeInterval

    var body: some View {
        Text(CutTrainLogic.countdown(seconds))
            .font(DS.Cut.Typography.condensed(size: DS.Cut.Typography.Hero.xxl.size, monospacedDigits: true))
            .tracking(DS.Cut.Typography.Hero.xxl.tracking)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .accessibilityLabel("Rest")
            .accessibilityValue(Text(Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.minutes, .seconds]))))
    }
}

// MARK: - Weekly goal

private struct CutTrainWeeklyGoalView: View {
    let goal: CutTrainWeeklyGoal

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Numbers under the mark so they keep their size.
                VStack(alignment: .leading, spacing: 18) {
                    mark.frame(width: 150)
                    numbers
                }
            } else {
                // The mark gives way to the numbers on narrow screens.
                HStack(spacing: 22) {
                    mark.frame(minWidth: 96, maxWidth: 150)
                    numbers.layoutPriority(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.vertical, 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CutTrainLogic.weeklyGoalAccessibilityLabel(goal))
    }

    private var mark: some View {
        VMarkProgress(
            left: CutTrainLogic.fraction(goal.strengthDone, of: goal.strengthTarget),
            right: CutTrainLogic.fraction(goal.cardioMinutes, of: goal.cardioTarget),
            accessibilityLabel: CutTrainLogic.weeklyGoalAccessibilityLabel(goal)
        )
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 10) {
            line("\(goal.strengthDone)/\(goal.strengthTarget)", "strength")
            line("\(goal.cardioMinutes)/\(goal.cardioTarget)", "cardio min")
        }
        .fixedSize()
    }

    private func line(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(DS.Cut.Typography.numeral(.medium))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
            Text(unit)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
        }
    }
}

// MARK: - Rows

private struct CutTrainRows: View {
    let rows: [CutTrainRow]
    let actions: CutTrainActions

    var body: some View {
        CutHairlineList {
            ForEach(rows) { row in
                let hairlineRow = CutHairlineRow(row.title, value: row.value,
                                                 valueTone: row.kind == .battle ? .lime : .secondary)
                if actions.tappableRows.contains(row.kind) {
                    Button {
                        Haptics.light()
                        actions.openRow(row.kind)
                    } label: {
                        hairlineRow
                    }
                    .buttonStyle(.plain)
                } else {
                    hairlineRow
                }
            }
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
    }
}

// MARK: - Previews

#if DEBUG
enum CutTrainFixtures {
    static let goal = CutTrainWeeklyGoal(strengthDone: 2, strengthTarget: 4, cardioMinutes: 95, cardioTarget: 150)

    static func rows(now: Date = .now) -> [CutTrainRow] {
        let friday = Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
        return CutTrainLogic.rows(battle: ("Battle with Alex", "Leading by 1,240 kg"), streakWeeks: 6,
                                  lastWorkout: ("Lower Body", friday), now: now)
    }

    static func model(_ hero: CutTrainHero) -> CutTrainModel {
        CutTrainModel(hero: hero, weeklyGoal: goal, rows: rows())
    }

    static let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now

    static let states: [(name: String, hero: CutTrainHero)] = [
        ("planned", .planned(name: "Upper Body", exerciseCount: 6)),
        ("planned-long-name", .planned(name: "Posterior Chain and Conditioning Superset", exerciseCount: 9)),
        ("rest-day", .restDay(next: PlanOutlook.Session(name: "Lower Body", date: tomorrow))),
        ("no-plan", .noPlan),
        ("live", .live(name: "Upper Body", exercisesDone: 2, exerciseCount: 6,
                       startDate: Date.now.addingTimeInterval(-(24 * 60 + 16)))),
        ("resting", .resting(nextLine: "Next: Bench Press, 85\u{00A0}kg\u{00A0}x\u{00A0}6", countdown: .fixed(92)))
    ]
}

#Preview("Cut Train states") {
    TabView {
        ForEach(CutTrainFixtures.states, id: \.name) { state in
            CutTrainView(model: CutTrainFixtures.model(state.hero))
        }
    }
    .tabViewStyle(.page)
    .preferredColorScheme(.dark)
}
#endif
