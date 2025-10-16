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

    private var title: String {
        if summary.prCount > 0 { return "Personal Record!" }
        if summary.levelUpTo != nil { return "Level Up!" }
        return "Workout Complete"
    }

    private var subtitle: String? {
        var bits: [String] = []
        if summary.streakNew > summary.streakOld { bits.append("Streak \(summary.streakNew)🔥") }
        if summary.unlockedAchievements.count > 0 { bits.append("\(summary.unlockedAchievements.count) new achievement\(summary.unlockedAchievements.count == 1 ? "" : "s")") }
        if summary.prCount > 0 { bits.append("\(summary.prCount) PR\(summary.prCount == 1 ? "" : "s")") }
        return bits.isEmpty ? nil : bits.joined(separator: " • ")
    }

    private var highlights: [Highlight] {
        var items: [Highlight] = []
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
            // Show up to 3, then “+N more…”
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

            VStack(spacing: 20) {
                // Top icon & title
                Image(systemName: summary.prCount > 0 ? "crown.fill" : "sparkles")
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
                    Pill("XP +\(summary.xp)")
                    if summary.coins > 0 { Pill("Coins +\(summary.coins)") }
                    if let lvl = summary.levelUpTo { Pill("Level \(lvl)") }
                }
                .padding(.top, 2)

                // Highlights card
                if !highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(highlights) { h in
                            HStack(spacing: 10) {
                                Image(systemName: h.icon)
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 22, height: 22)
                                Text(h.label)
                                    .font(.subheadline)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            Divider().background(.white.opacity(0.08))
                        }
                    }
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
                }

                Spacer(minLength: 0)

                Button("Continue") { onDismiss() }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(hex: "#F4E409"))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(22)
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
