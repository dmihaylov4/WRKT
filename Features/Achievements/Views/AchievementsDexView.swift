// AchievementsDexView.swift
import SwiftUI
import SwiftData
import Combine
import Foundation


private let DexParenRegex: NSRegularExpression? = {
    try? NSRegularExpression(pattern: #"\s*\(.*\)"#, options: [])
}()



enum DexText {
    static let paren: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\s*\(.*\)"#, options: [])
    }()

    // Pure helper – not on a @MainActor type
    static func shortName(_ s: String) -> String {
        var x = s
        if let regex = paren,
           let m = regex.firstMatch(in: x, options: [], range: NSRange(x.startIndex..., in: x)),
           let r = Range(m.range, in: x) { x.removeSubrange(r) }
        for (k,v) in [("Barbell","BB"),("Dumbbell","DB"),("Kettlebell","KB"),
                      ("Machine","Mch"),("Cable","Cbl"),("Smith Machine","Smith"),
                      ("Incline","Inc"),("Decline","Dec"),("Seated","Seat"),
                      ("Single-Arm","SA"),("Single Arm","SA"),
                      ("Single-Leg","SL"),("Single Leg","SL")] {
            x = x.replacingOccurrences(of: k, with: v)
        }
        return x.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
struct AchievementsDexView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse) private var achievements: [Achievement]
    @Query private var stamps: [DexStamp]

    @StateObject private var vm = AchievementsDexVM()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                // Show loading spinner during search
                if vm.isSearching {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Searching...")
                                .dsFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 40)
                        Spacer()
                    }
                    .transition(.opacity)
                } else {
                    // Disable implicit animations while filtering for snappier typing
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(vm.filtered) { item in
                            NavigationLink {
                                DexDetailView(item: item)
                            } label: {
                                DexTile(item: item).equatable()     // avoids re-render when unchanged
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                    .transaction { $0.animation = nil }
                    .transition(.opacity)
                }

                recordsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: vm.isSearching)
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $vm.search, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Filter", selection: $vm.scope) {
                    ForEach(AchievementsDexVM.Scope.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationDestination(for: DexItem.self) { item in
            DexDetailView(item: item)
        }
        .task {
            // Load ALL exercises for the dex, not just the paginated list
            let allExercises = await repo.getAllExercises()
            vm.rebuild(exercises: allExercises, stamps: stamps)
        }
        .onChange(of: repo.exercises) { _ in
            // When exercises update (e.g., custom exercises added), reload all
            Task {
                let allExercises = await repo.getAllExercises()
                vm.rebuild(exercises: allExercises, stamps: stamps)
            }
        }
        .onChange(of: stamps) { s in
            // When stamps update, reload with all exercises
            Task {
                let allExercises = await repo.getAllExercises()
                vm.rebuild(exercises: allExercises, stamps: s)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("PR Dex").dsFont(.headline)
            Spacer()
            Text("\(vm.unlockedCount)/\(vm.totalCount)")
                .dsFont(.caption2, weight: .semibold)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(DS.Theme.accent, in: ChamferedRectangle(.small))
                .foregroundColor(.black)
        }
        .accessibilityLabel("Unlocked \(vm.unlockedCount) of \(vm.totalCount)")
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Records").dsFont(.headline).padding(.top, 8)
            RecordRow(icon: "figure.run", title: "Longest run",    value: "—")
            RecordRow(icon: "flame.fill",  title: "Longest streak", value: "—")
        }
        .padding(.top, 10)
    }
}

// MARK: - ViewModel
@MainActor
final class AchievementsDexVM: ObservableObject {
    // UI state
    @Published var search: String = ""
    @Published var scope: Scope = .all
    @Published private(set) var isSearching: Bool = false

    @inline(__always)
    nonisolated static func canonicalExerciseKey(from id: String) -> String { id }

    enum Scope: String, CaseIterable, Identifiable { case all = "All", unlocked = "Unlocked", locked = "Locked"; var id: String { rawValue } }

    // Data
    @Published private(set) var filtered: [DexItem] = []
    private(set) var base: [DexItem] = []       // precomputed, sorted once

    var unlockedCount: Int { base.filter(\.isUnlocked).count }
    var totalCount: Int { base.count }

    private var bag = Set<AnyCancellable>()

    init() {
        // Track when search/scope changes to show loading state
        Publishers.CombineLatest(
            $search.removeDuplicates(),
            $scope.removeDuplicates()
        )
        .sink { [weak self] _, _ in
            self?.isSearching = true
        }
        .store(in: &bag)

        // Apply filter with 300ms debounce
        Publishers.CombineLatest(
            $search.removeDuplicates(),
            $scope.removeDuplicates()
        )
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .sink { [weak self] q, scope in
            self?.applyFilter(query: q, scope: scope)
            self?.isSearching = false
        }
        .store(in: &bag)
    }

