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
        if summary.streakNew > summary.streakOld { bits.append("Streak \(summary.streakNew)") }
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
                        .multilineTextAlignment(.center)

                    if let sub = subtitle {
                        Text(sub)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
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

                    Button {
                        Haptics.light()
                        onDismiss()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
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

    @State private var animatedProgress: Double = 0
    @State private var showFinalValues: Bool = false

    private var isLevelUp: Bool {
        snapshot.afterLevel > snapshot.beforeLevel
    }

    private var displayLevel: Int {
        showFinalValues ? snapshot.afterLevel : snapshot.beforeLevel
    }

    private var displayXP: Int {
        if !isLevelUp {
            // No level up: simple interpolation
            let range = Double(snapshot.afterXP - snapshot.beforeXP)
            return snapshot.beforeXP + Int(range * animatedProgress)
        } else if !showFinalValues {
            // Level up, phase 1: interpolate to old level ceiling
            let range = Double(snapshot.beforeCeiling - snapshot.beforeXP)
            return snapshot.beforeXP + Int(range * animatedProgress)
        } else {
            // Level up, phase 2: interpolate from new floor to final XP
            let range = Double(snapshot.afterXP - snapshot.afterFloor)
            return snapshot.afterFloor + Int(range * animatedProgress)
        }
    }

    private var displayFloor: Int {
        showFinalValues ? snapshot.afterFloor : snapshot.beforeFloor
    }

    private var displayCeiling: Int {
        showFinalValues ? snapshot.afterCeiling : snapshot.beforeCeiling
    }

    private var progress: Double {
        let range = Double(displayCeiling - displayFloor)
        guard range > 0 else { return 0 }
        let current = Double(displayXP - displayFloor)
        return min(max(current / range, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // XP Progress Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Level \(displayLevel)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                        .id("level-\(displayLevel)")
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

                        // Fill - smoothly animated
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
                    Text("\(displayXP - displayFloor) / \(displayCeiling - displayFloor) XP")
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
            // Smooth animation using SwiftUI's native animation system
            if snapshot.afterLevel > snapshot.beforeLevel {
                // Level up animation sequence:
                // 1. Fill bar to 100% in old level
                withAnimation(.easeOut(duration: 0.9)) {
                    animatedProgress = 1.0
                }
                // 2. Switch to new level (bar disappears/resets)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    // Instantly switch to new level with 0 progress
                    showFinalValues = true
                    animatedProgress = 0

                    // 3. Fill bar to final position in new level
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.7)) {
                            animatedProgress = 1.0
                        }
                    }
                }
            } else {
                // Simple progress animation without level up
                withAnimation(.easeOut(duration: 1.2)) {
                    animatedProgress = 1.0
                    showFinalValues = true
                }
            }
        }
    }
}
