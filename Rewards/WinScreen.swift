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

    private var iconName: String {
        if summary.newExerciseCount > 0 { return "star.fill" }
        if summary.prCount > 0 { return "crown.fill" }
        return "sparkles"
    }

    private var title: String {
        if summary.newExerciseCount > 0 { return "You completed a new exercise!" }
        if summary.prCount > 0 { return "Personal Record!" }
        if summary.levelUpTo != nil { return "Level Up!" }
        return "You completed a workout!"
    }

    private var subtitle: String? {
        var bits: [String] = []
        if summary.streakNew > summary.streakOld { bits.append("Streak \(summary.streakNew)🔥") }
        if summary.unlockedAchievements.count > 0 { bits.append("\(summary.unlockedAchievements.count) new achievement\(summary.unlockedAchievements.count == 1 ? "" : "s")") }
        if summary.newExerciseCount > 0 { bits.append("\(summary.newExerciseCount) new exercise\(summary.newExerciseCount == 1 ? "" : "s")") }
        if summary.prCount > 0 { bits.append("\(summary.prCount) PR\(summary.prCount == 1 ? "" : "s")") }
        return bits.isEmpty ? nil : bits.joined(separator: " • ")
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
            LinearGradient(colors: [Color.black, Color.black.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Top icon & title
                    Image(systemName: iconName)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Color(hex: "#F4E409"))
                        .scaleEffect(animate ? 1 : 0.6)
                        .symbolEffect(.bounce, options: .repeat(1))

                    Text(title)
                        .font(.system(.largeTitle, weight: .bold))
                        .foregroundStyle(.white)

                    if let sub = subtitle {
                        Text(sub)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    // Totals row
                    HStack(spacing: 10) {
                        if summary.xp > 0 { Pill("XP +\(summary.xp)") }
                        if summary.coins > 0 { Pill("Coins +\(summary.coins)") }
                        if let lvl = summary.levelUpTo { Pill("Level \(lvl)") }
                    }
                    .padding(.top, 2)

                    // XP Gain Card with animated progress bar
                    if let snapshot = summary.xpSnapshot, !summary.xpLineItems.isEmpty {
                        XPGainCard(snapshot: snapshot, lineItems: summary.xpLineItems)
                            .transition(.opacity.combined(with: .scale))
                    }

                    // Highlights card
                    //if !highlights.isEmpty {
                        //VStack(alignment: .leading, spacing: 10) {
                            //ForEach(highlights) { h in
                                //HStack(spacing: 10) {
                                    //Image(systemName: h.icon)
                                       // .font(.subheadline.weight(.bold))
                                     //   .frame(width: 22, height: 22)
                                   // Text(h.label)
                                   //     .font(.subheadline)
                                 //   Spacer(minLength: 0)
                               // }
                               // .foregroundStyle(.white)
                               // .padding(.vertical, 6)
                             //   .contentShape(Rectangle())
                           //     Divider().background(.white.opacity(0.08))
                         //   }
                       // }
                      //  .padding(14)
                      //  .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                      //  .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
                    //}

                    Button("Continue") { onDismiss() }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(hex: "#F4E409"))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 20)
                }
                .padding(22)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { animate = true }
        }
    }

    private func Pill(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            .foregroundStyle(.white)
    }

    private func humanize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
    }
}

// MARK: - XP Gain Card with Animated Progress Bar

private struct XPGainCard: View {
    let snapshot: XPSnapshot
    let lineItems: [XPLineItem]

    @State private var animatedXP: Int
    @State private var animatedLevel: Int
    @State private var currentLevelFloor: Int
    @State private var currentLevelCeiling: Int

    init(snapshot: XPSnapshot, lineItems: [XPLineItem]) {
        self.snapshot = snapshot
        self.lineItems = lineItems
        _animatedXP = State(initialValue: snapshot.beforeXP)
        _animatedLevel = State(initialValue: snapshot.beforeLevel)
        _currentLevelFloor = State(initialValue: snapshot.beforeFloor)
        _currentLevelCeiling = State(initialValue: snapshot.beforeCeiling)
    }

    private var progress: Double {
        let range = Double(currentLevelCeiling - currentLevelFloor)
        guard range > 0 else { return 0 }
        let current = Double(animatedXP - currentLevelFloor)
        return min(max(current / range, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // XP Progress Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Level \(animatedLevel)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("+\(snapshot.xpGained) XP")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: "#F4E409"))
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.10))
                            .frame(height: 12)

                        // Fill
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#F4E409"), Color(hex: "#FFD700")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 12)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("\(animatedXP) / \(currentLevelCeiling) XP")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
            }

            // XP Breakdown
            if !lineItems.isEmpty {
                Divider()
                    .background(.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 10) {
                    Text("XP Breakdown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    ForEach(lineItems) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.subheadline.weight(.bold))
                                .frame(width: 22, height: 22)
                                .foregroundStyle(Color(hex: "#F4E409"))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.source)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)

                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }

                            Spacer(minLength: 0)

                            Text("+\(item.xp)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color(hex: "#F4E409"))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
        .onAppear {
            animateXPGain()
        }
    }

    private func animateXPGain() {
        let duration: Double = 1.5
        let steps = 30
        let stepDelay = duration / Double(steps)

        let totalGain = snapshot.afterXP - snapshot.beforeXP
        let xpPerStep = Double(totalGain) / Double(steps)

        var currentStep = 0

        Timer.scheduledTimer(withTimeInterval: stepDelay, repeats: true) { timer in
            currentStep += 1

            let newXP = snapshot.beforeXP + Int(Double(currentStep) * xpPerStep)
            animatedXP = min(newXP, snapshot.afterXP)

            // Check for level up
            if animatedXP >= currentLevelCeiling && animatedLevel < snapshot.afterLevel {
                animatedLevel += 1
                let (_, floor, ceiling) = levelCurveFloors(for: animatedXP)
                currentLevelFloor = floor
                currentLevelCeiling = ceiling
            }

            if currentStep >= steps || animatedXP >= snapshot.afterXP {
                timer.invalidate()
                animatedXP = snapshot.afterXP
                animatedLevel = snapshot.afterLevel
                currentLevelFloor = snapshot.afterFloor
                currentLevelCeiling = snapshot.afterCeiling
            }
        }
    }

    // Helper to calculate level curve floors
    private func levelCurveFloors(for xp: Int) -> (level: Int, floor: Int, ceiling: Int) {
        var level = 1
        var floor = 0
        var ceiling = 100

        while xp >= ceiling {
            level += 1
            floor = ceiling
            ceiling = floor + (50 + (level - 1) * 50)
        }

        return (level, floor, ceiling)
    }
}
