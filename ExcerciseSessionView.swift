//
//  ExerciseSessionView.swift
//  WRKT
//

import SwiftUI
import Foundation
import SVGView   // SPM: https://github.com/exyte/SVGView

// MARK: - Theme (local to this file, matches your global style)
private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)   // #121212-ish
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

    private var totalReps: Int { sets.reduce(0) { $0 + max(0, $1.reps) } }
    private var workingSets: Int { sets.filter{ $0.reps > 0 }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header / summary
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("\(workingSets) sets • \(totalReps) reps")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.bg)

            // Sets list (compact)
            List {
                Section {
                    ForEach(sets.indices, id: \.self) { i in
                        SetRowCompact(
                            index: i + 1,
                            reps: Binding(
                                get: { sets[i].reps },
                                set: { sets[i].reps = max(0, $0) }
                            ),
                            weightKg: Binding(
                                get: { sets[i].weight },
                                set: { sets[i].weight = max(0, $0) }
                            ),
                            unit: unit,
                            onDuplicate: { duplicateSet(at: i) }
                        )
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) { sets.remove(at: i) }
                            Button("Duplicate") { duplicateSet(at: i) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }

                    Button("Add set") {
                        let last = sets.last ?? SetInput(reps: 10, weight: 0)
                        sets.append(SetInput(reps: last.reps, weight: last.weight))
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.surface2)

                } header: {
                    Text("Sets")
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 16)
                }

                // MARK: Muscles section
                Section {
                    ExerciseMusclesSection(
                        exercise: exercise,
                        focus: .full   // .upper/.lower cropping if you want later
                    )
                    .listRowInsets(.init(top: 0, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.bg)
                } header: {
                    Text("Muscles")
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 16)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
        }
        // Bottom bar that does NOT cover list content
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if currentEntryID == nil {
                    PrimaryCTA(title: "Save to Current Workout") { saveAsNewEntry() }
                    //SecondaryCTA(title: "Finish Workout") { finishWorkout() }
                } else {
                    PrimaryCTA(title: "Save to Current Workout") { saveToCurrent() }
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

    // MARK: - Actions
    private func addSet() {
        let last = sets.last ?? SetInput(reps: 10, weight: 0)
        sets.append(SetInput(reps: last.reps, weight: last.weight))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func duplicateSet(at index: Int) {
        guard sets.indices.contains(index) else { return }
        let s = sets[index]
        sets.append(SetInput(reps: s.reps, weight: s.weight))
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
        sets.map { SetInput(reps: max(0, $0.reps), weight: max(0, $0.weight)) }
    }

    private func saveAsNewEntry() {
        let entryID = store.addExerciseToCurrent(exercise)
        let clean = cleanSets()
        if clean.contains(where: { $0.reps > 0 || $0.weight > 0 }) {
            store.updateEntrySets(entryID: entryID, sets: clean)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        if returnToHomeOnSave { NotificationCenter.default.post(name: .resetHomeToRoot, object: nil) }
        NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
    }

    private func saveToCurrent() {
        guard let entryID = currentEntryID else { return }
        let clean = cleanSets()
        store.updateEntrySets(entryID: entryID, sets: clean)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        if returnToHomeOnSave {
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
            NotificationCenter.default.post(name: .resetHomeToRoot, object: nil)
        } else {
            NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
        }
    }

    private func finishWorkout() {
        let clean = cleanSets()
        guard clean.reduce(0, { $0 + $1.reps }) > 0 else { showEmptyAlert = true; return }
        let entry = WorkoutEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            muscleGroups: exercise.primaryMuscles + exercise.secondaryMuscles,
            sets: clean
        )
        let workout = CompletedWorkout(entries: [entry])
        store.addWorkout(workout)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Compact Row

private struct SetRowCompact: View {
    let index: Int
    @Binding var reps: Int
    @Binding var weightKg: Double
    let unit: WeightUnit
    let onDuplicate: () -> Void

    private var step: Double { unit == .kg ? 2.5 : 5 }
    private var displayWeight: Double {
        unit == .kg ? weightKg : (weightKg * 2.20462)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(index)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, alignment: .leading)

            CompactStepperInt(value: $reps, label: "Reps", lower: 0, upper: 500)
                .frame(maxWidth: .infinity, alignment: .leading)

            CompactStepperDouble(
                valueDisplay: Binding(
                    get: { displayWeight },
                    set: { newDisplay in
                        weightKg = (unit == .kg) ? max(0, newDisplay) : max(0, newDisplay / 2.20462)
                    }
                ),
                step: step,
                label: "Weight",
                suffix: unit.rawValue
            )
            .frame(maxWidth: .infinity)

        }
        .padding(.vertical, 8)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .contextMenu { Button("Duplicate") { onDuplicate() } }
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

private struct CompactStepperDouble: View {
    @Binding var valueDisplay: Double
    let step: Double
    let label: String
    var suffix: String = ""

    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
                .frame(width: 38, alignment: .leading)

            HStack(spacing: 0) {
                Button { bump(-step) } label: { Text("−").font(.headline) }
                    .buttonStyle(CompactKnobStyle())

                Group {
                    if editing {
                        TextField("",
                                  value: $valueDisplay,
                                  format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .onChange(of: focused) { if !$0 { editing = false } }
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

                Button { bump(+step) } label: { Text("+").font(.headline) }
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

// One outer border for the whole pill. Knobs have no stroke.
private struct PillBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Theme.surface2, in: Capsule())
            .overlay(
                Capsule().stroke(Theme.border.opacity(0.9), lineWidth: 0.75)
            )
    }
}

private extension View {
    func pillBackground() -> some View { modifier(PillBackground()) }
}

// Filled accent knob with soft halo. No stroke → removes the double-border look.
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

// MARK: - CTAs (text only)

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

private struct SecondaryCTA: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Muscles section (UI container + equal-width torsos)

private enum MusclesTheme {
    static let surface  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border   = Color.white.opacity(0.10)
    static let headline = Color.white.opacity(0.65)
}

struct ExerciseMusclesSection: View {
    let exercise: Exercise
    var focus: SVGHumanBodyView.Focus = .full   // crop option

    private var primary: Set<String> { Set(exercise.primaryMuscles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }
    private var secondary: Set<String> { Set(exercise.secondaryMuscles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Muscles worked")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MusclesTheme.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MusclesTheme.surface)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MusclesTheme.border, lineWidth: 1)

                HStack(spacing: 12) {
                    SVGHumanBodyView(side: .front, focus: focus, primary: primary, secondary: secondary)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.56, contentMode: .fit)

                    SVGHumanBodyView(side: .back,  focus: focus, primary: primary, secondary: secondary)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.56, contentMode: .fit)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - SVG torso/Highlighting

struct SVGHumanBodyView: View {
    enum Side  { case front, back }
    enum Focus { case full, upper, lower }

    var side: Side
    var focus: Focus = .full
    var primary: Set<String> = []
    var secondary: Set<String> = []

    private var highlightKey: String {
        (primary.sorted().joined(separator: ",")) + "|" + (secondary.sorted().joined(separator: ","))
    }

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: side == .front ? "torso" : "torso_back",
                                         withExtension: "svg") {
                let svg = SVGView(contentsOf: url)

                svg
                    .aspectRatio(contentMode: .fit)
                    .mask(maskForFocus())
                    // Defer one runloop to ensure the node tree is ready.
                    .onAppear { DispatchQueue.main.async { applyHighlights(into: svg) } }
                    .onChange(of: highlightKey) { _ in DispatchQueue.main.async { applyHighlights(into: svg) } }

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
            let h = geo.size.height
            let w = geo.size.width
            let rect: CGRect = {
                switch focus {
                case .full:  return .init(x: 0, y: 0, width: w, height: h)
                case .upper: return .init(x: 0, y: 0, width: w, height: h * 0.58)
                case .lower: return .init(x: 0, y: h * 0.42, width: w, height: h * 0.58)
                }
            }()
            Rectangle().path(in: rect).fill(.black)
        }
    }

    // Apply highlight styles
    private func applyHighlights(into root: SVGView) {
        // 1) Canonicalize dataset muscle names to SVG-friendly tokens
        let primaryTokens   = Array(primary).flatMap { MuscleLexicon.tokens(for: $0) }
        let secondaryTokens = Array(secondary).flatMap { MuscleLexicon.tokens(for: $0) }

        // 2) Derive concrete IDs to try
        let primaryIDs   = MuscleLexicon.idCandidates(forTokens: primaryTokens)
        let secondaryIDs = MuscleLexicon.idCandidates(forTokens: secondaryTokens)

        // 3) Paint
        color(ids: primaryIDs,   in: root, opacity: 0.95)
        color(ids: secondaryIDs, in: root, opacity: 0.45)
    }

    // Recursively paint a node (groups + all descendant shapes)
    private func paint(_ node: SVGNode, targetOpacity: Double) {
        if let shape = node as? SVGShape {
            shape.fill = SVGColor.by(name: "yellow") // swap to your exact brand if supported
            shape.opacity = targetOpacity
        } else if let group = node as? SVGGroup {
            group.opacity = max(group.opacity, targetOpacity)
            for child in group.contents { paint(child, targetOpacity: targetOpacity) }
        } else {
            node.opacity = max(node.opacity, targetOpacity)
        }
    }

    private func color(ids: [String], in root: SVGView, opacity: Double) {
        for id in ids {
            if let node = root.getNode(byId: id) {
                paint(node, targetOpacity: opacity)   // recurse into groups
            }
        }
    }
}

// MARK: - Muscle lexicon & ID candidates

private enum MuscleLexicon {
    // Maps common dataset names → likely SVG tokens/prefixes
    static func tokens(for raw: String) -> [String] {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: Set<String> = [
            base,
            base.replacingOccurrences(of: " ", with: "-"),
            singularize(base),
        ]

        switch base {
        case "abs", "abdominals":
            out.formUnion(["abs","abdominals","rectus-abdominis"])
        case "obliques":
            out.formUnion(["obliques","external-oblique","internal-oblique","oblique"])
        case "shoulders", "delts", "deltoids":
            out.formUnion(["shoulders","deltoid","deltoids"])
        case "lats", "lat":
            out.formUnion(["lats","latissimus-dorsi"])
        case "middle back", "mid back", "mid-back":
            out.formUnion(["middle-back","mid-back","rhomboid"])
        case "lower back":
            out.formUnion(["lower-back","erector-spinae"])
        case "traps", "trapezius":
            out.formUnion(["traps","trapezius"])
        case "forearms":
            out.formUnion(["forearm","forearms","brachioradialis"])
        case "biceps":
            out.formUnion(["biceps","biceps-brachii"])
        case "triceps":
            out.formUnion(["triceps","triceps-brachii"])
        case "chest", "pecs", "pectorals":
            // add major + typical subdivisions used by anatomy SVGs
            out.formUnion([
                "pectoralis","pectoralis-major","pectoralis-minor",
                "pectoralis-major-clavicular","pectoralis-major-sternal"
            ])
        case "pectoralis", "pectoralis major", "pectoralis-major":
            out.formUnion([
                "pectoralis-major","pectoralis-major-clavicular","pectoralis-major-sternal"
            ])
        case "pectoralis minor", "pectoralis-minor":
            out.formUnion(["pectoralis-minor"])
        case "glutes", "glute":
            out.formUnion(["glutes","gluteus-maximus","gluteus-medius","gluteus-minimus"])
        case "hamstrings", "hamstring":
            out.formUnion(["hamstrings","biceps-femoris","semitendinosus","semimembranosus"])
        case "quadriceps", "quads", "quad":
            out.formUnion(["quadriceps","quads","rectus-femoris","vastus-lateralis","vastus-medialis","vastus-intermedius"])
        case "calves", "calf":
            out.formUnion(["calves","calf","gastrocnemius","soleus"])
        case "adductors":
            out.formUnion(["adductors","adductor"])
        case "abductors":
            out.formUnion(["abductors","abductor","tensor-fasciae-latae","gluteus-medius","gluteus-minimus"])
        default: break
        }
        return Array(out)
    }

    // IDs often come with side/plane/duplicate suffixes.
    static func idCandidates(forTokens tokens: [String]) -> [String] {
        var ids = Set<String>()

        let sides   = ["", "-l", "-r", "-L", "-R", "-left", "-right"]  // include uppercase L/R seen in your SVG
        let planes  = ["", "-front", "-back", "-anterior", "-posterior"]
        let copies  = (0...20).map { "-\($0)" } + [""]

        for t in tokens {
            let base = t
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
                .replacingOccurrences(of: " ", with: "-")

            let singular = base.hasSuffix("s") ? String(base.dropLast()) : base
            let forms = Set([base, singular])

            for form in forms {
                for s in sides {
                    for p in planes {
                        for c in copies {
                            ids.insert("\(form)\(s)\(p)\(c)")
                            ids.insert("\(form)\(p)\(s)\(c)")
                        }
                    }
                }
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
