//
//  AchievementsView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


import SwiftUI
import SwiftData

struct AchievementsView: View {
    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse)
    private var achievements: [Achievement]

    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var filter: Filter = .all
    @State private var searchDebounceTask: Task<Void, Never>?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case inProgress = "In progress"
        case unlocked = "Unlocked"
        var id: String { rawValue }
    }

    private var filtered: [Achievement] {
        achievements
            .filter { a in
                guard !debouncedSearch.isEmpty else { return true }
                return a.title.localizedCaseInsensitiveContains(debouncedSearch)
                    || a.desc.localizedCaseInsensitiveContains(debouncedSearch)
            }
            .filter { a in
                switch filter {
                case .all: return true
                case .inProgress: return a.unlockedAt == nil
                case .unlocked: return a.unlockedAt != nil
                }
            }
    }

    private var inProgress: [Achievement] { filtered.filter { $0.unlockedAt == nil } }
    private var unlocked:   [Achievement] { filtered.filter { $0.unlockedAt != nil } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if filtered.isEmpty {
                ContentUnavailableView("No achievements",
                                       systemImage: "trophy",
                                       description: Text("Log more workouts or adjust your filters."))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else {
                    if !inProgress.isEmpty {
                        AchievementSection(title: "In progress", achievements: inProgress)
                    }
                    if !unlocked.isEmpty {
                        AchievementSection(title: "Unlocked", achievements: unlocked)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.large)
                }
            }
        }
        .onChange(of: search) { _, newSearch in
            // Debounce search input (300ms delay)
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                guard !Task.isCancelled else { return }
                debouncedSearch = newSearch
            }
        }
    }
}

private struct AchievementSection: View {
    let title: String
    let achievements: [Achievement]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .dsFont(.title3, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(achievements.enumerated()), id: \.element.id) { index, achievement in
                    AchievementRow(achievement)

                    if index < achievements.count - 1 {
                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(height: 1)
                            .padding(.leading, 72)
                    }
                }
            }
            .padding(.vertical, 12)
            .background(DS.Theme.cardTop, in: ChamferedRectangle(.xl))
            .overlay(ChamferedRectangle(.xl).stroke(DS.Semantic.border, lineWidth: 1))
        }
    }
}

private struct AchievementRow: View {
    let a: Achievement

    init(_ a: Achievement) { self.a = a }

    private var progressFrac: Double {
        guard a.target > 0 else { return 0 }
        return min(Double(a.progress) / Double(a.target), 1.0)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ProfileSectionIcon(
                kind: .achievementCup,
                color: a.unlockedAt == nil ? .secondary : DS.Theme.accent
            )
            .frame(width: 40, height: 40)
            .background(
                (a.unlockedAt == nil ? Color.white.opacity(0.04) : DS.Theme.accent.opacity(0.12)),
                in: ChamferedRectangleAlt(.small)
            )
            .overlay(
                ChamferedRectangleAlt(.small)
                    .stroke(a.unlockedAt == nil ? DS.Semantic.border : DS.Theme.accent.opacity(0.35), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(a.title)
                    .dsFont(.headline, weight: .semibold)
                    .foregroundStyle(.primary)
                Text(a.desc)
                    .dsFont(.subheadline, weight: .medium)
                    .foregroundStyle(.secondary)

                if let unlockedDate = a.unlockedAt {
                    Text(unlockedDate, style: .date)
                        .dsFont(.subheadline, weight: .medium)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.16))
                                Rectangle()
                                    .fill(DS.Theme.accent)
                                    .frame(width: geo.size.width * progressFrac)
                            }
                        }
                        .frame(height: 6)
                        .clipShape(ChamferedRectangle(.micro))

                        Text("\(a.progress)/\(a.target)")
                            .dsFont(.subheadline, weight: .semibold, monospacedDigits: true)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(ChamferedRectangle(.medium))
    }
}
