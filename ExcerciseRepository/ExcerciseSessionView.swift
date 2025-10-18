//
//  ExerciseSessionView.swift
//  WRKT
//

import SwiftUI
import Foundation
import SVGView

#if canImport(UIKit)
private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
#endif

// MARK: - Theme
private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = Color(hex: "#F4E409")
}

// MARK: - Exercise session

struct ExerciseSessionView: View {
    @EnvironmentObject var store: WorkoutStore

    let exercise: Exercise
    var currentEntryID: UUID? = nil

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    @Environment(\.dismiss) private var dismiss

    @State private var sets: [SetInput] = [SetInput(reps: 10, weight: 0)]
    @State private var didPreloadExisting = false
    @State private var showEmptyAlert = false
    var returnToHomeOnSave: Bool = false
    @State private var showInfo = false
    
    @EnvironmentObject var repo: ExerciseRepository
    @State private var showDemo = false
    
    private var totalReps: Int { sets.reduce(0) { $0 + max(0, $1.reps) } }
    private var workingSets: Int { sets.filter { $0.reps > 0 }.count }

    
    //@EnvironmentObject var repo: ExerciseRepository
    // MARK: Body
    var body: some View {
        VStack(spacing: 0) {
            header
            contentList
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .scrollDismissesKeyboard(.immediately)
                // Let child gestures fire first; this won't cancel button taps
                .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
                .simultaneousGesture(DragGesture().onChanged { _ in hideKeyboard() })
            
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                PrimaryCTA(title: "Save to Current Workout") {
                    if currentEntryID == nil {
                        saveAsNewEntry()
                    } else {
                        saveToCurrent()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(Theme.bg)
            .overlay(Divider().background(Theme.border), alignment: .top)
        }
        .navigationTitle("Log Sets")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.bg.ignoresSafeArea())
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Empty workout", isPresented: $showEmptyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Add at least one set with reps to save.")
        }
        .onAppear { preloadExistingIfNeeded() }
        .onChange(of: currentEntryID) { _ in preloadExistingIfNeeded(force: true) }
    }
    
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(workingSets) sets • \(totalReps) reps")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()

            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(8)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("Exercise info")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bg)
        .overlay(Divider().background(Theme.border), alignment: .bottom)
        .sheet(isPresented: $showInfo) {
            
            ScrollView {
                if let media = repo.media(for: exercise),
                   let s = media.youtube {
                    YouTubePlayerView(url: s)      // ⬅️ pass String, not URL
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                }
                VStack(spacing: 16) {
                    OverviewCard(meta: guideMeta)
                    ExerciseMusclesSection(exercise: exercise, focus: .full)
                }
                .padding(16)
                .background(Theme.bg.ignoresSafeArea())
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var contentList: some View {
        List {
  
            
            
            SetsSection(
                sets: $sets,
                unit: unit,
                exercise: exercise,
                onDelete: { idx in sets.remove(at: idx) },
           
                onDuplicate: { idx in duplicateSet(at: idx) },
                onAdd: {
                    let last = sets.last ?? SetInput(reps: 10, weight: 0)
                    sets.append(SetInput(
                        reps: last.reps,
                        weight: last.weight,
                        tag: last.tag,                       // keep the type
                        autoWeight: last.autoWeight,         // keep auto state
                        didSeedFromMemory: false             // reset seed for a new row
                    ))
                }
            )

          //  MusclesListSection(exercise: exercise)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
    }
    
    // MARK: Overview
    private struct OverviewSection: View {
        let meta: ExerciseGuideMeta
        var body: some View {
            Section {
                OverviewCard(meta: meta)
                    .listRowInsets(.init(top: 0, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Theme.bg)
                    .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: Sets
    private struct SetsSection: View {
        @Binding var sets: [SetInput]
        @EnvironmentObject private var store: WorkoutStore   // ✅ add this

        let unit: WeightUnit
        let exercise: Exercise
        let onDelete: (Int) -> Void
        let onDuplicate: (Int) -> Void
        let onAdd: () -> Void

        var body: some View {
            Section {
                // Sets list
                ForEach(Array(sets.indices), id: \.self) { i in
                    SetRowUnified(
                        index: i + 1,
                        set: $sets[i],
                        unit: unit,
                        exercise: exercise,
                        onDuplicate: { onDuplicate(i) }
                    )
                    .listRowInsets(.init(top: 8, leading: 6, bottom: 8, trailing: 6))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { onDelete(i) }
                        Button("Duplicate") { onDuplicate(i) }
                    }
                }

                // Quick actions footer
                VStack(spacing: 12) {
                    // Quick preset buttons
                    HStack(spacing: 12) {
                        PresetButton(title: "Use Last", icon: "clock.arrow.circlepath") {
                            useLast()
                        }
                        
                        PresetButton(title: "5×5", icon: "number.circle") {
                            applyFiveByFive()
                        }
                        
                        Spacer()
                        
                        // Add set button
                        Button(action: onAdd) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Set")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.accent.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(.init(top: 16, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.bg)
                
            } header: {
                HStack(spacing: 8) {
                    Text("Sets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                    
                    Spacer()
                    
                    // Set counter badge
                    HStack(spacing: 6) {
                        Text("\(sets.count)")
                            .font(.caption.monospacedDigit().weight(.medium))
                        Text(sets.count == 1 ? "set" : "sets")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Theme.bg)
            }
        }

        private func useLast() {
            // Your existing useLast implementation
            if let lastWorkingSet = store.lastWorkingSet(exercise: exercise) {
                sets.append(SetInput(
                    reps: lastWorkingSet.reps,
                    weight: lastWorkingSet.weightKg,
                    tag: .working,
                    autoWeight: true,
                    didSeedFromMemory: true
                ))
            }
        }

        private func applyFiveByFive() {
            // Clear existing sets and add 5 working sets
            sets = (1...5).map { _ in
                SetInput(reps: 5, weight: 0, tag: .working, autoWeight: true)
            }
        }
    }

    // Supporting view for preset buttons
    private struct PresetButton: View {
        let title: String
        let icon: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption.weight(.medium))
                    Text(title)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface2)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private struct PresetsRow: View {
        var onUseLast: () -> Void
        var onFiveByFive: () -> Void
        var body: some View {
            HStack(spacing: 8) {
                PresetChip(title: "Use last"); PresetChip(title: "5×5")
            }
            .onTapGesture { /* no-op */ }
        }
        private func PresetChip(title: String) -> some View {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surface2, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
    }

    private struct SetRowCompactWrapper: View {
        @Binding var set: SetInput
        let index: Int
        let unit: WeightUnit
        let exercise: Exercise
        let onDelete: () -> Void
        let onDuplicate: () -> Void

        var body: some View {
            SetRowCompact(
                index: index,
                set: $set,                     // 👈 pass the whole set
                unit: unit,
                exercise: exercise,
                onDuplicate: onDuplicate
            )
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.surface)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Duplicate", action: onDuplicate)
            }
        }
    }

    // MARK: Muscles section
    private struct MusclesListSection: View {
        let exercise: Exercise
        var body: some View {
            Section {
                ExerciseMusclesSection(exercise: exercise, focus: .full)
                    .listRowInsets(.init(top: 0, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.bg)
            } header: {
                Text("Muscles worked")
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Helpers
    private func cleaned(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty, t.lowercased() != "nan" else { return nil }
        return t
    }
    private func firstNonEmpty(_ values: String?...) -> String {
        for v in values { if let t = cleaned(v) { return t } }
        return ""
    }

    // Build the lightweight meta from your current Exercise model
    private var guideMeta: ExerciseGuideMeta {
        let difficulty = firstNonEmpty(exercise.level)
        let equipment  = firstNonEmpty(exercise.equipment, "Bodyweight")
        let classif    = firstNonEmpty(exercise.category)
        let mechanics  = firstNonEmpty(exercise.mechanic)
        let forceType  = firstNonEmpty(exercise.force)
        let grip       = firstNonEmpty(exercise.grip)    // optional on Exercise

        // Not stored in Exercise yet; leave empty so they’re filtered
        let pattern = "", plane = "", posture = "", laterality = ""

        var cues: [String] = []
        if mechanics.lowercased() == "isolation" { cues.append("Control the eccentric; avoid swinging.") }
        if mechanics.lowercased() == "compound"  { cues.append("Brace your core; keep ribs down.") }
        if forceType.lowercased() == "pull"      { cues.append("Initiate the pull without shrugging your shoulders.") }
        if !equipment.isEmpty && equipment.lowercased().contains("cable") {
            cues.append("Use a steady tempo (e.g., 3-1-1) to keep tension on the target muscle.")
        }
        if !grip.isEmpty { cues.append(gripCue(for: grip)) }

        return ExerciseGuideMeta(
            difficulty: difficulty,
            equipment: equipment,
            classification: classif,
            mechanics: mechanics,
            forceType: forceType,
            pattern: pattern,
            plane: plane,
            posture: posture,
            grip: grip,
            laterality: laterality,
            cues: cues
        )
    }

    private func gripCue(for grip: String) -> String {
        let g = grip.lowercased()
        switch true {
        case g.contains("pronated"):
            return "Pronated grip: palms away—keep wrists straight and elbows ~45°."
        case g.contains("supinated"):
            return "Supinated grip: palms toward you—tuck elbows; avoid wrist extension."
        case g.contains("neutral"):
            return "Neutral grip: palms facing—stack wrists under forearms and don’t flare."
        case g.contains("mixed"):
            return "Mixed grip: rotate sides between sets and keep both wrists neutral."
        case g.contains("hook"):
            return "Hook grip: thumb under fingers—keep wrist straight to reduce strain."
        default:
            return "Use a \(grip) grip and keep wrists neutral—not bent back."
        }
    }

    // MARK: Actions
    private func duplicateSet(at index: Int) {
        guard sets.indices.contains(index) else { return }
        let s = sets[index]
        sets.append(s) // preserves tag/auto/didSeed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func preloadExistingIfNeeded(force: Bool = false) {
        guard let id = currentEntryID else { return }
        guard force || !didPreloadExisting else { return }
        if let existing = store.currentWorkout?.entries.first(where: { $0.id == id })?.sets,
           !existing.isEmpty {
            sets = existing
        }
        didPreloadExisting = true
    }

    private func cleanSets() -> [SetInput] {
        sets.map {
            var s = $0
            s.reps = max(0, s.reps)
            s.weight = max(0, s.weight)
            return s
        }
    }

    // ExerciseSessionView.swift

    private func saveAsNewEntry() {
        let entryID = store.addExerciseToCurrent(exercise)
        let clean = cleanSets()
        if clean.contains(where: { $0.reps > 0 || $0.weight > 0 }) {
            store.updateEntrySets(entryID: entryID, sets: clean)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()

        if returnToHomeOnSave {
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
           // NotificationCenter.default.post(name: .resetHomeToRoot, object: nil)  // ⬅️ go to Home root
            AppBus.postResetHome(reason: .user_intent)
        } else {
            NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
        }
    }

    private func saveToCurrent() {
        guard let entryID = currentEntryID else { return }
        let clean = cleanSets()
        store.updateEntrySets(entryID: entryID, sets: clean)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()

        if returnToHomeOnSave {
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
           // NotificationCenter.default.post(name: .resetHomeToRoot, object: nil)  // ⬅️ already correct pattern
            AppBus.postResetHome(reason: .user_intent)
        } else {
            NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
        }
    }
}

// MARK: - Overview card (chips + tips)

private struct ExerciseGuideMeta: Hashable {
    let difficulty: String
    let equipment: String
    let classification: String
    let mechanics: String
    let forceType: String
    let pattern: String
    let plane: String
    let posture: String
    let grip: String
    let laterality: String
    let cues: [String]
}

private struct OverviewCard: View {
    let meta: ExerciseGuideMeta
    @State private var showAllTips = false

    var chips: [ChipItem] {
        var c: [ChipItem] = []
        if !meta.difficulty.isEmpty   { c.append(.init(icon: "dial.medium.fill", label: meta.difficulty)) }
        if !meta.equipment.isEmpty    { c.append(.init(icon: "dumbbell.fill",    label: meta.equipment)) }
        if !meta.mechanics.isEmpty    { c.append(.init(icon: "gearshape",        label: meta.mechanics)) }
        if !meta.forceType.isEmpty    { c.append(.init(icon: "arrow.left.arrow.right", label: meta.forceType)) }
        if !meta.grip.isEmpty         { c.append(.init(icon: "hand.raised.fill", label: meta.grip)) }
        if !meta.classification.isEmpty { c.append(.init(icon: "tag.fill",       label: meta.classification)) }
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Chips (horizontal, unobtrusive)
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { ChipView(item: $0) }
                    }
                    .padding(.vertical, 6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                )
                .padding(.top, 2)
                .padding(.bottom, 2)
                .padding(.horizontal, 0)
            }

            // Technique tips
            if !meta.cues.isEmpty {
                Text("Technique tips")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondary)

                let tips = Array(meta.cues.prefix(showAllTips ? meta.cues.count : 3))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tips, id: \.self) { cue in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "lightbulb")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(cue)
                                .foregroundStyle(.white.opacity(0.92))
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if meta.cues.count > 3 {
                        Button(showAllTips ? "Show less" : "Show more") {
                            withAnimation(.easeInOut(duration: 0.18)) { showAllTips.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    struct ChipItem: Identifiable, Hashable { let id = UUID(); let icon: String; let label: String }
    private struct ChipView: View {
        let item: ChipItem
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: item.icon).font(.caption.weight(.semibold))
                Text(item.label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
    }
}

// MARK: - Sets row (unchanged UX)



private struct TagDotCycler: View {
    @Binding var tag: SetTag
    var body: some View {
        Button {
            cycle()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tag.color).frame(width: 10, height: 10)
                Text(tag.short)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 0.75))
        }
        .buttonStyle(.plain) // ✅ important
        .contextMenu {
            ForEach(SetTag.allCases, id: \.self) { t in Button(t.label) { tag = t } }
        }
        .accessibilityLabel("Set type \(tag.label)")
    }

    private func cycle() {
        let all = SetTag.allCases
        if let idx = all.firstIndex(of: tag) {
            let next = all.index(after: idx)
            tag = next < all.endIndex ? all[next] : all.first!
        } else { tag = .working }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// OLD : TO DELETE


private struct TokenStepperInt: View {
    let title: String
    @Binding var value: Int
    let lower: Int
    let upper: Int
    var onChange: () -> Void = {}

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                CircleButton("−") { bump(-1) }
                    .layoutPriority(2)                      // ← keep visible
                Text("\(value)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)               // ← allow shrink
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)            // ← flexible middle
                CircleButton("+") { bump(+1) }
                    .layoutPriority(2)                      // ← keep visible
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func bump(_ delta: Int) {
        let newValue = min(upper, max(lower, value + delta))
        guard newValue != value else { return }
        value = newValue
        onChange()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct TokenStepperDouble: View {
    let title: String
    @Binding var valueDisplay: Double
    let step: Double
    var suffix: String = ""
    var onManualEdit: () -> Void = {}

    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                CircleButton("−") { bump(-step) }
                    .layoutPriority(2)

                Group {
                    if editing {
                        TextField("0",
                                  value: $valueDisplay,
                                  format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .multilineTextAlignment(.center)
                            .onChange(of: valueDisplay) { _ in onManualEdit() }
                            .onChange(of: focused) { if !$0 { editing = false } }
                            .onAppear { focused = true }
                    } else {
                        Text("\(valueDisplay, specifier: "%.1f") \(suffix)")
                            .onTapGesture { editing = true }
                    }
                }
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)

                CircleButton("+") { bump(+step) }
                    .layoutPriority(2)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        }
        .toolbar {
            if editing {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("Done") { focused = false; editing = false }
                }
            }
        }
    }

    private func bump(_ delta: Double) {
        let newValue = max(0, valueDisplay + delta)
        guard newValue != valueDisplay else { return }
        valueDisplay = newValue
        onManualEdit()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct CircleButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain) // ✅ prevents list/row interference
            .font(.headline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 32, height: 32)
            .background(Theme.accent.opacity(0.16), in: Circle())
            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            .contentShape(Circle())
    }
}

// END OLD: TO BE DELETED

//NEW TEST

// MARK: - Compact capsule steppers (fully constrained, no overflow)

private struct CapsuleStepperInt: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var onChange: () -> Void = {}

    // tuning
    private let hPad: CGFloat = 6
    private let capW: CGFloat = 34
    private let capH: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)

            // Base capsule
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .frame(height: 36)
                // Center value gets full width minus reserved edges
                .overlay(
                    Text("\(value)")
                        .font(.headline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, capW + hPad) // reserve space for the two buttons
                        .frame(maxWidth: .infinity),
                    alignment: .center
                )
                // Left (-)
                .overlay(alignment: .leading) {
                    StepCap(systemName: "minus", width: capW, height: capH) { bump(-1) }
                        //.padding(.leading, hPad)
                }
                // Right (+)
                .overlay(alignment: .trailing) {
                    StepCap(systemName: "plus", width: capW, height: capH) { bump(+1) }
                        //.padding(.trailing, hPad)
                }
        }
    }

    private func bump(_ delta: Int) {
        let newValue = (value + delta).clamped(to: range)
        guard newValue != value else { return }
        value = newValue
        onChange()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct CapsuleStepperDouble: View {
    let title: String
    @Binding var valueDisplay: Double
    let step: Double
    var suffix: String = ""
    var onManualEdit: () -> Void = {}

    @State private var editing = false
    @FocusState private var focused: Bool

    // tuning
    private let hPad: CGFloat = 6
    private let capW: CGFloat = 34
    private let capH: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .frame(height: 36)
                // Center: value or text field
                .overlay(
                    Group {
                        if editing {
                            TextField("0",
                                      value: $valueDisplay,
                                      format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .focused($focused)
                                .multilineTextAlignment(.center)
                                .onChange(of: focused) { if !$0 { editing = false } }
                                .onChange(of: valueDisplay) { _ in onManualEdit() }
                        } else {
                            Text("\(valueDisplay, specifier: "%.1f") \(suffix)")
                                .onTapGesture { editing = true }
                        }
                    }
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, capW + hPad) // reserve edges
                    .frame(maxWidth: .infinity),
                    alignment: .center
                )
                .overlay(alignment: .leading) {
                    StepCap(systemName: "minus", width: capW, height: capH) { bump(-step) }
                        //.padding(.leading, hPad)
                }
                .overlay(alignment: .trailing) {
                    StepCap(systemName: "plus", width: capW, height: capH) { bump(+step) }
                       // .padding(.trailing, hPad)
                }
        }
        .toolbar {
            if editing {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("Done") { focused = false; editing = false }
                }
            }
        }
    }

    private func bump(_ delta: Double) {
        let newValue = max(0, valueDisplay + delta)
        guard newValue != valueDisplay else { return }
        valueDisplay = newValue
        onManualEdit()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// Small, square edge buttons (denser than circles; no layout grab)
private struct StepCap: View {
    let systemName: String
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.text)
                .frame(width: width, height: height)
                .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
// ENDNEWTEST

private struct SetRowUnified: View {
    let index: Int
       @Binding var set: SetInput
       let unit: WeightUnit
       let exercise: Exercise
       let onDuplicate: () -> Void

       @EnvironmentObject private var store: WorkoutStore

       private let defaultWorkingReps = 10
       private var step: Double { unit == .kg ? 2.5 : 5 }
       private var displayWeight: Double { unit == .kg ? set.weight : (set.weight * 2.20462) }

       var body: some View {
           HStack(spacing: 8) {
               Text("\(index)")
                   .font(.caption.weight(.semibold))
                   .foregroundStyle(Theme.secondary)
                   .frame(width: 18, alignment: .leading)

               // let the tag size to content (no fixed width)
               TagDotCycler(tag: $set.tag)
                   .fixedSize(horizontal: true, vertical: false)

               // Reps
               CapsuleStepperInt(
                   title: "Reps",
                   value: $set.reps,
                   range: 0...500,
                   onChange: { if set.tag == .working, set.autoWeight { applyWeightSuggestion() } }
               )
               .frame(maxWidth: .infinity)
               .layoutPriority(1)

               // Weight
               CapsuleStepperDouble(
                   title: "Weight",
                   valueDisplay: Binding(
                       get: { displayWeight },
                       set: { newDisplay in
                           let kg = (unit == .kg) ? max(0, newDisplay) : max(0, newDisplay / 2.20462)
                           set.weight = kg
                       }
                   ),
                   step: step,
                   suffix: unit.rawValue,
                   onManualEdit: { set.autoWeight = false }
               )
               .frame(maxWidth: .infinity)
               .layoutPriority(1)
           }
           .padding(.vertical, 8)
           .contextMenu { Button("Duplicate") { onDuplicate() } }
           .onAppear {
               seedFromMemoryIfNeeded()
               if set.tag == .working { applyWeightSuggestion() }
           }
       }

    private func seedFromMemoryIfNeeded() {
        guard set.tag == .working, set.autoWeight, !set.didSeedFromMemory else { return }
        let looksEmpty = (set.reps == 0 && set.weight == 0)
        guard looksEmpty else { return }
        if let last = store.lastWorkingSet(exercise: exercise) {
            set.reps = last.reps
            set.weight = last.weightKg
            set.didSeedFromMemory = true
            return
        }
        set.reps = (set.reps > 0) ? set.reps : defaultWorkingReps
        set.didSeedFromMemory = true
    }

    private func applyWeightSuggestion() {
        guard set.autoWeight else { return }
        if set.reps <= 0 { set.reps = defaultWorkingReps }
        if let w = store.suggestedWorkingWeight(for: exercise, targetReps: set.reps) {
            let snapped: Double
            if unit == .kg {
                snapped = (w / step).rounded() * step
            } else {
                let lb = w * 2.20462
                snapped = ((lb / step).rounded() * step) / 2.20462
            }
            set.weight = max(0, snapped)
        }
    }
}// ExerciseSessionView.swift — replace SetRowCompact with this version

private struct SetRowCompact: View {
    let index: Int
    @Binding var set: SetInput
    let unit: WeightUnit
    let exercise: Exercise
    let onDuplicate: () -> Void

    @EnvironmentObject private var store: WorkoutStore

    private let defaultWorkingReps = 10
    private var step: Double { unit == .kg ? 2.5 : 5 }
    private var displayWeight: Double { unit == .kg ? set.weight : (set.weight * 2.20462) }

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(index)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, alignment: .leading)

            // 👇 Tag chip: tap to cycle, long-press for menu
            TagCycler(tag: $set.tag)
                .onChange(of: set.tag) { newTag in
                    if newTag == .working {
                        seedFromMemoryIfNeeded()
                        applyWeightSuggestion()
                    }
                }

            // Reps
            CompactStepperInt(value: $set.reps, label: "Reps", lower: 0, upper: 500)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: set.reps) { _ in
                       if set.tag == .working, set.autoWeight {
                           applyWeightSuggestion() // weight only
                       }
                   }

            // Weight
            CompactStepperDouble(
                valueDisplay: Binding(
                    get: { displayWeight },
                    set: { newDisplay in
                        let kg = (unit == .kg) ? max(0, newDisplay) : max(0, newDisplay / 2.20462)
                        set.weight = kg
                    }
                ),
                step: step,
                  label: "Weight",
                  suffix: unit.rawValue,
                  onManualEdit: { set.autoWeight = false }
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .contextMenu { Button("Duplicate") { onDuplicate() } }
        .onAppear {
            // First render: if this is a working set and still auto, suggest now.
            if set.tag == .working { applySuggestionsIfAllowed() }
        }
        .onAppear {
                    seedFromMemoryIfNeeded()
                    if set.tag == .working { applyWeightSuggestion() }
                }
    }
    
    private func seedFromMemoryIfNeeded() {
          guard set.tag == .working, set.autoWeight, !set.didSeedFromMemory else { return }
          // only seed when the set looks “empty”
          let looksEmpty = (set.reps == 0 && set.weight == 0)
          guard looksEmpty else { return }

          if let last = store.lastWorkingSet(exercise: exercise) {
              set.reps = last.reps
              set.weight = last.weightKg
              set.didSeedFromMemory = true
              return
          }
          // fallback seed: reps only
          set.reps = (set.reps > 0) ? set.reps : defaultWorkingReps
          set.didSeedFromMemory = true
      }

      // 👇 rename & update: only compute WEIGHT based on CURRENT reps.
      private func applyWeightSuggestion() {
          guard set.autoWeight else { return }

          // If reps is zero, give a gentle default
          if set.reps <= 0 { set.reps = defaultWorkingReps }

          if let w = store.suggestedWorkingWeight(for: exercise, targetReps: set.reps) {
              let snapped: Double
              if unit == .kg {
                  snapped = (w / step).rounded() * step
              } else {
                  let lb = w * 2.20462
                  snapped = ((lb / step).rounded() * step) / 2.20462
              }
              set.weight = max(0, snapped)
          }
      }

    private func applySuggestionsIfAllowed() {
        guard set.autoWeight else { return }

        // 1) If we have a very recent working set, prefer copying both reps & weight.
        if let last = store.lastWorkingSet(exercise: exercise) {
            set.reps = last.reps
            set.weight = last.weightKg     // ✅
            return
        }

        // 2) Otherwise, choose reps then weight conservatively.
        if set.reps <= 0 { set.reps = defaultWorkingReps }

        if let w = store.suggestedWorkingWeight(for: exercise, targetReps: set.reps) {
            // snap to step for nicer UX
            let snapped: Double
            if unit == .kg {
                snapped = (w / step).rounded() * step
            } else {
                let lb = w * 2.20462
                snapped = ((lb / step).rounded() * step) / 2.20462
            }
            set.weight = max(0, snapped)
        }
    }
}

// ExerciseSessionView.swift — add this helper view near the other small views

private struct TagCycler: View {
    @Binding var tag: SetTag

    var body: some View {
        let label = tag.label
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tag.color, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 0.75))
            .onTapGesture { cycle() }
            .contextMenu {
                ForEach(SetTag.allCases, id: \.self) { t in
                    Button(t.label) { tag = t }
                }
            }
            .accessibilityLabel("Set type \(label)")
    }

    private func cycle() {
        let all = SetTag.allCases
        if let idx = all.firstIndex(of: tag) {
            let next = all.index(after: idx)
            tag = next < all.endIndex ? all[next] : all.first!
        } else {
            tag = .working
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Compact steppers

private struct CompactStepperInt: View {
    @Binding var value: Int
    let label: String
    let lower: Int
    let upper: Int

    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
                .frame(width: 30, alignment: .leading)

            HStack(spacing: 0) {
                Button { bump(-1) } label: { Text("−").font(.headline) }
                    .buttonStyle(CompactKnobStyle())

                Group {
                    if editing {
                        TextField("", value: $value, format: .number)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .onChange(of: focused) { if !$0 { editing = false } }
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 34, maxWidth: 48)
                            .onAppear { focused = true }
                    } else {
                        Text("\(value)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .frame(minWidth: 34, maxWidth: 48)
                            .onTapGesture { editing = true }
                    }
                }
                .padding(.horizontal, 6)

                Button { bump(+1) } label: { Text("+").font(.headline) }
                    .buttonStyle(CompactKnobStyle())
            }
            .pillBackground()
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .toolbar {
            if editing {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focused = false
                        editing = false
                    }
                }
            }
        }
    }

    private func bump(_ delta: Int) {
        let newValue = min(upper, max(lower, value + delta))
        if newValue != value {
            value = newValue
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// ExerciseSessionView.swift — update CompactStepperDouble signature & call sites

private struct CompactStepperDouble: View {
    @Binding var valueDisplay: Double
    let step: Double
    let label: String
    var suffix: String = ""
    var onManualEdit: () -> Void = {}    // 👈 add this

    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
                .frame(width: 38, alignment: .leading)

            HStack(spacing: 0) {
                Button {
                    bump(-step)
                    onManualEdit()            // 👈 notify
                } label: { Text("−").font(.headline) }
                .buttonStyle(CompactKnobStyle())

                Group {
                    if editing {
                        TextField("",
                                  value: $valueDisplay,
                                  format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .onChange(of: focused) { if !$0 { editing = false } }
                            .onChange(of: valueDisplay) { _ in onManualEdit() } // 👈 typing -> manual
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 56, maxWidth: 74)
                            .onAppear { focused = true }
                    } else {
                        Text("\(valueDisplay, specifier: "%.1f")\(suffix.isEmpty ? "" : " \(suffix)")")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .frame(minWidth: 56, maxWidth: 74)
                            .minimumScaleFactor(0.9)
                            .lineLimit(1)
                            .onTapGesture { editing = true }
                    }
                }
                .padding(.horizontal, 6)

                Button {
                    bump(+step)
                    onManualEdit()            // 👈 notify
                } label: { Text("+").font(.headline) }
                .buttonStyle(CompactKnobStyle())
            }
            .pillBackground()
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .toolbar {
            if editing {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focused = false
                        editing = false
                    }
                }
            }
        }
    }

    private func bump(_ delta: Double) {
        let newValue = max(0, valueDisplay + delta)
        if newValue != valueDisplay {
            valueDisplay = newValue
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Common styles

private struct PillBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border.opacity(0.9), lineWidth: 0.75))
    }
}
private extension View { func pillBackground() -> some View { modifier(PillBackground()) } }

private struct CompactKnobStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 28, height: 28)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.26 : 0.18), in: Circle())
            .shadow(color: Theme.accent.opacity(configuration.isPressed ? 0.35 : 0.22),
                    radius: configuration.isPressed ? 6 : 4, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - CTA

private struct PrimaryCTA: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(.headline)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Muscles section (your existing visuals)

private enum MusclesTheme {
    static let surface  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border   = Color.white.opacity(0.10)
    static let headline = Color.white.opacity(0.65)
}

struct ExerciseMusclesSection: View {
    let exercise: Exercise
    var focus: SVGHumanBodyView.Focus = .full

    private var primary: Set<String> { Set(exercise.primaryMuscles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }
    private var secondary: Set<String> { Set(exercise.secondaryMuscles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }
    private var tertiary: Set<String> { Set(exercise.tertiaryMuscles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MusclesTheme.surface)
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MusclesTheme.border, lineWidth: 1)

            HStack(spacing: 12) {
                SVGHumanBodyView(side: .front, focus: focus, primary: primary, secondary: secondary, tertiary: tertiary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.56, contentMode: .fit)
                SVGHumanBodyView(side: .back,  focus: focus, primary: primary, secondary: secondary, tertiary: tertiary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.56, contentMode: .fit)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SVG body + lexicon (unchanged from your version)

struct SVGHumanBodyView: View {
    enum Side  { case front, back }
    enum Focus { case full, upper, lower }

    var side: Side
    var focus: Focus = .full
    var primary: Set<String> = []
    var secondary: Set<String> = []
    var tertiary: Set<String> = []

    private var highlightKey: String {
        (primary.sorted().joined(separator: ",")) + "|" +
        (secondary.sorted().joined(separator: ",")) + "|" +
        (tertiary.sorted().joined(separator: ","))
    }

    private enum Heatmap {
        static let primaryName   = "mediumorchid"
        static let secondaryName = "orchid"
        static let tertiaryName  = "mediumpurple"
        static let primaryAlpha:   Double = 0.95
        static let secondaryAlpha: Double = 0.55
        static let tertiaryAlpha:  Double = 0.30
    }

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: side == .front ? "torso" : "torso_back",
                                         withExtension: "svg") {
                let svg = SVGView(contentsOf: url)
                svg
                    .aspectRatio(contentMode: .fit)
                    .mask(maskForFocus())
                    .onAppear { DispatchQueue.main.async { applyHighlights(into: svg) } }
                    .onChange(of: highlightKey) { _ in DispatchQueue.main.async { applyHighlights(into: svg) } }
                    .onChange(of: side) { _ in DispatchQueue.main.async { applyHighlights(into: svg) } }
                    .onChange(of: focus) { _ in DispatchQueue.main.async { applyHighlights(into: svg) } }
            } else {
                Rectangle().fill(.secondary.opacity(0.15))
                    .overlay(Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary))
                    .aspectRatio(0.56, contentMode: .fit)
                    .mask(maskForFocus())
            }
        }
    }

    @ViewBuilder
    private func maskForFocus() -> some View {
        GeometryReader { geo in
            let size = geo.size
            let rect: CGRect = {
                switch focus {
                case .full:  return CGRect(origin: .zero, size: size)
                case .upper: return CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.58)
                case .lower: return CGRect(x: 0, y: size.height * 0.42, width: size.width, height: size.height * 0.58)
                }
            }()
            Path { $0.addRect(rect) }.fill(Color.white)
        }
    }

    private func applyHighlights(into root: SVGView) {
        let pTokens = Array(primary).flatMap { MuscleLexicon.tokens(for: $0) }
        let sTokens = Array(secondary).flatMap { MuscleLexicon.tokens(for: $0) }
        let tTokens = Array(tertiary).flatMap { MuscleLexicon.tokens(for: $0) }

        let idx = MuscleIndex.shared
        var pIDs = Set(idx.ids(forClassTokens: pTokens, side: side))
        var sIDs = Set(idx.ids(forClassTokens: sTokens, side: side))
        var tIDs = Set(idx.ids(forClassTokens: tTokens, side: side))

        sIDs.subtract(pIDs)
        tIDs.subtract(pIDs); tIDs.subtract(sIDs)

        color(ids: Array(tIDs), in: root, colorName: Heatmap.tertiaryName, opacity: Heatmap.tertiaryAlpha)
        color(ids: Array(sIDs), in: root, colorName: Heatmap.secondaryName, opacity: Heatmap.secondaryAlpha)
        color(ids: Array(pIDs), in: root, colorName: Heatmap.primaryName,   opacity: Heatmap.primaryAlpha)
    }

    private func paint(_ node: SVGNode, colorName: String, targetOpacity: Double) {
        if let shape = node as? SVGShape {
            shape.fill = SVGColor.by(name: colorName)
            shape.opacity = targetOpacity
        } else if let group = node as? SVGGroup {
            group.opacity = max(group.opacity, targetOpacity)
            for child in group.contents { paint(child, colorName: colorName, targetOpacity: targetOpacity) }
        } else {
            node.opacity = max(node.opacity, targetOpacity)
        }
    }
    private func color(ids: [String], in root: SVGView, colorName: String, opacity: Double) {
        for id in ids { if let node = root.getNode(byId: id) { paint(node, colorName: colorName, targetOpacity: opacity) } }
    }
}