    func rebuild(exercises: [Exercise], stamps: [DexStamp]) {
        // Precompute sets/maps on the calling actor (cheap)
        let unlockedKeys = Set(stamps.map { $0.key })
        let unlockedDates: [String: Date] = Dictionary(
            uniqueKeysWithValues: stamps.compactMap { s in s.unlockedAt.map { (s.key, $0) } }
        )

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Build everything off-main, using NONISOLATED helpers
            let items: [DexItem] = exercises.map { ex in
                let k = AchievementsDexVM.canonicalExerciseKey(from: ex.id)
                let short = DexText.shortName(ex.name)
                let searchKey = DexItem.buildSearchKey(name: ex.name, short: short, id: ex.id)

                return DexItem(
                    id: ex.id,
                    name: ex.name,
                    short: short,
                    ruleId: "ach.pr.\(ex.id)",
                    progress: unlockedKeys.contains(k) ? 1 : 0,
                    target: 1,
                    unlockedAt: unlockedDates[k],
                    searchKey: searchKey
                )
            }
            .sorted { $0.short < $1.short }

            // Publish on main actor
            await MainActor.run {
                self.base = items
                self.applyFilter(query: self.search, scope: self.scope)
            }
        }
    }

    private func applyFilter(query: String, scope: Scope) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1) Text filter (cheap, uses precomputed searchKey)
        let textFiltered: [DexItem]
        if q.isEmpty {
            textFiltered = base
        } else {
            textFiltered = base.filter { $0.searchKey.contains(q) }
        }

        // 2) Scope filter
        let scopeFiltered: [DexItem]
        switch scope {
        case .all:      scopeFiltered = textFiltered
        case .unlocked: scopeFiltered = textFiltered.filter(\.isUnlocked)
        case .locked:   scopeFiltered = textFiltered.filter { !$0.isUnlocked }
        }

        // Keep the unlocked-first ordering like before
        filtered = scopeFiltered.sorted {
            (($0.isUnlocked ? 0 : 1), $0.short) < (($1.isUnlocked ? 0 : 1), $1.short)
        }
    }

    // Precompiled regex (alloc once)
  

    nonisolated static func shortName(_ s: String) -> String {
        // strip parentheticals quickly
        var x = s
        if let regex = DexParenRegex,
           let m = regex.firstMatch(in: x, options: [], range: NSRange(x.startIndex..., in: x)),
           let r = Range(m.range, in: x) { x.removeSubrange(r) }
        // lightweight abbrevs
        let map: [(String,String)] = [
            ("Barbell","BB"),("Dumbbell","DB"),("Kettlebell","KB"),
            ("Machine","Mch"),("Cable","Cbl"),("Smith Machine","Smith"),
            ("Incline","Inc"),("Decline","Dec"),("Seated","Seat"),
            ("Single-Arm","SA"),("Single Arm","SA"),
            ("Single-Leg","SL"),("Single Leg","SL")
        ]
        for (k,v) in map { x = x.replacingOccurrences(of: k, with: v) }
        return x.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Models & Tiles

struct DexItem: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let ruleId: String
    let progress: Int
    let target: Int
    let unlockedAt: Date?
    let searchKey: String
    var isUnlocked: Bool { unlockedAt != nil }
    var frac: Double { min(Double(progress) / Double(max(target,1)), 1.0) }

    init(
        id: String,
        name: String,
        short: String,
        ruleId: String,
        progress: Int,
        target: Int,
        unlockedAt: Date?,
        searchKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.short = short
        self.ruleId = ruleId
        self.progress = progress
        self.target = target
        self.unlockedAt = unlockedAt
        self.searchKey = searchKey ?? DexItem.buildSearchKey(name: name, short: short, id: id)
    }

    static func buildSearchKey(name: String, short: String, id: String) -> String {
        [name, short, id]
            .joined(separator: " ")
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }
}

// MARK: - Pro Tile



// MARK: - Badge

// MARK: - Progress

private struct TinyProgressBar: View {
    var fraction: Double

    var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * clamped
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [DS.Theme.accent.opacity(0.95), DS.Charts.pull.opacity(0.90)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: w)
            }
        }
        .frame(height: 6)
        .clipShape(ChamferedRectangle(.micro))
        .accessibilityLabel("Progress")
        .accessibilityValue("\((clamped * 100).safeInt) percent")
    }
}

