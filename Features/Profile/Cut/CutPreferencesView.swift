//
//  CutPreferencesView.swift
//  WRKT
//
//  App preferences in the Cut language: the legacy nine groups as sentence-case sections of
//  hairline rows. Values sit as plain secondary text on the right; switches are lime when on;
//  unit and increment are choice rows with a menu; default rests step by 30 seconds with grey
//  pills or take a typed time; resets are red text rows at the end. The age and bodyweight
//  wheels are sheets sized to their content. Takes plain values, bindings and closures.
//

import SwiftUI

/// What the page edits in place. Every binding writes where the legacy control wrote.
struct CutPreferencesControls {
    var haptics: Binding<Bool>
    var weightUnit: Binding<String>
    var weightStep: Binding<Double>
    var restTimer: Binding<Bool>
    var autoAddSet: Binding<Bool>
    var compoundSeconds: Binding<Int>
    var isolationSeconds: Binding<Int>
    var autoPostPRs: Binding<Bool>
    var autoPostRuns: Binding<Bool>
    var autoPostWatch: Binding<Bool>
    var smartNudges: Binding<Bool>

    /// Fixed values, for previews and captures.
    static func constant(
        haptics: Bool = true, weightUnit: WeightUnit = .kg, weightStep: Double = 2.5,
        restTimer: Bool = true, autoAddSet: Bool = true, compound: Int = 150, isolation: Int = 90,
        autoPostPRs: Bool = true, autoPostRuns: Bool = true, autoPostWatch: Bool = false, smartNudges: Bool = false
    ) -> CutPreferencesControls {
        CutPreferencesControls(
            haptics: .constant(haptics), weightUnit: .constant(weightUnit.rawValue), weightStep: .constant(weightStep),
            restTimer: .constant(restTimer), autoAddSet: .constant(autoAddSet),
            compoundSeconds: .constant(compound), isolationSeconds: .constant(isolation),
            autoPostPRs: .constant(autoPostPRs), autoPostRuns: .constant(autoPostRuns),
            autoPostWatch: .constant(autoPostWatch), smartNudges: .constant(smartNudges))
    }
}

struct CutPreferencesActions {
    var openAge: () -> Void = {}
    var openBodyweight: () -> Void = {}
    var resetTimers: () -> Void = {}
    var editExercise: (String) -> Void = { _ in }
    var deleteExercise: (String) -> Void = { _ in }
    var openNotificationSettings: () -> Void = {}
    var exportCSV: () -> Void = {}
    var clearPlans: () -> Void = {}
    var resetWeeklyGoal: () -> Void = {}
    var resetAll: () -> Void = {}
}

struct CutPreferencesView: View {
    let model: CutPreferencesModel
    let controls: CutPreferencesControls
    var actions = CutPreferencesActions()
    var startsWithZonesOpen = false

    @State private var showsZones = false

