//
//  WinScreen.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 13.10.25.
//

// WinScreen.swift
import SwiftUI
import Combine
import RealityKit


struct WinScreenOverlay: View {
    @StateObject private var coord = WinScreenCoordinator.shared
    var body: some View {
        Group {
            if let s = coord.summary {
                WinScreenView(summary: s) {
                    WinScreenCoordinator.shared.dismissCurrent()
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(1000)
            }
        }
        .allowsHitTesting(coord.summary != nil)
    }
}

// WinScreenView.swift
import SwiftUI

struct WinScreenView: View {
    let summary: RewardSummary
    let onDismiss: () -> Void
    @State private var animate = false
    @State private var showingSharePost = false

    // Staggered reveal state
    @State private var showHeader = false
    @State private var showPills = false
    @State private var showXPCard = false
    @State private var revealedLineItems: Set<String> = []
    @State private var revealedHighlights: Set<String> = []
    @State private var showButtons = false
    @State private var didStartReveal = false

    // Lucky bonus animation state
    @State private var showLuckyBanner = false
    @State private var luckyPulse = false

    // Plate reveal state
    @State private var revealedPlates: [Int] = []   // indices into summary.earnedPlates revealed so far
    @State private var showBarbellMoment = false

    private var fullScreenBarbellPlate: EarnedPlateInfo? {
        summary.rewardQueue.fullScreenPlate
    }

    private var title: String {
        if summary.gotLuckyBonus { return "LUCKY!" }
        if !skinUnlockEvents.isEmpty { return "New Reward!" }
        if summary.newExerciseCount > 0 { return "You completed a new exercise!" }
        if summary.prCount > 0 { return "Personal Record!" }
        if summary.levelUpTo != nil { return "Level Up!" }
        return "You completed a workout!"
    }

    private var subtitle: String? {
        var bits: [String] = []
        if summary.gotLuckyBonus { bits.append("\(formatMultiplier(summary.bonusMultiplier)) XP Bonus!") }
        if summary.streakNew > summary.streakOld { bits.append("Streak \(summary.streakNew)") }
        if summary.unlockedAchievements.count > 0 { bits.append("\(summary.unlockedAchievements.count) new achievement\(summary.unlockedAchievements.count == 1 ? "" : "s")") }
        if summary.newExerciseCount > 0 { bits.append("\(summary.newExerciseCount) new exercise\(summary.newExerciseCount == 1 ? "" : "s")") }
        if summary.prCount > 0 { bits.append("\(summary.prCount) PR\(summary.prCount == 1 ? "" : "s")") }
        return bits.isEmpty ? nil : bits.joined(separator: " • ")
    }

    private var skinUnlockEvents: [BarbellRewardEvent] {
        ([summary.rewardQueue.primary].compactMap { $0 } + summary.rewardQueue.compactEvents)
            .filter { $0.kind == .cosmeticUnlock }
    }

    private func formatMultiplier(_ m: Double) -> String {
        if m == 1.5 { return "1.5x" }
        if m == 2.0 { return "2x" }
        if m == 3.0 { return "3x" }
        return "\(Int(m))x"
    }

    private var highlights: [Highlight] {
        var items: [Highlight] = []
        if summary.newExerciseCount > 0 {
            items.append(.init(id: "new-exercise-\(summary.newExerciseCount)", icon: "star.fill", label: "\(summary.newExerciseCount) new exercise\(summary.newExerciseCount == 1 ? "" : "s") unlocked"))
        }
        if summary.prCount > 0 {
            items.append(.init(id: "pr-\(summary.prCount)", icon: "crown.fill", label: "\(summary.prCount) new PR\(summary.prCount == 1 ? "" : "s")"))
        }
        if let lvl = summary.levelUpTo {
            items.append(.init(id: "level-\(lvl)", icon: "rosette", label: "Reached level \(lvl)"))
        }
        if summary.streakNew > summary.streakOld {
            let milestone = summary.hitStreakMilestone ? " (milestone!)" : ""
            items.append(.init(id: "streak-\(summary.streakNew)-\(summary.hitStreakMilestone)", icon: "flame.fill", label: "Streak \(summary.streakNew)\(milestone)"))
        }
        if !summary.unlockedAchievements.isEmpty {
            // Show up to 3, then "+N more…"
            let pretty = summary.unlockedAchievements.map(humanize)
            let head = pretty.prefix(3)
            head.forEach { items.append(.init(id: "achievement-\($0)", icon: "medal.fill", label: $0)) }
            let remaining = pretty.count - head.count
            if remaining > 0 { items.append(.init(id: "achievement-more-\(remaining)", icon: "ellipsis.circle", label: "+\(remaining) more achievements")) }
        }
        return items
    }

