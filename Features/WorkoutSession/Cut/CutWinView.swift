//
//  CutWinView.swift
//  WRKT
//
//  The workout complete screen in the Cut language: a lime field with "DONE." as the hero,
//  the XP gained with the level line and the record as one line; then on black the duration,
//  volume and sets as three big numerals with 1 pt dividers, hairline rows for anything
//  unlocked, and two pills. Plain values and closures only; CutWinScreen hosts it.
//

import SwiftUI

struct CutWinActions {
    var share: () -> Void = {}
    var proceed: () -> Void = {}
}

struct CutWinView: View {
    let model: CutWinModel
    /// "Continue", or "See your barbell" before a full screen plate moment.
    var continueTitle = "Continue"
    var actions = CutWinActions()
    /// Rows appear one after another; captures pass true to show everything at once.
    var revealsImmediately = false

    @State private var revealed = false
    @State private var showsBreakdown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    field(topInset: proxy.safeAreaInsets.top)
                    if !model.stats.isEmpty {
                        stats
                            .padding(.top, 28)
                            .rise(revealed, delay: 0.25, reduceMotion: reduceMotion)
                    }
                    rows
                        .padding(.top, model.stats.isEmpty ? 28 : 24)
                        .rise(revealed, delay: 0.35, reduceMotion: reduceMotion)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            .cutHidesTopScrollEdge()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .onAppear {
            if revealsImmediately || reduceMotion {
                revealed = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { revealed = true }
            }
        }
        .sheet(isPresented: $showsBreakdown) {
            CutXPBreakdownSheet(items: model.xpItems)
        }
    }

    // MARK: Field

    private func field(topInset: CGFloat) -> some View {
        CutField(padding: EdgeInsets(top: topInset + 40, leading: DS.Cut.Metrics.gutter,
                                     bottom: 96, trailing: DS.Cut.Metrics.gutter)) {
            Text(model.hero)
                .cutHero(.xxl, minimumScaleFactor: 0.3)
                .accessibilityAddTraits(.isHeader)
                .rise(revealed, delay: 0, reduceMotion: reduceMotion)
            if let xp = model.xp {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) { xpText(xp); levelText }
                    VStack(alignment: .leading, spacing: 4) { xpText(xp); levelText }
                }
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .rise(revealed, delay: 0.1, reduceMotion: reduceMotion)
            } else if let level = model.levelLine {
                Text(level)
                    .cutFont(.title)
                    .padding(.top, 18)
            }
            if let record = model.recordLine {
                Text(record)
                    .cutFont(.title)
                    .padding(.top, 14)
                    .rise(revealed, delay: 0.15, reduceMotion: reduceMotion)
            }
        }
        // Keeps the lime above the top when the scroll view bounces.
        .background(alignment: .top) {
            Rectangle().fill(DS.Cut.Colors.lime).frame(height: 600).offset(y: -600).accessibilityHidden(true)
        }
    }

    private func xpText(_ xp: String) -> some View {
        Text(xp)
            .font(DS.Cut.Typography.numeral(.large))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var levelText: some View {
        if let level = model.levelLine {
            Text(level)
                .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                .foregroundStyle(DS.Cut.Colors.inkSecondary)
        }
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.stats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(DS.Cut.Colors.hairline)
                        .frame(width: DS.Cut.Metrics.hairline)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.value)
                        .font(DS.Cut.Typography.numeral(.large))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text(stat.label)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, index == 0 ? 0 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stat.label)
                .accessibilityValue(stat.value)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        if !model.rows.isEmpty || !model.xpItems.isEmpty {
            CutHairlineList {
                ForEach(model.rows) { row in
                    CutHairlineRow(row.title, value: row.value, valueTone: .lime)
                }
                if !model.xpItems.isEmpty {
                    Button {
                        showsBreakdown = true
                    } label: {
                        CutHairlineRow("XP breakdown", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
        }
    }

    // MARK: Footer

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { footerButtons }
            VStack(spacing: 10) { footerButtons }
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.black.ignoresSafeArea(edges: .bottom))
        .rise(revealed, delay: 0.45, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var footerButtons: some View {
        if model.showsShare {
            Button("Share workout", systemImage: "square.and.arrow.up") {
                Haptics.light()
                actions.share()
            }
            .buttonStyle(.cutPrimary)
            Button(continueTitle) {
                Haptics.light()
                actions.proceed()
            }
            .buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
        } else {
            Button(continueTitle) {
                Haptics.light()
                actions.proceed()
            }
            .buttonStyle(.cutPrimary)
        }
    }
}

/// The legacy XP breakdown as hairline rows in a sheet.
private struct CutXPBreakdownSheet: View {
    let items: [CutWinXPItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("XP breakdown").cutFont(.title).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }
                    .font(DS.Cut.Typography.font(.title))
                    .foregroundStyle(DS.Cut.Colors.lime)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 14)
            ScrollView {
                CutHairlineList {
                    ForEach(items) { item in
                        CutHairlineRow(item.title, value: item.xp, valueTone: .lime, subtitle: item.detail)
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 10)
            }
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private extension View {
    /// Rises into place once `on` is true; fades only with Reduce Motion.
    func rise(_ on: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 18)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85).delay(delay),
                       value: on)
    }
}

// MARK: - Host