private enum MuscleLexicon {
    static func tokens(for raw: String) -> [String] {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: Set<String> = [base, base.replacingOccurrences(of: " ", with: "-"), singularize(base)]
        switch base {
        case "pectoralis major", "pectoralis-major", "chest", "pecs", "pectorals":
            out.formUnion(["pectoralis-major-clavicular","pectoralis-major","chest","pec"])
        case "pectoralis minor", "pectoralis-minor":
            out.formUnion(["pectoralis-minor","chest","pec"])
        case "triceps brachii", "triceps-brachii", "triceps":
            out.formUnion(["triceps","triceps-long","triceps-lateral","triceps-medial"])
        case "biceps brachii", "biceps-brachii":
            out.formUnion(["biceps-brachii-long","biceps-brachii-short","biceps"])
        case "biceps brachii long", "biceps-brachii-long":
            out.formUnion(["biceps-brachii-long","biceps"])
        case "biceps brachii short", "biceps-brachii-short":
            out.formUnion(["biceps-brachii-short","biceps"])
        case "biceps", "bicep":
            out.formUnion(["biceps","biceps-brachii-long","biceps-brachii-short"])
        case "brachialis": out.formUnion(["brachialis"])
        case "brachioradialis": out.formUnion(["brachioradialis"])
        case "forearm flexors", "forearm-flexors", "wrist flexors":
            out.formUnion(["forearm-flexors-1","forearm-flexors-2","forearm-flexors"])
        case "forearm extensors", "forearm-extensors", "wrist extensors":
            out.formUnion(["forearm-extensors","forearm-extensors-1","forearm-extensors-2","forearm-extensors-3"])
        case "supinator": out.formUnion(["supinator"])
        case "deltoid anterior", "anterior deltoid", "anterior deltoids", "deltoid-anterior", "front delts", "front delt":
            out.formUnion(["deltoid-anterior","deltoid","deltoids"])
        case "deltoid posterior", "posterior deltoid", "posterior deltoids", "rear delts", "rear delt", "deltoid-posterior":
            out.formUnion(["deltoid-posterior"])
        case "latissimus dorsi", "lat", "lats", "latissimus-dorsi":
            out.formUnion(["latissimus-dorsi","lats"])
        case "obliques", "external oblique", "internal oblique", "oblique":
            out.formUnion(["obliques"])
        case "rectus abdominis", "abs", "abdominals", "rectus-abdominis":
            out.formUnion(["rectus-abdominis","abs","abdominals"])
        case "serratus anterior", "serratus-anterior":
            out.formUnion(["serratus-anterior"])
        case "subscapularis": out.formUnion(["subscapularis"])
        case "trapezius upper", "upper traps", "trapezius-upper":
            out.formUnion(["trapezius-upper","trapezius","traps"])
        case "trapezius middle", "middle traps", "mid traps", "trapezius-middle":
            out.formUnion(["trapezius-middle"])
        case "trapezius lower", "lower traps", "trapezius-lower":
            out.formUnion(["trapezius-lower"])
        case "splenius", "splenius capitis", "splenius cervicis":
            out.formUnion(["splenius"])
        case "levator scapulae", "levator-scapulae":
            out.formUnion(["levator-scapulae"])
        case "rhomboid", "rhomboids", "rhomboid major", "rhomboid minor":
            out.formUnion(["rhomboid"])
        case "infraspinatus", "teres minor", "teres-minor", "infraspinatus-teres-minor":
            out.formUnion(["infraspinatus-teres-minor","infraspinatus","teres-minor"])
        case "supraspinatus": out.formUnion(["supraspinatus"])
        case "erector spinae", "erectors", "spinal erectors", "erector-spinae":
            out.formUnion(["erector-spinae"])
        case "quadratus lumborum", "quadratus-lumborum":
            out.formUnion(["quadratus-lumborum"])
        case "deep external rotators", "deep-external-rotators", "external rotators":
            out.formUnion(["deep-external-rotators"])
        case "quadriceps", "quads", "quadriceps femoris":
            out.formUnion(["quadriceps","quadriceps-1","quadriceps-2","quadriceps-3","quadriceps-4"])
        case "adductor magnus", "adductor-longus", "adductor longus",
             "adductor brevis", "adductor-brevis",
             "gracilis", "pectineus":
            out.formUnion(["adductors", "hip-adductors", "hip-adductors-1", "hip-adductors-2"])
        case "hip flexors", "hip-flexors": out.formUnion(["hip-flexors"])
        case "abductors", "abductor", "tfl": out.formUnion(["abductors"])
        case "gluteus maximus", "glute max", "gluteus-maximus":
            out.formUnion(["gluteus-maximus"])
        case "hamstrings", "hamstring", "posterior thigh", "posterior-thigh":
            out.formUnion(["hamstrings"])
        case "biceps femoris", "biceps-femoris":
            out.formUnion(["hamstrings","hamstring","biceps-femoris"])
        case "semitendinosus", "semi-tendinosus":
            out.formUnion(["hamstrings","semitendinosus"])
        case "semimembranosus", "semi-membranosus":
            out.formUnion(["hamstrings","semimembranosus"])
        case "gastrocnemius": out.formUnion(["gastrocnemius"])
        case "soleus": out.formUnion(["soleus"])
        case "tibialis anterior", "tibialis-anterior":
            out.formUnion(["tibialis-anterior"])
        default: break
        }
        return Array(out)
    }
    static func idCandidates(forTokens tokens: [String]) -> [String] {
        var ids = Set<String>()
        let sides = ["", "-l", "-r", "-L", "-R", "-left", "-right"]
        let planes = ["", "-front", "-back", "-anterior", "-posterior"]
        let copies = (0...20).map { "-\($0)" } + [""]
        for t in tokens {
            let base = t.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().replacingOccurrences(of: "_", with: "-")
                .replacingOccurrences(of: " ", with: "-")
            let singular = base.hasSuffix("s") ? String(base.dropLast()) : base
            let forms = Set([base, singular])
            for form in forms {
                for s in sides { for p in planes { for c in copies {
                    ids.insert("\(form)\(s)\(p)\(c)")
                    ids.insert("\(form)\(p)\(s)\(c)")
                }}}
            }
        }
        return Array(ids)
    }
    private static func singularize(_ s: String) -> String {
        if s.hasSuffix("s") { return String(s.dropLast()) }
        return s
    }
}

// MARK: - Small helpers

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:(a, r, g, b) = (255, 244, 228, 9)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}