    var body: some View {
        ZStack {
            // Solid black background first (ensures full opacity)
            Color.black
                .ignoresSafeArea()

            // Background - subtle golden tint for lucky bonus
            if summary.gotLuckyBonus {
                LinearGradient(
                    colors: [
                        Color.black,
                        DS.Theme.accent.opacity(luckyPulse ? 0.08 : 0.025),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: luckyPulse)
            }

            VStack(spacing: 0) {
                // Fixed header section
                VStack(spacing: 12) {
                    // Lucky Banner (appears first if bonus)
                    if summary.gotLuckyBonus && showLuckyBanner {
                        LuckyBonusBanner(multiplier: summary.bonusMultiplier)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // Top icon & title - more compact
                    if showHeader {
                        Image("reward-angular-spark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .foregroundStyle(DS.Theme.accent)
                            .scaleEffect(animate ? 1 : 0.6)
                            .padding(.top, summary.gotLuckyBonus ? 8 : 20)
                            .transition(.scale.combined(with: .opacity))

                        Text(title)
                            .font(.system(.title, weight: .bold))
                            .foregroundStyle(summary.gotLuckyBonus ? DS.Theme.accent : .white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))

                        if let sub = subtitle {
                            Text(sub)
                                .dsFont(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .transition(.opacity)
                        }
                    }

                    // Totals row - staggered
                    if showPills {
                        HStack(spacing: 8) {
                            if summary.xp > 0 {
                                Pill("XP +\(summary.xp)", isLucky: summary.gotLuckyBonus)
                            }
                            if summary.coins > 0 { Pill("Coins +\(summary.coins)") }
                            if let lvl = summary.levelUpTo { Pill("Level \(lvl)") }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Scrollable content area (only this part scrolls if needed)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Unified XP & Rewards Card - with staggered reveal
                        if showXPCard {
                            if let snapshot = summary.xpSnapshot, !summary.xpLineItems.isEmpty {
                                XPGainCardStaggered(
                                    snapshot: snapshot,
                                    lineItems: summary.xpLineItems,
                                    highlights: highlights,
                                    humanize: humanize,
                                    revealedLineItems: $revealedLineItems,
                                    revealedHighlights: $revealedHighlights,
                                    isLuckyBonus: summary.gotLuckyBonus
                                )
                                .transition(.opacity.combined(with: .scale))
                            } else if !highlights.isEmpty {
                                // If no XP card, show highlights standalone
                                HighlightsOnlyCard(highlights: highlights)
                            }
                        }

                        // Plate reveal cards
                        if !summary.earnedPlates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                if !revealedPlates.isEmpty {
                                    Text(summary.rewardQueue.compactSummary.map { "New Plates, \($0)" } ?? "New Plates")
                                        .dsFont(.caption, weight: .semibold)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .padding(.top, 4)
                                }
                                ForEach(Array(summary.earnedPlates.enumerated()), id: \.offset) { index, plate in
                                    if revealedPlates.contains(index) {
                                        PlateRevealCard(plate: plate)
                                            .transition(.asymmetric(
                                                insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                    }
                                }
                            }
                        }

                        if !skinUnlockEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("New Skins")
                                    .dsFont(.caption, weight: .semibold)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.top, 4)

                                ForEach(skinUnlockEvents) { event in
                                    SkinRevealCard(event: event)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Fixed buttons at bottom
                if showButtons {
                    VStack(spacing: 12) {
                        // Share Workout Button
                        if WinScreenCoordinator.shared.currentWorkout != nil {
                            Button {
                                Haptics.light()
                                showingSharePost = true
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share Workout")
                                }
                                .dsFont(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                            }
                        .background(.white.opacity(0.15))
                        .foregroundStyle(.white)
                            .clipShape(ChamferedRectangle(.medium))
                            .overlay(
                                ChamferedRectangle(.medium)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Continue Button
                        Button {
                            Haptics.light()
                            if fullScreenBarbellPlate != nil && !showBarbellMoment {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showBarbellMoment = true
                                }
                            } else {
                                onDismiss()
                            }
                        } label: {
                            Text(fullScreenBarbellPlate == nil || showBarbellMoment ? "Continue" : "See Your Barbell")
                                .dsFont(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                        .background(DS.Theme.accent)
                        .foregroundStyle(.black)
                        .clipShape(ChamferedRectangle(.medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.black.opacity(0.3))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showingSharePost) {
            if let workout = WinScreenCoordinator.shared.currentWorkout {
                PostCreationView(workout: workout)
            }
        }
        .fullScreenCover(isPresented: $showBarbellMoment) {
            if !summary.earnedPlates.isEmpty {
                BarbellMomentView(plates: summary.earnedPlates, onDismiss: onDismiss)
            }
        }
        .task {
            guard !didStartReveal else { return }
            didStartReveal = true
            playPrimaryBarbellRewardFeedback()
            try? await Task.sleep(for: .milliseconds(80))
            startStaggeredReveal()
        }
    }

    private func playPrimaryBarbellRewardFeedback() {
        switch summary.rewardQueue.primary?.kind {
        case .tierUp:
            BarbellProgressService.shared.playTierUpFeedback()
        case .cosmeticUnlock:
            BarbellProgressService.shared.playCosmeticEquipFeedback()
        case .newPlate:
            BarbellProgressService.shared.playClinkHaptic()
        case .setBonus, .personalRecord, .agingMilestone, nil:
            break
        }
    }

    // MARK: - Staggered Reveal Animation
    private func startStaggeredReveal() {
        let baseDelay: Double = summary.gotLuckyBonus ? 0.3 : 0.0

        // Lucky banner first (if applicable)
        if summary.gotLuckyBonus {
            Haptics.heavy()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showLuckyBanner = true
                luckyPulse = true
            }
        }

        // Header (icon + title)
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.1) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showHeader = true
                animate = true
            }
        }

        // Pills (XP, coins, level)
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.4) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showPills = true
            }
            if summary.gotLuckyBonus {
                Haptics.medium()
            }
        }

        // XP Card
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.6) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showXPCard = true
            }
        }

        // Stagger line items reveal (one every 150ms)
        for (index, item) in summary.xpLineItems.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.9 + Double(index) * 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    _ = revealedLineItems.insert(item.id)
                }
            }
        }

        // Stagger highlights reveal
        let highlightStartDelay = baseDelay + 0.9 + Double(summary.xpLineItems.count) * 0.15 + 0.2
        for (index, highlight) in highlights.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + highlightStartDelay + Double(index) * 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    _ = revealedHighlights.insert(highlight.id)
                }
            }
        }

        // Stagger plate reveal cards after highlights
        let plateStartDelay = highlightStartDelay + Double(highlights.count) * 0.15 + 0.2
        for (index, _) in summary.earnedPlates.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + plateStartDelay + Double(index) * 0.25) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    revealedPlates.append(index)
                }
                Haptics.heavy()
            }
        }

        // Buttons appear last
        let totalItems = summary.xpLineItems.count + highlights.count + summary.earnedPlates.count + skinUnlockEvents.count
        let buttonsDelay = baseDelay + 0.9 + Double(totalItems) * 0.15 + 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + buttonsDelay) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showButtons = true
            }
        }
    }

    private func Pill(_ text: String, isLucky: Bool = false) -> some View {
        Text(text)
            .dsFont(.subheadline, weight: .semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isLucky ? DS.Theme.accent.opacity(0.16) : .white.opacity(0.10), in: ChamferedRectangle(.small))
            .overlay(ChamferedRectangle(.small).stroke(isLucky ? DS.Theme.accent.opacity(0.45) : .white.opacity(0.15), lineWidth: 1))
            .foregroundStyle(isLucky ? DS.Theme.accent : .white)
    }

    private func humanize(_ raw: String) -> String {
        // Convert snake_case or kebab-case to Title Case
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { String($0).capitalized }  // Convert to String and capitalize
            .joined(separator: " ")
    }

    fileprivate struct Highlight: Identifiable {
        let id: String
        let icon: String
        let label: String
    }
}

