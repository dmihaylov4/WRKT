//
//  WinScreen.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 13.10.25.
//

// WinScreen.swift
import SwiftUI
import Combine



//REMOVE OLD
struct WinScreenHost: View {
    @StateObject private var coord = WinScreenCoordinator.shared

    var body: some View {
        EmptyView()
            .fullScreenCover(
                item: Binding(
                    get: { coord.summary.map { Box(value: $0) } },
                    set: { (box: Box?) in if box == nil { coord.summary = nil } }
                )
            ) { (box: Box) in
                WinScreenView(summary: box.value) { coord.summary = nil }
            }
    }

    private struct Box: Identifiable {
        let id = UUID()
        let value: RewardSummary
    }
}

// ENDREMOVE OLD

//NEW TEST
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

//END NEW TEST

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
    @State private var revealedHighlights: Set<UUID> = []
    @State private var showButtons = false

    // Lucky bonus animation state
    @State private var showLuckyBanner = false
    @State private var luckyPulse = false

    private var iconName: String {
        if summary.gotLuckyBonus { return "sparkles" }
        if summary.newExerciseCount > 0 { return "star.fill" }
        if summary.prCount > 0 { return "crown.fill" }
        return "sparkles"
    }

    private var title: String {
        if summary.gotLuckyBonus { return "LUCKY!" }
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

    private func formatMultiplier(_ m: Double) -> String {
        if m == 1.5 { return "1.5x" }
        if m == 2.0 { return "2x" }
        if m == 3.0 { return "3x" }
        return "\(Int(m))x"
    }

    private var highlights: [Highlight] {
        var items: [Highlight] = []
        if summary.newExerciseCount > 0 {
            items.append(.init(icon: "star.fill", label: "\(summary.newExerciseCount) new exercise\(summary.newExerciseCount == 1 ? "" : "s") unlocked"))
        }
        if summary.prCount > 0 {
            items.append(.init(icon: "crown.fill", label: "\(summary.prCount) new PR\(summary.prCount == 1 ? "" : "s")"))
        }
        if let lvl = summary.levelUpTo {
            items.append(.init(icon: "rosette", label: "Reached level \(lvl)"))
        }
        if summary.streakNew > summary.streakOld {
            let milestone = summary.hitStreakMilestone ? " (milestone!)" : ""
            items.append(.init(icon: "flame.fill", label: "Streak \(summary.streakNew)\(milestone)"))
        }
        if !summary.unlockedAchievements.isEmpty {
            // Show up to 3, then "+N more…"
            let pretty = summary.unlockedAchievements.map(humanize)
            let head = pretty.prefix(3)
            head.forEach { items.append(.init(icon: "medal.fill", label: $0)) }
            let remaining = pretty.count - head.count
            if remaining > 0 { items.append(.init(icon: "ellipsis.circle", label: "+\(remaining) more achievements")) }
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
                        Color.yellow.opacity(luckyPulse ? 0.12 : 0.04),
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
                        Image(systemName: iconName)
                            .font(.system(size: 52, weight: .bold))
                            .foregroundStyle(summary.gotLuckyBonus ? .yellow : DS.Theme.accent)
                            .scaleEffect(animate ? 1 : 0.6)
                            .symbolEffect(.bounce, options: .repeat(1))
                            .padding(.top, summary.gotLuckyBonus ? 8 : 20)
                            .transition(.scale.combined(with: .opacity))

                        Text(title)
                            .font(.system(.title, weight: .bold))
                            .foregroundStyle(summary.gotLuckyBonus ? .yellow : .white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))

                        if let sub = subtitle {
                            Text(sub)
                                .font(.subheadline)
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
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .background(.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Continue Button
                        Button {
                            Haptics.light()
                            onDismiss()
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                        .background(summary.gotLuckyBonus ? .yellow : DS.Theme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .onAppear {
            startStaggeredReveal()
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
                    revealedLineItems.insert(item.id)
                }
                Haptics.soft()
            }
        }

        // Stagger highlights reveal
        let highlightStartDelay = baseDelay + 0.9 + Double(summary.xpLineItems.count) * 0.15 + 0.2
        for (index, highlight) in highlights.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + highlightStartDelay + Double(index) * 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    revealedHighlights.insert(highlight.id)
                }
                Haptics.soft()
            }
        }

        // Buttons appear last
        let totalItems = summary.xpLineItems.count + highlights.count
        let buttonsDelay = baseDelay + 0.9 + Double(totalItems) * 0.15 + 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + buttonsDelay) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showButtons = true
            }
        }
    }

    private func Pill(_ text: String, isLucky: Bool = false) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isLucky ? .yellow.opacity(0.20) : .white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(isLucky ? .yellow.opacity(0.4) : .white.opacity(0.15), lineWidth: 1))
            .foregroundStyle(isLucky ? .yellow : .white)
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
        let id = UUID()
        let icon: String
        let label: String
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
            .font(.headline.weight(.black))
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Capsule()
                        .fill(.yellow)

                    // Shimmer effect
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.4), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmer ? 100 : -100)
                        .mask(Capsule())
                }
            )
            .shadow(color: .yellow.opacity(0.5), radius: 10, x: 0, y: 0)
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
                        .font(.caption.weight(.bold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(DS.Theme.accent)
                    Text(h.label)
                        .font(.caption.weight(.medium))
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
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - XP Gain Card with Staggered Reveal
private struct XPGainCardStaggered: View {
    let snapshot: XPSnapshot
    let lineItems: [XPLineItem]
    let highlights: [WinScreenView.Highlight]
    let humanize: (String) -> String
    @Binding var revealedLineItems: Set<String>
    @Binding var revealedHighlights: Set<UUID>
    let isLuckyBonus: Bool

    @State private var progress: Double = 0
    @State private var displayLevel: Int
    @State private var displayXP: Int
    @State private var displayFloor: Int
    @State private var displayCeiling: Int

    init(snapshot: XPSnapshot, lineItems: [XPLineItem], highlights: [WinScreenView.Highlight],
         humanize: @escaping (String) -> String, revealedLineItems: Binding<Set<String>>,
         revealedHighlights: Binding<Set<UUID>>, isLuckyBonus: Bool) {
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
        isLuckyBonus ? .yellow : DS.Theme.accent
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
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                        .id("level-\(displayLevel)")
                    Spacer()
                    Text("+\(snapshot.xpGained) XP")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                }

                // Progress bar - GPU accelerated
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.10))
                            .frame(height: 10)

                        // Fill - smoothly animated with GPU acceleration
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .drawingGroup() // GPU-accelerated rendering
                }
                .frame(height: 10)

                HStack {
                    Text("\(displayXP - displayFloor) / \(displayCeiling - displayFloor) XP")
                        .font(.caption2.weight(.medium))
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(lineItems) { item in
                        if revealedLineItems.contains(item.id) {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .font(.caption.weight(.bold))
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(humanize(item.source))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white)

                                    if let detail = item.detail {
                                        Text(humanize(detail))
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }

                                Spacer(minLength: 0)

                                Text("+\(item.xp)")
                                    .font(.caption.weight(.bold))
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(highlights) { h in
                        if revealedHighlights.contains(h.id) {
                            HStack(spacing: 8) {
                                Image(systemName: h.icon)
                                    .font(.caption.weight(.bold))
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(accentColor)

                                Text(h.label)
                                    .font(.caption.weight(.medium))
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
                ? .yellow.opacity(0.08)
                : .white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(
                isLuckyBonus ? .yellow.opacity(0.2) : .white.opacity(0.10),
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
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                        .id("level-\(displayLevel)")
                    Spacer()
                    Text("+\(snapshot.xpGained) XP")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Theme.accent)
                }

                // Progress bar - GPU accelerated
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.10))
                            .frame(height: 10)

                        // Fill - smoothly animated with GPU acceleration
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .drawingGroup() // GPU-accelerated rendering
                }
                .frame(height: 10)

                HStack {
                    Text("\(displayXP - displayFloor) / \(displayCeiling - displayFloor) XP")
                        .font(.caption2.weight(.medium))
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(lineItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.caption.weight(.bold))
                                .frame(width: 18, height: 18)
                                .foregroundStyle(DS.Theme.accent)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(humanize(item.source))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)

                                if let detail = item.detail {
                                    Text(humanize(detail))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }

                            Spacer(minLength: 0)

                            Text("+\(item.xp)")
                                .font(.caption.weight(.bold))
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(highlights) { h in
                        HStack(spacing: 8) {
                            Image(systemName: h.icon)
                                .font(.caption.weight(.bold))
                                .frame(width: 18, height: 18)
                                .foregroundStyle(DS.Theme.accent)

                            Text(h.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10), lineWidth: 1))
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