private struct RecordRow: View {
    let icon: String; let title: String; let value: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
            Text(title).dsFont(.subheadline, weight: .semibold)
            Spacer()
            Text(value).dsFont(.footnote, monospacedDigits: true).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.medium))
        .overlay(ChamferedRectangle(.medium).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Helpers

//@inline(__always)
//private func canonicalExerciseKey(from id: String) -> String { id } // adjust if you’ve got a custom canonicalizer



struct DexDetailView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2
    @Environment(\.dismiss) private var dismiss

    let item: DexItem

    private var exercise: Exercise? { repo.exercise(byID: item.id) }

    private var bestE1RM: Double? {
        guard let ex = exercise else { return nil }
        return store.bestE1RM(exercise: ex)
    }
    private var lastWorking: (reps: Int, weight: Double)? {
        guard let ex = exercise, let lw = store.lastWorkingSet(exercise: ex) else { return nil }
        return (lw.reps, lw.weightKg)
    }

    // 👇 cache instead of recomputing in a computed var
    @State private var ladder: [(r: Int, w: Double?)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let bestE1RM {
                    DexDetailSection(title: "Records") {
                        DexMetricRow(icon: "star.circle.fill", title: "Best est. 1RM", value: String(format: "%.1f kg", bestE1RM))
                        if let last = lastWorking {
                            DexMetricRow(icon: "clock.arrow.circlepath", title: "Last working", value: "\(last.reps) x \(last.weight.safeInt) kg")
                        }
                    }
                }

                DexDetailSection(title: "Rep ladder (best)") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(ladder, id: \.r) { cell in
                            VStack(spacing: 6) {
                                Text("\(cell.r) reps")
                                    .dsFont(.caption2, weight: .medium)
                                    .foregroundStyle(.secondary)
                                Text(cell.w.map { "\(Int($0)) kg" } ?? "-")
                                    .dsFont(.footnote, weight: .semibold)
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.white.opacity(0.045), in: ChamferedRectangle(.small))
                            .overlay(ChamferedRectangle(.small).stroke(DS.Semantic.border, lineWidth: 1))
                        }
                    }
                }

                if let ex = exercise {
                    VStack(spacing: 16) {
                        if let nxt = store.personalRecordAttempt(for: ex) {
                            Button {
                                store.startWorkoutIfNeeded()
                                let entryID = store.addExerciseToCurrent(ex)
                                store.updateEntrySets(entryID: entryID, sets: [
                                    SetInput(reps: nxt.reps, weight: nxt.weightKg, tag: .working, autoWeight: false)
                                ])
                                NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
                                dismiss()
                            } label: {
                                HStack {
                                    Label("Try a PR", systemImage: "bolt.fill")
                                    Spacer()
                                    Text("\(nxt.reps) × \(nxt.weightKg.safeInt) kg").monospacedDigit()
                                }
                                .dsFont(.headline, weight: .semibold)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(DS.Theme.accent, in: ChamferedRectangle(.medium))
                            }
                            .buttonStyle(.plain)
                        }

                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(height: 1)

                        Button {
                            store.startWorkoutIfNeeded()
                            _ = store.addExerciseToCurrent(ex)
                            NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
                            dismiss()
                        } label: {
                            Label("Add to current workout", systemImage: "plus.circle.fill")
                                .dsFont(.headline, weight: .medium)
                                .foregroundStyle(DS.Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(DS.Theme.cardTop, in: ChamferedRectangle(.xl))
                    .overlay(ChamferedRectangle(.xl).stroke(DS.Semantic.border, lineWidth: 1))

                    DexDetailSection(title: "Exercise") {
                        ExerciseMusclesSection(exercise: ex, focus: .full)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(shortName(item.name))
        .navigationBarTitleDisplayMode(.inline)
        .task { rebuildLadder() }                 // build once
        .onChange(of: exercise?.id) { _ in        // rebuild when switching items
            rebuildLadder()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProfileSectionIcon(
                kind: .achievementCup,
                color: item.isUnlocked ? DS.Theme.accent : .secondary
            )
            .frame(width: 48, height: 48)
            .background(
                (item.isUnlocked ? DS.Theme.accent.opacity(0.14) : Color.white.opacity(0.05)),
                in: ChamferedRectangleAlt(.medium)
            )
            .overlay(
                ChamferedRectangleAlt(.medium)
                    .stroke(item.isUnlocked ? DS.Theme.accent.opacity(0.35) : DS.Semantic.border, lineWidth: 1)
            )
            VStack(alignment: .leading) {
                Text(item.name).dsFont(.headline)
                if let when = item.unlockedAt {
                    Text("Unlocked \(when.formatted(date: .abbreviated, time: .omitted))")
                        .dsFont(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Log a working set to unlock")
                        .dsFont(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(18)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.xl))
        .overlay(ChamferedRectangle(.xl).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func rebuildLadder() {
        guard let ex = exercise else { ladder = []; return }
        ladder = (1...12).map { r in (r, store.bestWeightForExactReps(exercise: ex, reps: r)) }
    }

    private func shortName(_ s: String) -> String {
        var x = s
        if let r = x.range(of: #"\s*\(.*\)"#, options: .regularExpression) { x.removeSubrange(r) }
        let map = ["Barbell":"BB","Dumbbell":"DB","Kettlebell":"KB","Machine":"Mch","Cable":"Cbl","Smith Machine":"Smith","Incline":"Inc","Decline":"Dec","Seated":"Seat","Single-Arm":"SA","Single Arm":"SA","Single-Leg":"SL","Single Leg":"SL"]
        for (k,v) in map { x = x.replacingOccurrences(of: k, with: v) }
        return x.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DexDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .dsFont(.title3, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Theme.cardTop, in: ChamferedRectangle(.xl))
            .overlay(ChamferedRectangle(.xl).stroke(DS.Semantic.border, lineWidth: 1))
        }
    }
}

private struct DexMetricRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(DS.Theme.accent)
            Text(title)
                .dsFont(.subheadline, weight: .medium)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .dsFont(.subheadline, weight: .semibold, monospacedDigits: true)
                .foregroundStyle(.secondary)
        }
    }
}