// MARK: - Plate Reveal Card

private struct PlateRevealCard: View {
    let plate: EarnedPlateInfo

    private var tier: PlateTier? {
        PlateTier.all.first { $0.id == plate.tierID }
    }

    private var tierName: String {
        tier?.name ?? "Plate"
    }

    private var rarityLabel: String {
        tier?.rarity.rawValue ?? ""
    }

    private var rarityColor: Color {
        tier?.rarity.color ?? .white
    }

    var body: some View {
        HStack(spacing: 12) {
            RealityPlatePreview(plate: plate)
                .frame(width: 72, height: 58)
                .clipShape(ChamferedRectangle(.small))
                .overlay(ChamferedRectangle(.small).stroke(rarityColor.opacity(0.35), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tierName)
                        .dsFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(rarityLabel)
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(rarityColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(rarityColor.opacity(0.15), in: ChamferedRectangle(.small))
                }
                Text(plate.engravingText)
                    .dsFont(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)

            Image(systemName: "plus.circle.fill")
                .dsFont(.title3)
                .foregroundStyle(DS.Semantic.brand)
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.medium))
        .overlay(ChamferedRectangle(.medium).stroke(rarityColor.opacity(0.35), lineWidth: 1))
    }

}

private struct SkinRevealCard: View {
    let event: BarbellRewardEvent

