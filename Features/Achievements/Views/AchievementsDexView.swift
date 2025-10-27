// AchievementsDexView.swift
import SwiftUI
import SwiftData
import Combine
import Foundation


private let DexParenRegex: NSRegularExpression = try! NSRegularExpression(
    pattern: #"\s*\(.*\)"#, options: []
)



enum DexText {
    static let paren = try! NSRegularExpression(pattern: #"\s*\(.*\)"#, options: [])

    // Pure helper – not on a @MainActor type
    static func shortName(_ s: String) -> String {
        var x = s
        if let m = paren.firstMatch(in: x, options: [], range: NSRange(x.startIndex..., in: x)),
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
                                .font(.caption)
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
        .animation(.easeInOut(duration: 0.2), value: vm.isSearching)
        .navigationTitle("Achievements")
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
            vm.rebuild(exercises: repo.exercises, stamps: stamps)
        }
        .onChange(of: repo.exercises) { ex in
            vm.rebuild(exercises: ex, stamps: stamps)
        }
        .onChange(of: stamps) { s in
            vm.rebuild(exercises: repo.exercises, stamps: s)
        }
    }

    private var header: some View {
        HStack {
            Text("PR Dex").font(.headline)
            Spacer()
            Text("\(vm.unlockedCount)/\(vm.totalCount)")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.yellow, in: Capsule())
                .foregroundColor(.black)
        }
        .accessibilityLabel("Unlocked \(vm.unlockedCount) of \(vm.totalCount)")
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Records").font(.headline).padding(.top, 8)
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
        if let m = DexParenRegex.firstMatch(in: x, options: [], range: NSRange(x.startIndex..., in: x)),
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
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.95), Color.orange.opacity(0.90)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: w)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}

private struct RecordRow: View {
    let icon: String; let title: String; let value: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(value).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.quaternary))
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
        List {
            header

            if let bestE1RM {
                Section("Records") {
                    HStack {
                        Label("Best est. 1RM", systemImage: "star.circle.fill")
                        Spacer()
                        Text(String(format: "%.1f kg", bestE1RM)).monospacedDigit()
                    }
                    if let last = lastWorking {
                        HStack {
                            Label("Last working", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text("\(last.reps) × \(Int(last.weight)) kg").monospacedDigit()
                        }
                    }
                }
            }

            Section("Rep ladder (best)") {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4)) {
                    ForEach(ladder, id: \.r) { cell in
                        VStack(spacing: 4) {
                            Text("\(cell.r) reps").font(.caption2).foregroundStyle(.secondary)
                            Text(cell.w.map { "\(Int($0)) kg" } ?? "—")
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity).padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if let ex = exercise {
                Section {
                    if let nxt = nextAttempt(for: ex) {
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
                                Text("\(nxt.reps) × \(Int(nxt.weightKg)) kg").monospacedDigit()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        store.startWorkoutIfNeeded()
                        _ = store.addExerciseToCurrent(ex)
                        NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
                        dismiss()
                    } label: {
                        Label("Add to current workout", systemImage: "plus.circle.fill")
                    }
                }

                Section("Exercise") {
                    ExerciseMusclesSection(exercise: ex, focus: .full)
                }
            }
        }
        .navigationTitle(shortName(item.name))
        .task { rebuildLadder() }                 // build once
        .onChange(of: exercise?.id) { _ in        // rebuild when switching items
            rebuildLadder()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isUnlocked ? "trophy.fill" : "trophy")
                .foregroundStyle(item.isUnlocked ? .yellow : .secondary)
            VStack(alignment: .leading) {
                Text(item.name).font(.headline)
                if let when = item.unlockedAt {
                    Text("Unlocked \(when.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Log a working set to unlock")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func rebuildLadder() {
        guard let ex = exercise else { ladder = []; return }
        ladder = (1...12).map { r in (r, store.bestWeightForExactReps(exercise: ex, reps: r)) }
    }

    private func nextAttempt(for ex: Exercise) -> (reps: Int, weightKg: Double)? {
        let reps = lastWorking?.reps ?? 5
        guard var w = store.suggestedWorkingWeight(for: ex, targetReps: reps) else { return nil }
        w += 2.5
        return (reps, max(0, w))
    }

    private func shortName(_ s: String) -> String {
        var x = s
        if let r = x.range(of: #"\s*\(.*\)"#, options: .regularExpression) { x.removeSubrange(r) }
        let map = ["Barbell":"BB","Dumbbell":"DB","Kettlebell":"KB","Machine":"Mch","Cable":"Cbl","Smith Machine":"Smith","Incline":"Inc","Decline":"Dec","Seated":"Seat","Single-Arm":"SA","Single Arm":"SA","Single-Leg":"SL","Single Leg":"SL"]
        for (k,v) in map { x = x.replacingOccurrences(of: k, with: v) }
        return x.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
