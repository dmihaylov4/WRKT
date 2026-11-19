//
//  CutYearReviewView.swift
//  WRKT
//
//  Year in review in the Cut language: a lime card that pops up over the app, a deck of dark
//  stat cards that each set one number against something from the real world, and a steel
//  award plaque to keep and share (CutYearAwardView.swift). CutYearReviewOverlay sits at the
//  app root; CutYearReviewCenter decides when it shows.
//

import SwiftUI

// MARK: - Presentation

/// What the app root overlay shows. Debug triggers and the first-open check both go through here.
@MainActor
@Observable
final class CutYearReviewCenter {
    static let shared = CutYearReviewCenter()

    private(set) var presented: CutYearReviewStats?
    /// The deck's first card: 0, the opening card, except for Debug screenshots.
    private(set) var startStep = 0
    @ObservationIgnored private var marksSeen = false

    func present(_ stats: CutYearReviewStats, marksSeen: Bool = false, startStep: Int = 0) {
        self.marksSeen = marksSeen
        self.startStep = startStep
        presented = stats
    }

    /// "Later" leaves the year unseen, so it pops up again on the next launch.
    func dismiss(seen: Bool) {
        if seen, marksSeen, let year = presented?.year {
            UserDefaults.standard.set(year, forKey: CutYearReviewLogic.seenYearKey)
        }
        presented = nil
    }

    /// Shows the pop-up when it is due: Cut is on, the date is in the window (or the Debug
    /// force flag is set), this year was not seen yet and there is enough to show.
    func presentIfDue(store: WorkoutStoreV2, now: Date = .now) {
        guard DS.Redesign.cutEnabled, presented == nil, store.currentWorkout == nil else { return }
        let defaults = UserDefaults.standard
        let forced = defaults.bool(forKey: CutYearReviewLogic.forceNextLaunchKey)
        let calendar = Calendar.current
        guard let year = forced ? calendar.component(.year, from: now) : CutYearReviewLogic.reviewYear(now: now) else { return }
        let stats = CutYearReviewLogic.stats(year: year, workouts: store.completedWorkouts, runs: store.runSummaries, now: now)
        let seenYear = forced ? nil : defaults.object(forKey: CutYearReviewLogic.seenYearKey) as? Int
        guard CutYearReviewLogic.shouldAutoPresent(stats: stats, seenYear: seenYear) else { return }
        defaults.removeObject(forKey: CutYearReviewLogic.forceNextLaunchKey)
        present(stats, marksSeen: true)
    }
}

/// App root overlay: empty until the center presents a year.
struct CutYearReviewOverlay: View {
    @State private var center = CutYearReviewCenter.shared
    @Environment(\.dependencies) private var deps
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    var body: some View {
        ZStack {
            if let stats = center.presented {
                CutYearReviewDeck(stats: stats, unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg,
                                  startStep: center.startStep) { seen in
                    center.dismiss(seen: seen)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: center.presented != nil)
        .task {
            #if DEBUG
            // Screenshots: `-CutYearAwardDemo` opens the award card with the sample year.
            if ProcessInfo.processInfo.arguments.contains("-CutYearAwardDemo") {
                // After the launch animation, so the award's arrival can be seen.
                try? await Task.sleep(for: .seconds(1.5))
                let stats = CutYearReviewStats.sample(year: Calendar.current.component(.year, from: .now))
                center.present(stats, startStep: CutYearReviewLogic.cards(for: stats).count + 1)
                return
            }
            #endif
            // After the store has loaded and the first screen has settled.
            try? await Task.sleep(for: .seconds(1.5))
            center.presentIfDue(store: deps.workoutStore)
        }
    }
}

// MARK: - Deck

struct CutYearReviewDeck: View {
    let stats: CutYearReviewStats
    let unit: WeightUnit
    /// Called with whether the year was opened (false for "Later").
    let onClose: (Bool) -> Void

    /// 0 is the opening card, then one step per stat card, then the share card.
    @State private var step: Int
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(stats: CutYearReviewStats, unit: WeightUnit, startStep: Int = 0, onClose: @escaping (Bool) -> Void) {
        self.stats = stats
        self.unit = unit
        self.onClose = onClose
        _step = State(initialValue: startStep)
    }

    private var cards: [CutYearReviewCard] { CutYearReviewLogic.cards(for: stats) }
    private var lastStep: Int { cards.count + 1 }

    var body: some View {
        ZStack {
            backdrop
            Group {
                if step == 0 {
                    CutYearReviewIntroCard(stats: stats, unit: unit,
                                           open: { go(to: 1) }, later: { onClose(false) })
                } else if step <= cards.count {
                    let card = cards[step - 1]
                    CutYearReviewStatCard(card: card, stats: stats, unit: unit, index: step - 1, total: cards.count + 1,
                                          next: { go(to: step + 1) }, close: { onClose(true) })
                } else {
                    CutYearAwardStep(stats: stats, unit: unit, cards: cards, done: { onClose(true) })
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : cardTransition)
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)
        }
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard step > 0, abs(value.translation.width) > abs(value.translation.height) else { return }
            if value.translation.width < -50, step < lastStep { go(to: step + 1) }
            if value.translation.width > 50, step > 1 { go(to: step - 1) }
        })
        .environment(\.colorScheme, .dark)
        .accessibilityAddTraits(.isModal)
        .task {
            // Builds the 3D award while the cards play, so it is ready on the last one.
            guard CutYearAwardRendering.usesObject() else { return }
            CutYearAwardStageCache.shared.prepare(CutYearAwardLogic.content(stats: stats, unit: unit, cards: cards))
        }
        .onDisappear { CutYearAwardStageCache.shared.release() }
    }