    private var skin: BarSkin? {
        BarSkin.all.first { $0.id == 4 }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let skin {
                BarSkinPreviewTile(skin: skin)
                    .frame(width: 120, height: 40)
                    .clipShape(ChamferedRectangle(.small))
                    .overlay(ChamferedRectangle(.small).stroke(skin.rarity.color.opacity(0.35), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .dsFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(skin?.rarity.rawValue ?? "Epic")
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(skin?.rarity.color ?? DS.Semantic.brand)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((skin?.rarity.color ?? DS.Semantic.brand).opacity(0.15), in: ChamferedRectangle(.small))
                }

                Text("Exclusive bar skin - equip it in your Barbell")
                    .dsFont(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)

            Image(systemName: "plus.circle.fill")
                .dsFont(.title3)
                .foregroundStyle(DS.Semantic.brand)
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.medium))
        .overlay(ChamferedRectangle(.medium).stroke((skin?.rarity.color ?? DS.Semantic.brand).opacity(0.35), lineWidth: 1))
        .onAppear {
            BarbellProgressService.shared.playCosmeticEquipFeedback()
        }
    }
}

private struct RealityPlatePreview: View {
    let plate: EarnedPlateInfo

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(DS.Theme.cardBottom.opacity(0.55))
            PlateFaceView(
                tierID: plate.tierID,
                progressionTier: .iron,
                liftTypeID: plate.liftTypeID,
                weightKg: plate.weightKg
            )
            .padding(6)
        }
    }
}

// MARK: - Lucky Bonus Banner
private struct LuckyBonusBanner: View {
    let multiplier: Double
    @State private var shimmer = false

    private var multiplierText: String {
        if multiplier == 1.5 { return "1.5X" }
        if multiplier == 2.0 { return "2X" }
        if multiplier == 3.0 { return "3X" }
        return "\(Int(multiplier))X"
    }