    var body: some View {
        CutSettingsPage(title: model.title) {
            // Profile
            CutSettingsSectionHeader("Profile", isFirst: true)
            CutSettingsLinkRow("Age", value: model.age, action: actions.openAge)
            CutSettingsLinkRow("Bodyweight", value: model.bodyweight, action: actions.openBodyweight)
            CutSettingsFooter(model.profileFooter)

            // Workout
            CutSettingsSectionHeader("Workout")
            CutSettingsToggleRow("Haptic feedback", isOn: controls.haptics)
            CutSettingsChoiceRow("Weight unit", options: model.unitOptions, selection: controls.weightUnit)
            CutSettingsChoiceRow("Weight increment", options: model.incrementOptions, selection: controls.weightStep)
            CutSettingsToggleRow("Rest timer", isOn: controls.restTimer)
            if model.showsRestTimerDetails {
                CutSettingsToggleRow("Auto-add next set",
                                     subtitle: "Add a new set row automatically when the rest timer finishes",
                                     isOn: controls.autoAddSet)
                CutPreferencesRestRow(title: "Compound exercises", seconds: controls.compoundSeconds)
                CutPreferencesRestRow(title: "Isolation exercises", seconds: controls.isolationSeconds)
                CutSettingsActionRow("Reset all custom timers", role: .destructive, action: actions.resetTimers)
            }
            CutSettingsFooter(model.workoutFooter)

            // Heart rate zones
            CutSettingsSectionHeader("Heart rate zones")
            CutSettingsValueRow("Max heart rate", value: model.maxHeartRate)
            zonesToggle
            if showsZones {
                ForEach(model.zones) { zone in
                    CutSettingsValueRow(zone.title, value: zone.range)
                }
            }
            CutSettingsFooter(model.zonesFooter)

            // Custom exercises
            CutSettingsSectionHeader("Custom exercises")
            if model.customExercises.isEmpty {
                CutSettingsRowLayout(title: CutPreferencesLogic.customEmptyLine,
                                     titleColor: DS.Cut.Colors.textSecondary) { EmptyView() }
            } else {
                ForEach(model.customExercises) { exercise in
                    CutSettingsLinkRow(exercise.name, subtitle: exercise.detail) { actions.editExercise(exercise.id) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { actions.deleteExercise(exercise.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: Text("Delete")) { actions.deleteExercise(exercise.id) }
                }
            }
            CutSettingsFooter(model.customFooter)

            // Social
            if model.showsSocial {
                CutSettingsSectionHeader("Social")
                CutSettingsToggleRow("Auto-post PRs",
                                     subtitle: "Automatically share Personal Records to your social feed",
                                     isOn: controls.autoPostPRs)
                CutSettingsToggleRow("Auto-post runs",
                                     subtitle: "Automatically share runs over 1km with map, heart rate, and stats",
                                     isOn: controls.autoPostRuns)
                CutSettingsToggleRow("Auto-post Watch workouts",
                                     subtitle: "Automatically share HIIT, functional training, and other Apple Watch workouts",
                                     isOn: controls.autoPostWatch)
                CutSettingsFooter(model.socialFooter)
            }

            // Notifications
            CutSettingsSectionHeader("Notifications and reminders")
            CutSettingsToggleRow("Smart nudges", subtitle: "Get notifications when friends work out",
                                 isOn: controls.smartNudges)
            if model.showsNotificationSettingsLink {
                CutSettingsActionRow("Enable in Settings", systemImage: "arrow.up.right",
                                     action: actions.openNotificationSettings)
            }
            CutSettingsFooter(model.notificationsFooter)

            // Data
            CutSettingsSectionHeader("Data")
            CutSettingsActionRow("Export workouts as CSV", systemImage: "square.and.arrow.up", action: actions.exportCSV)
            CutSettingsFooter(model.dataFooter)

            // About
            CutSettingsSectionHeader("About")
            CutSettingsValueRow("Version", value: model.version)
            if let url = CutPreferencesLogic.privacyURL {
                Link(destination: url) {
                    CutSettingsRowLayout(title: "Privacy policy") {
                        EmptyView()
                    } accessory: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
            }

            // Reset
            CutSettingsSectionHeader("Reset and clear")
            CutSettingsActionRow("Clear all plans and workouts", role: .destructive, action: actions.clearPlans)
            if model.showsResetWeeklyGoal {
                CutSettingsActionRow("Reset weekly goal", role: .destructive, action: actions.resetWeeklyGoal)
            }
            CutSettingsActionRow("Reset all data", role: .destructive, action: actions.resetAll)
            CutSettingsFooter(model.resetFooter)
        }
        .onAppear { if startsWithZonesOpen { showsZones = true } }
    }

    /// The legacy disclosure group: a row that opens the five zone rows under it.
    private var zonesToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { showsZones.toggle() }
        } label: {
            CutSettingsRowLayout(title: "Zone boundaries") {
                EmptyView()
            } accessory: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .rotationEffect(.degrees(showsZones ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(showsZones ? "Expanded" : "Collapsed"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Rest row

/// A default rest: the time between grey minus and plus pills (30 seconds a step, 0:30 to
/// 10:00). Tapping the time lets you type one ("2:30" or "150").
private struct CutPreferencesRestRow: View {
    let title: String
    @Binding var seconds: Int

    @State private var editing = false
    @State private var editText = ""
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .headline) private var timeWidth: CGFloat = 52

    var body: some View {
        CutSettingsRowLayout(title: title) {
            HStack(spacing: 8) {
                step("minus", label: "Decrease \(title.lowercased())", delta: -CutPreferencesLogic.restStep,
                     enabled: seconds > CutPreferencesLogic.restRange.lowerBound)
                time
                step("plus", label: "Increase \(title.lowercased())", delta: CutPreferencesLogic.restStep,
                     enabled: seconds < CutPreferencesLogic.restRange.upperBound)
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: focused) { _, isFocused in
            guard !isFocused else { return }
            editing = false
            seconds = CutPreferencesLogic.typedRest(editText, current: seconds)
            editText = ""
        }
        .toolbar {
            if focused {
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

    @ViewBuilder
    private var time: some View {
        if editing {
            TextField("Time", text: $editText)
                .keyboardType(.numbersAndPunctuation)
                .focused($focused)
                .multilineTextAlignment(.center)
                .cutFont(.title, monospacedDigits: true)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .tint(DS.Cut.Colors.lime)
                .frame(width: timeWidth + 12, height: DS.Cut.Metrics.minTouchTarget)
                .onAppear {
                    editText = CutPreferencesLogic.restLine(seconds)
                    focused = true
                }
                .onChange(of: editText) { _, newValue in
                    let filtered = CutPreferencesLogic.filteredRestInput(newValue)
                    if filtered != newValue { editText = filtered }
                }
                .accessibilityLabel(Text(title))
        } else {
            Button { editing = true } label: {
                Text(CutPreferencesLogic.restLine(seconds))
                    .cutFont(.title, monospacedDigits: true)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: timeWidth, minHeight: DS.Cut.Metrics.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(CutPreferencesLogic.restLine(seconds)))
            .accessibilityHint(Text("Type a new time"))
        }
    }

    private func step(_ systemImage: String, label: String, delta: Int, enabled: Bool) -> some View {
        Button {
            if let next = CutPreferencesLogic.bumpedRest(seconds, by: delta) {
                seconds = next
                Haptics.light()
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(enabled ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary.opacity(0.5))
                .frame(width: 48, height: DS.Cut.Metrics.minTouchTarget)
                .background(Capsule().fill(DS.Cut.Colors.controlFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Picker sheets

/// The age wheel: Done in the bar, sized to the wheel. The wheel edits a draft; `onCommit` runs
/// once when the sheet closes with a change (see AgeDraft).
struct CutAgePickerView: View {
    var onCommit: (Int) -> Void = { _ in }

    @State private var draft: AgeDraft
    @State private var confirmed = false
    @Environment(\.dismiss) private var dismiss

    init(saved: Int?, onCommit: @escaping (Int) -> Void = { _ in }) {
        self.onCommit = onCommit
        _draft = State(initialValue: AgeDraft(saved: saved))
    }

    var body: some View {
        NavigationStack {
            CutPreferencesWheel {
                Picker("Age", selection: $draft.age) {
                    ForEach(AgeDraft.range, id: \.self) { years in
                        Text("\(years) years").tag(years)
                    }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle("Your age")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CutPreferencesDoneItem {
                    confirmed = true
                    dismiss()
                }
            }
        }
        .onDisappear {
            if let age = draft.ageToCommit(confirmed: confirmed) { onCommit(age) }
        }
        .presentationDetents([.height(cutPreferencesWheelSheetHeight)])
        .presentationBackground(DS.Cut.Colors.background)
        .presentationDragIndicator(.visible)
    }
}

/// The bodyweight wheels in kilograms (whole and tenths), as the legacy sheet.
struct CutWeightPickerView: View {
    @Binding var weight: Double
    var done: () -> Void = {}

    var body: some View {
        NavigationStack {
            CutPreferencesWheel {
                HStack(spacing: 0) {
                    Picker("Kilograms", selection: Binding(
                        get: { CutPreferencesLogic.wholeKg(weight) },
                        set: { weight = CutPreferencesLogic.weight(wholeKg: $0, tenths: CutPreferencesLogic.tenths(weight)) }
                    )) {
                        ForEach(CutPreferencesLogic.wholeKgRange, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    Text(verbatim: ".")
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                    Picker("Tenths", selection: Binding(
                        get: { CutPreferencesLogic.tenths(weight) },
                        set: { weight = CutPreferencesLogic.weight(wholeKg: CutPreferencesLogic.wholeKg(weight), tenths: $0) }
                    )) {
                        ForEach(CutPreferencesLogic.tenthsRange, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 72)
                    Text("kg")
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .padding(.trailing, DS.Cut.Metrics.gutter)
                }
            }
            .navigationTitle("Your bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CutPreferencesDoneItem(done: done) }
        }
        .presentationDetents([.height(cutPreferencesWheelSheetHeight)])
        .presentationBackground(DS.Cut.Colors.background)
        .presentationDragIndicator(.visible)
    }
}

/// The bar plus the 200 pt wheel and its margins.
private let cutPreferencesWheelSheetHeight: CGFloat = 300

/// A system wheel on the black ground, its selection tinted lime.
private struct CutPreferencesWheel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(height: 200)
            .tint(DS.Cut.Colors.lime)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}

private struct CutPreferencesDoneItem: ToolbarContent {
    let done: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: done)
                .fontWeight(.semibold)
        }
    }
}
