import SwiftUI

struct CutCreateExerciseView: View {
    let model: CutCreateExerciseModel
    let change: (CutCreateExerciseModel) -> Void
    let save: () -> Void
    let cancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFocused: Bool
    @Environment(\.cutSheetDepth) private var sheetDepth
    private var level: DS.Cut.SheetLevel { .resolve(parentDepth: sheetDepth) }

    var body: some View {
        CutSheet(model.title, kind: .form, close: cancel) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                    TextField("Exercise Name", text: Binding(get: { model.name }, set: { update(\.name, $0) }),
                              prompt: Text("Exercise Name").foregroundStyle(DS.Cut.Colors.textSecondary))
                        .cutFont(.body).autocorrectionDisabled().focused($nameFocused)
                        .padding(.horizontal, 16).frame(minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(level.control))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("DETAILS").font(DS.Cut.Typography.condensed(size: 23, relativeTo: .headline)).padding(.bottom, 12)
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
                    Text("TYPE").font(DS.Cut.Typography.condensed(size: 23, relativeTo: .headline))
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                    layout {
                        ForEach(["compound", "isolation"], id: \.self) { type in
                            Button(type.capitalized) { update(\.mechanic, type) }
                                .buttonStyle(CutPillButtonStyle(model.mechanic == type ? .white : .control, fillsWidth: true))
                                .accessibilityAddTraits(model.mechanic == type ? .isSelected : [])
                        }
                    }
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
        } footer: {
            Button(model.actionTitle, action: save)
                .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true)).disabled(!model.canSave)
                .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.vertical, 12)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameFocused = false }.cutFont(.title)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
