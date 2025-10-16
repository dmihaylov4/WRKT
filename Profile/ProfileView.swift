//
//  ProfileView.swift
//  WRKT
//

import SwiftUI
import SwiftData




struct ProfileView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @Query private var progress: [RewardProgress]
    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse) private var achievements: [Achievement]
    @Query private var stamps: [DexStamp]

    // MARK: - PR Dex preview items (unlocked first, then alpha; first 8)
    private var dexPreview: [DexItem] {
        let unlockedDates: [String: Date] = Dictionary(
            uniqueKeysWithValues: stamps.compactMap { s in
                guard let d = s.unlockedAt else { return nil }
                return (s.key, d)
            }
        )
        let unlockedSet = Set(unlockedDates.keys)

        // Split → sort → merge → take first 8 (avoids sorting all together twice)
        var unlocked: [DexItem] = []
        var locked:   [DexItem] = []

        unlocked.reserveCapacity(16)
        locked.reserveCapacity(16)

        for ex in repo.exercises {
            let key = canonicalExerciseKey(from: ex.id)
            let unlockedAt = unlockedDates[key]
            let short = DexText.shortName(ex.name)

            let item = DexItem(
                id: ex.id,
                name: ex.name,
                short: short,
                ruleId: "ach.pr.\(ex.id)",
                progress: unlockedAt == nil ? 0 : 1,
                target: 1,
                unlockedAt: unlockedAt,
                searchKey: DexItem.buildSearchKey(name: ex.name, short: short, id: ex.id)
            )

            if unlockedSet.contains(key) { unlocked.append(item) } else { locked.append(item) }
        }

        unlocked.sort { $0.short < $1.short }
        locked.sort { $0.short < $1.short }

        return Array((unlocked + locked).prefix(8))
    }

    var body: some View {
        List {
            // HEADER
            if let p = progress.first {
                Section {
                    ProfileHeaderCard(level: p.level,
                                      xp: p.xp,
                                      nextXP: p.nextLevelXP,
                                      streak: p.currentStreak,
                                      longest: p.longestStreak)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ContentUnavailableView("No profile yet",
                                           systemImage: "person.crop.circle.badge.questionmark",
                                           description: Text("Start a workout to earn XP and level up."))
                }
            }
            Section {
                ProfileStatsView()
            }

            // “DEX” PREVIEW — same tiles as the Dex screen (compact variant)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PR Collection").font(.headline)
                        Spacer()
                        NavigationLink("Open Dex") { AchievementsDexView() }
                            .font(.subheadline.weight(.semibold))
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                        ForEach(dexPreview) { item in
                            DexTile(item: item).equatable()

                        }
                    }
                    .padding(.top, 2)
                    .transaction { $0.animation = nil } // snappy scrolling
                }
                .padding(.vertical, 6)
            }

            // MILESTONES (non-PR achievements)
            let milestones = achievements.filter { !$0.id.hasPrefix("ach.pr.") }
            if !milestones.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Milestones").font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(milestones.prefix(12)) { a in
                                    MilestoneChip(a: a)
                                }
                            }
                            .padding(.horizontal, 2)
                        }

                        NavigationLink("See all achievements") { AchievementsView() }
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            }

            // SETTINGS
            Section("Settings & Connections") {
                NavigationLink("Preferences") { PreferencesView() }
                NavigationLink("Health & Sync") { ConnectionsView() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profile")
    }
}

// MARK: - Sleek header card

private struct ProfileHeaderCard: View {
    let level: Int
    let xp: Int
    let nextXP: Int
    let streak: Int
    let longest: Int

    private var ringFrac: Double {
        let total = max(nextXP, 1)
        let cur   = xp % total
        return min(Double(cur) / Double(total), 1.0)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Level \(level)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    // streak chip
                    Label {
                        Text("\(streak)")
                            .font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: "flame.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .foregroundStyle(.white.opacity(0.85))
                }

                Text("Longest streak \(longest) days")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                // slim progress + numeric
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(0.15))
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: "#F4E409"))
                                .frame(width: max(8, geo.size.width * ringFrac))
                        }
                    }
                    .frame(height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text("XP \(xp % max(nextXP,1))/\(max(nextXP,1))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            Spacer(minLength: 0)

            // XP donut
            XPRing(fraction: ringFrac)
                .frame(width: 80, height: 80)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#232323"), Color(hex: "#353535")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .foregroundStyle(.white)
    }
}

private struct XPRing: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [Color(hex: "#F4E409"), Color(hex: "#FFE869"), Color(hex: "#F4E409")],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: "bolt.heart.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(hex: "#F4E409"))
        }
    }
}

// MARK: - Dex preview


private struct DexBadge: View {
    let item: DexItem
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(item.isUnlocked ? Color.yellow.opacity(0.18) : Color.gray.opacity(0.12))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.quaternary)
                Image(systemName: item.isUnlocked ? "trophy.fill" : "trophy")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(item.isUnlocked ? Color.yellow : .secondary)
                    .font(.title2.weight(.bold))
            }
            .frame(height: 62)

            Text(item.short)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .frame(minHeight: 128)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Milestones (non-PR)

private struct MilestoneChip: View {
    let a: Achievement

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: a.unlockedAt == nil ? "trophy" : "trophy.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(a.unlockedAt == nil ? .secondary : Color.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).font(.subheadline.weight(.semibold))
                if let when = a.unlockedAt {
                    Text(when, style: .date).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(a.progress)/\(a.target)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary))
    }
}

// MARK: - Tiny hex helper (if you don’t already have a shared one)
private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >>  8) & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