/// The Cut win screen with the legacy win screen's behaviour: the barbell reward feedback,
/// lucky bonus and plate haptics, the share sheet, the full screen barbell moment before
/// dismissing, and the dismiss itself.
struct CutWinScreen: View {
    let summary: RewardSummary
    let workout: CompletedWorkout?
    let onDismiss: () -> Void

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @State private var showingSharePost = false
    @State private var showBarbellMoment = false
    @State private var didStart = false

    private var fullScreenBarbellPlate: EarnedPlateInfo? { summary.rewardQueue.fullScreenPlate }

    private var model: CutWinModel {
        CutWinLogic.model(summary: summary, workout: workout, unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg,
                          tierName: { id in PlateTier.all.first { $0.id == id }?.name })
    }

    var body: some View {
        CutWinView(
            model: model,
            continueTitle: fullScreenBarbellPlate == nil || showBarbellMoment ? "Continue" : "See your barbell",
            actions: CutWinActions(
                share: { showingSharePost = true },
                proceed: {
                    if fullScreenBarbellPlate != nil && !showBarbellMoment {
                        withAnimation(.easeInOut(duration: 0.3)) { showBarbellMoment = true }
                    } else {
                        onDismiss()
                    }
                }
            )
        )
        .modifier(CutWinStatusBar())
        .sheet(isPresented: $showingSharePost) {
            if let workout {
                PostCreationView(workout: workout)
            }
        }
        .fullScreenCover(isPresented: $showBarbellMoment) {
            if !summary.earnedPlates.isEmpty {
                BarbellMomentView(plates: summary.earnedPlates) {
                    showBarbellMoment = false
                    DispatchQueue.main.async { onDismiss() }
                }
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            playFeedback()
        }
    }

    /// The legacy reveal's feedback, at its times: the barbell reward first, the lucky bonus,
    /// a heavy tap per plate, and the cosmetic feedback per unlocked skin.
    private func playFeedback() {
        switch summary.rewardQueue.primary?.kind {
        case .tierUp: BarbellProgressService.shared.playTierUpFeedback()
        case .cosmeticUnlock: BarbellProgressService.shared.playCosmeticEquipFeedback()
        case .newPlate: BarbellProgressService.shared.playClinkHaptic()
        case .setBonus, .personalRecord, .agingMilestone, nil: break
        }
        let baseDelay = summary.gotLuckyBonus ? 0.3 : 0.0
        if summary.gotLuckyBonus {
            Haptics.heavy()
            DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.4) { Haptics.medium() }
        }
        let plateStart = baseDelay + 1.1
        for index in summary.earnedPlates.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + plateStart + Double(index) * 0.25) { Haptics.heavy() }
        }
        let skins = ([summary.rewardQueue.primary].compactMap { $0 } + summary.rewardQueue.compactEvents)
            .filter { $0.kind == .cosmeticUnlock }
        for _ in skins {
            BarbellProgressService.shared.playCosmeticEquipFeedback()
        }
    }
}

/// Dark status bar content over the lime field while the win screen is up (iOS 27, Train tab),
/// restoring what the Train tab asked for when it goes.
private struct CutWinStatusBar: ViewModifier {
    @State private var previous = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                previous = CutTrainStatusBar.shared.wantsDarkContent
                CutTrainStatusBar.shared.wantsDarkContent = true
            }
            .onDisappear { CutTrainStatusBar.shared.wantsDarkContent = previous }
    }
}

#if DEBUG
enum CutWinFixtures {
    static let workout: CompletedWorkout = {
        let start = Date(timeIntervalSince1970: 1_794_312_000)
        let sets = (0..<6).map { _ in
            SetInput(reps: 6, weight: 85, isCompleted: true)
        }
        let entries = (0..<3).map { index in
            WorkoutEntry(exerciseID: "fixture-\(index)", exerciseName: ["Bench Press", "Overhead Press", "Row"][index],
                         muscleGroups: [], sets: sets)
        }
        return CompletedWorkout(date: start.addingTimeInterval(52 * 60 + 8), startedAt: start, entries: entries)
    }()

    static func summary(prCount: Int, plates: [EarnedPlateInfo]) -> RewardSummary {
        RewardSummary(
            xp: 240, coins: 0, levelUpTo: nil, streakOld: 5, streakNew: 5, hitStreakMilestone: false,
            unlockedAchievements: [], prCount: prCount, newExerciseCount: 0,
            xpSnapshot: XPSnapshot(beforeXP: 2340, beforeLevel: 14, beforeFloor: 2000, beforeCeiling: 3000,
                                   afterXP: 2580, afterLevel: 14, afterFloor: 2000, afterCeiling: 3000),
            xpLineItems: [
                XPLineItem(id: "a", source: "Strength Day", xp: 150, icon: "dumbbell", detail: nil),
                XPLineItem(id: "b", source: "PR", xp: 90, icon: "crown", detail: "Bench Press")
            ],
            streakFrozen: false, streakBonusXP: 0, earnedPlates: plates)
    }

    static let plate = EarnedPlateInfo(tierID: 3, weightKg: 20, engravingText: "", earnedByEvent: "workout")

    static var withRecordAndPlate: CutWinModel {
        CutWinLogic.model(summary: summary(prCount: 1, plates: [plate]), workout: workout, unit: .kg,
                          tierName: { _ in "Bumper" })
    }

    static var plain: CutWinModel {
        CutWinLogic.model(summary: summary(prCount: 0, plates: []), workout: workout, unit: .kg)
    }
}

#Preview("Cut win") {
    CutWinView(model: CutWinFixtures.withRecordAndPlate)
}
#endif