    /// The opening card floats over the dimmed app; the deck gets its own black screen. The
    /// award at the end stands on plain black, without the dark lime field.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(step == 0 ? 0.78 : 1)
            if step > 0, step < lastStep {
                CutCornerShape.field
                    .fill(Color(hex: "#1C2000"))
                    .frame(height: 320)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.3), value: step == 0)
        .animation(.easeOut(duration: 0.3), value: step == lastStep)
    }

    private var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .modifier(active: CutYearReviewFling(direction: forward ? -1 : 1, progress: 1),
                               identity: CutYearReviewFling(direction: forward ? -1 : 1, progress: 0)))
    }

    private func go(to target: Int) {
        forward = target > step
        Haptics.light()
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.82)) {
            step = target
        }
    }
}

/// A card leaving the deck: off to one side with a little rotation.
private struct CutYearReviewFling: ViewModifier {
    let direction: CGFloat
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(Double(direction * progress) * 10))
            .offset(x: direction * progress * 460, y: progress * 30)
            .opacity(1 - Double(progress) * 0.4)
    }
}

// MARK: - Card shell

/// A card with the cut top leading corner and a second card peeking out behind it.
private struct CutYearReviewCardShell<Content: View>: View {
    let fill: Color
    var tilt: Double = 4
    var showsBack = true
    @ViewBuilder let content: () -> Content

    private var shape: CutCornerShape { CutCornerShape(corner: .topLeading, cut: .points(40)) }

    var body: some View {
        content()
            .padding(EdgeInsets(top: 28, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(shape.fill(fill))
            .background {
                if showsBack {
                    Rectangle()
                        .fill(Color(hex: "#2C2C2E"))
                        .rotationEffect(.degrees(tilt))
                        .offset(x: tilt > 0 ? 8 : -8, y: 10)
                        .accessibilityHidden(true)
                }
            }
    }
}

// MARK: - Opening card

private struct CutYearReviewIntroCard: View {
    let stats: CutYearReviewStats
    let unit: WeightUnit
    let open: () -> Void
    let later: () -> Void

    @State private var landed = false
    @State private var backShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            CutYearReviewCardShell(fill: DS.Cut.Colors.lime, showsBack: backShown) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your year is ready")
                        .cutFont(.title)
                        .padding(.leading, 24)
                    // The year is shown as is. It used to tick up from the year before, which
                    // read as the wrong year loading first.
                    Text(String(stats.year))
                        .font(DS.Cut.Typography.condensed(size: 168, monospacedDigits: true))
                        .tracking(-3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .padding(.top, 36)
                    Text(CutYearReviewLogic.teaser(stats: stats, unit: unit))
                        .font(DS.Cut.Typography.condensed(size: 28, weight: .bold, relativeTo: .title2))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    Button("Open your year", action: open)
                        .buttonStyle(CutYearReviewInkPillStyle())
                        .padding(.top, 36)
                }
                .foregroundStyle(DS.Cut.Colors.ink)
            }
            Button("Later", action: later)
                .font(DS.Cut.Typography.font(.buttonCompact))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .frame(minWidth: 88, minHeight: 48)
        }
        // Rises from the bottom and settles with a slight overshoot.
        .rotationEffect(.degrees(landed || reduceMotion ? 0 : -6))
        .offset(y: landed || reduceMotion ? 0 : 900)
        .onAppear {
            guard !reduceMotion else {
                landed = true
                backShown = true
                return
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.1)) { landed = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.55)) { backShown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { Haptics.soft() }
        }
    }
}

