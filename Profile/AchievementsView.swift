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
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case inProgress = "In progress"
        case unlocked = "Unlocked"
        var id: String { rawValue }
    }

    private var filtered: [Achievement] {
        achievements
            .filter { a in
                guard !search.isEmpty else { return true }
                return a.title.localizedCaseInsensitiveContains(search)
                    || a.desc.localizedCaseInsensitiveContains(search)
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
        List {
            if filtered.isEmpty {
                ContentUnavailableView("No achievements",
                                       systemImage: "trophy",
                                       description: Text("Log more workouts or adjust your filters."))
            } else {
                if !inProgress.isEmpty {
                    Section("In progress") {
                        ForEach(inProgress) { a in AchievementRow(a) }
                    }
                }
                if !unlocked.isEmpty {
                    Section("Unlocked") {
                        ForEach(unlocked) { a in AchievementRow(a) }
                    }
                }
            }
        }
        .navigationTitle("Achievements")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.menu)
            }
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: a.unlockedAt == nil ? "trophy" : "trophy.fill")
                .symbolRenderingMode(.monochrome) // optional, but nice with styles
                .foregroundStyle(
                    a.unlockedAt == nil
                    ? AnyShapeStyle(.secondary)
                    : AnyShapeStyle(.yellow)
                )
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(a.title).font(.subheadline.weight(.semibold))
                Text(a.desc).font(.caption).foregroundStyle(.secondary)

                if a.unlockedAt == nil {
                    ProgressView(value: progressFrac) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(a.progress)/\(a.target)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .tint(.yellow)
                } else {
                    Text(a.unlockedAt!, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