    var body: some View {
        Text("\(multiplierText) BONUS!")
            .dsFont(.headline, weight: .black)
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    ChamferedRectangle(.medium)
                        .fill(DS.Theme.accent)

                    // Shimmer effect
                    ChamferedRectangle(.medium)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.4), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmer ? 100 : -100)
                        .mask(ChamferedRectangle(.medium))
                }
            )
            .shadow(color: DS.Theme.accent.opacity(0.35), radius: 10, x: 0, y: 0)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
    }
}

// MARK: - Highlights Only Card (fallback when no XP)
private struct HighlightsOnlyCard: View {
    let highlights: [WinScreenView.Highlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(highlights) { h in
                HStack(spacing: 8) {
                    Image(systemName: h.icon)
                        .dsFont(.caption, weight: .bold)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(DS.Theme.accent)
                    Text(h.label)
                        .dsFont(.caption, weight: .medium)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.vertical, 3)

                if h.id != highlights.last?.id {
                    Divider().background(.white.opacity(0.08))
                }
            }
        }
        .padding(14)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - XP Gain Card with Staggered Reveal
private struct XPGainCardStaggered: View {
    let snapshot: XPSnapshot
    let lineItems: [XPLineItem]
    let highlights: [WinScreenView.Highlight]
    let humanize: (String) -> String
    @Binding var revealedLineItems: Set<String>
    @Binding var revealedHighlights: Set<String>
    let isLuckyBonus: Bool

    @State private var progress: Double = 0
    @State private var displayLevel: Int
    @State private var displayXP: Int
    @State private var displayFloor: Int
    @State private var displayCeiling: Int

    init(snapshot: XPSnapshot, lineItems: [XPLineItem], highlights: [WinScreenView.Highlight],
         humanize: @escaping (String) -> String, revealedLineItems: Binding<Set<String>>,
         revealedHighlights: Binding<Set<String>>, isLuckyBonus: Bool) {
        self.snapshot = snapshot
        self.lineItems = lineItems
        self.highlights = highlights
        self.humanize = humanize
        self._revealedLineItems = revealedLineItems
        self._revealedHighlights = revealedHighlights
        self.isLuckyBonus = isLuckyBonus

        // Initialize with "before" values
        _displayLevel = State(initialValue: snapshot.beforeLevel)
        _displayXP = State(initialValue: snapshot.beforeXP)
        _displayFloor = State(initialValue: snapshot.beforeFloor)
        _displayCeiling = State(initialValue: snapshot.beforeCeiling)
        _progress = State(initialValue: Double(snapshot.beforeXP - snapshot.beforeFloor) / Double(max(1, snapshot.beforeCeiling - snapshot.beforeFloor)))
    }

    private var accentColor: Color {
        DS.Theme.accent
    }

    private var isLevelUp: Bool {
        snapshot.afterLevel > snapshot.beforeLevel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // XP Progress Bar - Prominent and always visible
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Level \(displayLevel)")
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(.white)
                        .transition(.opacity)
                        .id("level-\(displayLevel)")
                    Spacer()
                    Text("+\(snapshot.xpGained) XP")
                        .dsFont(.subheadline, weight: .semibold)
                        .foregroundStyle(accentColor)
                }

                // Progress bar - GPU accelerated
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        ChamferedRectangle(.small)
                            .fill(.white.opacity(0.10))
                            .frame(height: 10)

