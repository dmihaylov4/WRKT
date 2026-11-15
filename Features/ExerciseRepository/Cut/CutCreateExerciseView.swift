import SwiftUI

struct CutCreateExerciseView: View {
    let model: CutCreateExerciseModel
    let change: (CutCreateExerciseModel) -> Void
    let save: () -> Void
    let cancel: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                    TextField("Exercise Name", text: Binding(get: { model.name }, set: { update(\.name, $0) }))
                        .cutFont(.body).autocorrectionDisabled().focused($nameFocused)
                        .frame(minHeight: 44)
                    CutHairline()
                    Text("Give your exercise a descriptive name").cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Classification").cutFont(.title).padding(.bottom, 12)
                    CutHairline()
                    menu("Primary Muscle", choices: CutCreateExerciseLogic.muscles, value: model.muscle) { update(\.muscle, $0) }
                    menu("Equipment", choices: EquipBucket.allCases.map(\.rawValue), value: model.equipment.rawValue) {
                        if let value = EquipBucket(rawValue: $0) { update(\.equipment, value) }
                    }
                    menu("Movement Pattern", choices: MoveBucket.allCases.map(\.rawValue), value: model.movement.rawValue) {
                        if let value = MoveBucket(rawValue: $0) { update(\.movement, value) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exercise Type").cutFont(.title)
                    HStack(spacing: 10) {
                        ForEach(["compound", "isolation"], id: \.self) { type in
                            CutExerciseFilterChip(title: type.capitalized, selected: model.mechanic == type) { update(\.mechanic, type) }
                        }
                    }
                    Text("Compound exercises work multiple muscle groups. Isolation exercises target a single muscle.")
                        .cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    CutHairline()
                    menu("Difficulty", choices: ["Not Set"] + DifficultyLevel.allCases.map(\.label),
                         value: model.difficulty?.label ?? "Not Set") { title in
                        update(\.difficulty, DifficultyLevel.allCases.first { $0.label == title })
                    }
                }
            }
            .padding(DS.Cut.Metrics.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.title.uppercased()).font(DS.Cut.Typography.condensed(size: 22, relativeTo: .headline))
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel).cutFont(.title).tint(DS.Cut.Colors.textPrimary)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(model.actionTitle, action: save).cutFont(.title).tint(DS.Cut.Colors.lime).disabled(!model.canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameFocused = false }.cutFont(.title)
            }
        }
        .shellNavigationBarBackground(DS.Cut.Colors.background)
    }

    private func update<Value>(_ key: WritableKeyPath<CutCreateExerciseModel, Value>, _ value: Value) {
        var form = model
        form[keyPath: key] = value
        change(form)
    }

    private func menu(_ title: String, choices: [String], value: String, select: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Button { select(choice) } label: {
                    if value == choice { Label(choice, systemImage: "checkmark") } else { Text(choice) }
                }
            }
        } label: {
            menuRow(title, value: value)
        }
        .buttonStyle(.plain)
    }

    private func menuRow(_ title: String, value: String) -> some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(title).cutFont(.title).fixedSize()
                    Spacer(minLength: 8)
                    Text(value).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).fixedSize()
                    Image(systemName: "chevron.right").foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).cutFont(.title).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Text(value).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
            CutHairline()
        }
    }

}