/// Ink pill on lime: the opening card's one action.
private struct CutYearReviewInkPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Cut.Typography.actionPill)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(DS.Cut.Colors.lime)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: DS.Cut.Metrics.actionPillHeight)
            .background(Capsule().fill(DS.Cut.Colors.ink))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Stat card

private struct CutYearReviewStatCard: View {
    let card: CutYearReviewCard
    let stats: CutYearReviewStats
    let unit: WeightUnit
    let index: Int
    let total: Int
    let next: () -> Void
    let close: () -> Void

    /// 0 nothing yet, 1 the drawing builds, 2 the number counts up, 3 the comparison lands.
    @State private var stage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var comparison: CutYearReviewComparison {
        CutYearReviewLogic.comparison(card, stats: stats, unit: unit)
    }

    var body: some View {
        CutYearReviewCardShell(fill: DS.Cut.Colors.darkField, tilt: index.isMultiple(of: 2) ? 4 : -4) {
            VStack(alignment: .leading, spacing: 0) {
                header
                CutYearReviewArt(card: card, stats: stats, built: stage >= 1)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
                number
                    .padding(.top, 20)
                CutHeroText(comparison.headline, hero: .exercise, minimumScaleFactor: 0.5)
                    .lineLimit(nil)
                    .padding(.top, 8)
                    .opacity(stage >= 3 ? 1 : 0)
                    .offset(y: stage >= 3 ? 0 : 14)
                Text(comparison.detail)
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .opacity(stage >= 3 ? 1 : 0)
                footer
                    .padding(.top, 28)
            }
            .foregroundStyle(DS.Cut.Colors.textPrimary)
        }
        .task { await play() }
    }

    private var header: some View {
        HStack {
            Text(card.label)
                .cutFont(.title)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .padding(.leading, 24)
            Spacer(minLength: 12)
            Button("Close", systemImage: "xmark", action: close)
                .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: 44))
        }
    }

    private var number: some View {
        let target = value
        return CutYearReviewCountUp(value: stage >= 2 ? target : 0) { format($0) }
            .font(DS.Cut.Typography.numeral(.rest))
            .foregroundStyle(DS.Cut.Colors.lime)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .animation(reduceMotion ? nil : .easeOut(duration: 1.1), value: stage >= 2)
            .accessibilityLabel(Text(CutYearReviewLogic.valueText(card, stats: stats, unit: unit)))
    }

    private var value: Double {
        switch card {
        case .lifted: stats.liftedKg
        case .distance: stats.distanceKm
        case .time: stats.trainedSeconds
        case .streak: Double(stats.longestStreakWeeks)
        }
    }

    private func format(_ value: Double) -> String {
        switch card {
        case .lifted: CutYearReviewLogic.liftedText(kg: value, unit: unit)
        case .distance: CutYearReviewLogic.distanceText(km: value)
        case .time: CutYearReviewLogic.hoursText(seconds: value)
        case .streak: CutYearReviewLogic.weeksText(Int(value.rounded()))
        }
    }

    private var footer: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { segment in
                    Rectangle()
                        .fill(segment <= index ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.segmentTrack)
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Card \(index + 1) of \(total)")
            Button("Next", action: next)
                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3))
                .textCase(.uppercase)
                .foregroundStyle(DS.Cut.Colors.lime)
                .padding(.horizontal, 26)
                .frame(minHeight: 48)
                .overlay(Capsule().strokeBorder(DS.Cut.Colors.lime, lineWidth: 2))
                .contentShape(Capsule())
        }
    }

    private func play() async {
        guard !reduceMotion else {
            stage = 3
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.3)) { stage = 1 }
        try? await Task.sleep(for: .milliseconds(650))
        stage = 2
        try? await Task.sleep(for: .milliseconds(1150))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { stage = 3 }
        Haptics.rigid()
    }
}