                        // Fill - smoothly animated with GPU acceleration
                        ChamferedRectangle(.small)
                            .fill(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 10)
                            .animation(.easeOut(duration: 1.0), value: progress)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("\(displayXP - displayFloor) / \(displayCeiling - displayFloor) XP")
                        .dsFont(.caption2, weight: .medium)
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 1.0), value: displayXP)
                    Spacer()
                }
            }

            // XP Breakdown - Staggered reveal
            if !lineItems.isEmpty {
                Divider()
                    .background(.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 6) {
                    Text("XP Breakdown")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(lineItems) { item in
                        if revealedLineItems.contains(item.id) {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .dsFont(.caption, weight: .bold)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(humanize(item.source))
                                        .dsFont(.caption, weight: .medium)
                                        .foregroundStyle(.white)

                                    if let detail = item.detail {
                                        Text(humanize(detail))
                                            .dsFont(.caption2)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }

                                Spacer(minLength: 0)

                                Text("+\(item.xp)")
                                    .dsFont(.caption, weight: .bold)
                                    .foregroundStyle(accentColor)
                            }
                            .padding(.vertical, 2)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                }
            }

            // Highlights (achievements, PRs, etc.) - Staggered reveal
            if !highlights.isEmpty {
                Divider()
                    .background(.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Rewards")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(highlights) { h in
                        if revealedHighlights.contains(h.id) {
                            HStack(spacing: 8) {
                                Image(systemName: h.icon)
                                    .dsFont(.caption, weight: .bold)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(accentColor)

                                Text(h.label)
                                    .dsFont(.caption, weight: .medium)
                                    .foregroundStyle(.white)

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            isLuckyBonus
                ? DS.Theme.accent.opacity(0.08)
                : DS.Theme.cardTop,
            in: ChamferedRectangle(.large)
        )
        .overlay(
            ChamferedRectangle(.large).stroke(
                isLuckyBonus ? DS.Theme.accent.opacity(0.26) : .white.opacity(0.10),
                lineWidth: 1
            )
        )
        .onAppear {
            animateXPProgress()
        }
    }

    private func animateXPProgress() {
        if isLevelUp {
            // Level up animation sequence
            // Phase 1: Animate to 100% in old level (0.9s)
            progress = 1.0
            displayXP = snapshot.beforeCeiling

            // Phase 2: Instantly switch to new level at 0 progress (NO animation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    displayLevel = snapshot.afterLevel
                    displayFloor = snapshot.afterFloor
                    displayCeiling = snapshot.afterCeiling
                    displayXP = snapshot.afterFloor
                    progress = 0
                }

                // Phase 3: Animate to final position in new level (0.8s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let finalRange = Double(snapshot.afterCeiling - snapshot.afterFloor)
                    let finalProgress = finalRange > 0 ? Double(snapshot.afterXP - snapshot.afterFloor) / finalRange : 0
                    progress = min(max(finalProgress, 0), 1)
                    displayXP = snapshot.afterXP
                }
            }
        } else {
            // Simple progress animation without level up
            let finalRange = Double(snapshot.afterCeiling - snapshot.afterFloor)
            let finalProgress = finalRange > 0 ? Double(snapshot.afterXP - snapshot.afterFloor) / finalRange : 0
            progress = min(max(finalProgress, 0), 1)
            displayXP = snapshot.afterXP
            displayLevel = snapshot.afterLevel
            displayFloor = snapshot.afterFloor
            displayCeiling = snapshot.afterCeiling
        }
    }
}

// MARK: - XP Gain Card with Animated Progress Bar

private struct XPGainCard: View {
    let snapshot: XPSnapshot
    let lineItems: [XPLineItem]
    let highlights: [WinScreenView.Highlight]
    let humanize: (String) -> String

    @State private var progress: Double = 0
    @State private var displayLevel: Int
    @State private var displayXP: Int
    @State private var displayFloor: Int
    @State private var displayCeiling: Int

    init(snapshot: XPSnapshot, lineItems: [XPLineItem], highlights: [WinScreenView.Highlight], humanize: @escaping (String) -> String) {
        self.snapshot = snapshot
        self.lineItems = lineItems
        self.highlights = highlights
        self.humanize = humanize

        // Initialize with "before" values
        _displayLevel = State(initialValue: snapshot.beforeLevel)
        _displayXP = State(initialValue: snapshot.beforeXP)
        _displayFloor = State(initialValue: snapshot.beforeFloor)
        _displayCeiling = State(initialValue: snapshot.beforeCeiling)
        _progress = State(initialValue: Double(snapshot.beforeXP - snapshot.beforeFloor) / Double(max(1, snapshot.beforeCeiling - snapshot.beforeFloor)))
    }

    private var isLevelUp: Bool {
        snapshot.afterLevel > snapshot.beforeLevel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // XP Progress Bar - Prominent and always visible
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Level \(displayLevel)")
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(.white)
                        .transition(.opacity)
                        .id("level-\(displayLevel)")
                    Spacer()
                    Text("+\(snapshot.xpGained) XP")
                        .dsFont(.subheadline, weight: .semibold)
                        .foregroundStyle(DS.Theme.accent)
                }

                // Progress bar - GPU accelerated
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        ChamferedRectangle(.small)
                            .fill(.white.opacity(0.10))
                            .frame(height: 10)

                        // Fill - smoothly animated with GPU acceleration
                        ChamferedRectangle(.small)
                            .fill(
                                LinearGradient(
                                    colors: [DS.Theme.accent, DS.Theme.accent.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 10)
                            .animation(.easeOut(duration: 1.0), value: progress)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("\(displayXP - displayFloor) / \(displayCeiling - displayFloor) XP")
                        .dsFont(.caption2, weight: .medium)
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 1.0), value: displayXP)
                    Spacer()
                }
            }

            // XP Breakdown - Compact
            if !lineItems.isEmpty {
                Divider()
                    .background(.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 6) {
                    Text("XP Breakdown")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(lineItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .dsFont(.caption, weight: .bold)
                                .frame(width: 18, height: 18)
                                .foregroundStyle(DS.Theme.accent)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(humanize(item.source))
                                    .dsFont(.caption, weight: .medium)
                                    .foregroundStyle(.white)

                                if let detail = item.detail {
                                    Text(humanize(detail))
                                        .dsFont(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }

                            Spacer(minLength: 0)

                            Text("+\(item.xp)")
                                .dsFont(.caption, weight: .bold)
                                .foregroundStyle(DS.Theme.accent)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Highlights (achievements, PRs, etc.) - Compact
            if !highlights.isEmpty {
                Divider()
                    .background(.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Rewards")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(highlights) { h in
                        HStack(spacing: 8) {
                            Image(systemName: h.icon)
                                .dsFont(.caption, weight: .bold)
                                .frame(width: 18, height: 18)
                                .foregroundStyle(DS.Theme.accent)

                            Text(h.label)
                                .dsFont(.caption, weight: .medium)
                                .foregroundStyle(.white)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.10), lineWidth: 1))
        .onAppear {
            if isLevelUp {
                // Level up animation sequence
                // Phase 1: Animate to 100% in old level (0.9s)
                progress = 1.0
                displayXP = snapshot.beforeCeiling

                // Phase 2: Instantly switch to new level at 0 progress (NO animation)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        displayLevel = snapshot.afterLevel
                        displayFloor = snapshot.afterFloor
                        displayCeiling = snapshot.afterCeiling
                        displayXP = snapshot.afterFloor
                        progress = 0
                    }

                    // Phase 3: Animate to final position in new level (0.8s)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let finalRange = Double(snapshot.afterCeiling - snapshot.afterFloor)
                        let finalProgress = finalRange > 0 ? Double(snapshot.afterXP - snapshot.afterFloor) / finalRange : 0
                        progress = min(max(finalProgress, 0), 1)
                        displayXP = snapshot.afterXP
                    }
                }
            } else {
                // Simple progress animation without level up
                let finalRange = Double(snapshot.afterCeiling - snapshot.afterFloor)
                let finalProgress = finalRange > 0 ? Double(snapshot.afterXP - snapshot.afterFloor) / finalRange : 0
                progress = min(max(finalProgress, 0), 1)
                displayXP = snapshot.afterXP
                displayLevel = snapshot.afterLevel
                displayFloor = snapshot.afterFloor
                displayCeiling = snapshot.afterCeiling
            }
        }
    }
}