/// Text that counts between values when its value animates.
private struct CutYearReviewCountUp: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

// MARK: - Drawings

private struct CutYearReviewArt: View {
    let card: CutYearReviewCard
    let stats: CutYearReviewStats
    let built: Bool

    var body: some View {
        switch card {
        case .lifted:
            if let (rung, count) = CutYearReviewLadder.rung(forKg: stats.liftedKg) {
                switch rung.art {
                case .wheel: CutYearReviewWheel(built: built)
                case .symbol(let name): CutYearReviewObjects(count: count, symbol: name, built: built)
                case .blocks: CutYearReviewObjects(count: count, symbol: nil, built: built)
                }
            } else {
                CutYearReviewObjects(count: 1, symbol: "dumbbell.fill", built: built)
            }
        case .distance:
            let marathons = stats.distanceKm / CutYearReviewLogic.marathonKm
            CutYearReviewBlocks(amount: marathons, columns: 4, slanted: true, built: built)
        case .time:
            CutYearReviewDays(days: stats.trainedSeconds / 86_400, built: built)
        case .streak:
            CutYearReviewWeeks(weeks: stats.activeWeeks, streakStart: stats.streakStartWeek,
                               streakLength: stats.longestStreakWeeks, built: built)
        }
    }
}

/// The Riesenrad: the rim draws itself, then the wheel turns slowly with upright gondolas.
private struct CutYearReviewWheel: View {
    let built: Bool

    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gondolas = 15

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width / 2, proxy.size.height * 0.42)
            let centre = CGPoint(x: proxy.size.width / 2, y: radius + 8)
            ZStack {
                // The A-frame it stands on.
                Path { path in
                    path.move(to: centre)
                    path.addLine(to: CGPoint(x: centre.x - radius * 0.58, y: proxy.size.height))
                    path.move(to: centre)
                    path.addLine(to: CGPoint(x: centre.x + radius * 0.58, y: proxy.size.height))
                    path.move(to: CGPoint(x: centre.x - radius * 0.95, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: centre.x + radius * 0.95, y: proxy.size.height))
                }
                .stroke(Color(hex: "#8E8E93"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .opacity(built ? 1 : 0)

                ZStack {
                    Circle()
                        .trim(from: 0, to: built ? 1 : 0)
                        .stroke(DS.Cut.Colors.lime, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: built ? 1 : 0)
                        .stroke(DS.Cut.Colors.lime, lineWidth: 1.5)
                        .padding(radius * 0.26)
                    ForEach(0..<8, id: \.self) { spoke in
                        Rectangle()
                            .fill(DS.Cut.Colors.lime)
                            .frame(width: radius * 2, height: 1.5)
                            .rotationEffect(.degrees(Double(spoke) * 22.5))
                            .opacity(built ? 1 : 0)
                    }
                    ForEach(0..<gondolas, id: \.self) { index in
                        let angle = Double(index) / Double(gondolas) * 2 * .pi
                        Rectangle()
                            .fill(DS.Cut.Colors.textPrimary)
                            .frame(width: 14, height: 10)
                            // Counter-turned, so the cabins stay upright while the wheel turns.
                            .rotationEffect(.degrees(turning ? -360 : 0))
                            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                            .opacity(built ? 1 : 0)
                            .animation(.easeOut(duration: 0.2).delay(0.5 + Double(index) * 0.04), value: built)
                    }
                    Circle()
                        .fill(DS.Cut.Colors.lime)
                        .frame(width: 16, height: 16)
                }
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.degrees(turning ? 360 : 0))
                .position(centre)
            }
            .animation(.easeInOut(duration: 0.9), value: built)
        }
        .onChange(of: built, initial: true) { _, isBuilt in
            guard isBuilt, !reduceMotion else { return }
            withAnimation(.linear(duration: 48).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

/// One glyph or block per object, up to twelve, appearing one after another.
private struct CutYearReviewObjects: View {
    let count: Int
    let symbol: String?
    let built: Bool

    var body: some View {
        let shown = min(max(1, count), 12)
        let columns = shown == 1 ? 1 : shown <= 4 ? 2 : shown <= 9 ? 3 : 4
        let rows = Int((Double(shown) / Double(columns)).rounded(.up))
        GeometryReader { proxy in
            let side = min(proxy.size.width / CGFloat(columns), proxy.size.height / CGFloat(rows)) - 10
            VStack(spacing: 10) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < shown {
                                object(side: side)
                                    .opacity(built ? 1 : 0)
                                    .scaleEffect(built ? 1 : 0.6)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.08), value: built)
                            }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func object(side: CGFloat) -> some View {
        if let symbol {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(DS.Cut.Colors.lime)
                .frame(width: side, height: min(side, 150))
        } else {
            SlantedSegmentShape(slant: side * 0.3)
                .fill(DS.Cut.Colors.lime)
                .frame(width: side * 1.3, height: min(side * 0.7, 110))
                .frame(width: side, height: min(side, 150))
        }
    }
}

/// A grid of blocks, each standing for one unit, the last one part filled.
private struct CutYearReviewBlocks: View {
    let amount: Double
    let columns: Int
    let slanted: Bool
    let built: Bool

    var body: some View {
        let count = min(max(1, Int(amount.rounded(.up))), 24)
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < count {
                            block(fraction: min(max(amount - Double(index), 0), 1), index: index)
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
        .frame(maxHeight: CGFloat(rows) * 64)
    }

    private func block(fraction: Double, index: Int) -> some View {
        let shape = SlantedSegmentShape(slant: slanted ? 18 : 0)
        return shape
            .fill(DS.Cut.Colors.limeTrack)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    DS.Cut.Colors.lime
                        .frame(width: built ? proxy.size.width * fraction : 0)
                        .animation(.easeOut(duration: 0.25).delay(Double(index) * 0.07), value: built)
                }
            }
            .clipShape(shape)
    }
}

/// Day columns that fill from the bottom.
private struct CutYearReviewDays: View {
    let days: Double
    let built: Bool

    var body: some View {
        let count = min(max(1, Int(days.rounded(.up))), 8)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    let fraction = min(max(days - Double(index), 0), 1)
                    DS.Cut.Colors.limeTrack
                        .overlay(alignment: .bottom) {
                            GeometryReader { proxy in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    DS.Cut.Colors.lime
                                        .frame(height: built ? proxy.size.height * fraction : 0)
                                }
                                .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.12), value: built)
                            }
                        }
                        .clipShape(CutCornerShape(corner: .topLeading, cut: .points(14)))
                }
            }
            HStack(spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    Text(count <= 5 ? "Day \(index + 1)" : "\(index + 1)")
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// The year as week blocks: the longest streak lights up left to right.
private struct CutYearReviewWeeks: View {
    let weeks: [Bool]
    let streakStart: Int?
    let streakLength: Int
    let built: Bool

    private let columns = 13

    var body: some View {
        let rows = Int((Double(max(weeks.count, 1)) / Double(columns)).rounded(.up))
        VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < weeks.count {
                            let inStreak = streakStart.map { index >= $0 && index < $0 + streakLength } ?? false
                            Rectangle()
                                .fill(color(active: weeks[index], lit: inStreak && built))
                                .animation(.easeOut(duration: 0.2).delay(inStreak ? Double(index - (streakStart ?? 0)) * 0.09 : 0),
                                           value: built)
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
        .frame(maxHeight: CGFloat(rows) * 46)
    }

    private func color(active: Bool, lit: Bool) -> Color {
        if lit { return DS.Cut.Colors.lime }
        return active ? Color(hex: "#8E8E93") : Color(hex: "#3A3A3C")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Year in review") {
    CutYearReviewDeck(stats: .sample(year: 2026), unit: .kg) { _ in }
        .background(DS.Cut.Colors.background)
}
#endif
