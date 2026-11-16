import SwiftUI

struct CutEditProfileView: View {
    let model: CutEditProfileModel
    @Binding var draft: CutEditProfileDraft
    var save: () -> Void = {}
    var cancel: () -> Void = {}
    @Environment(\.cutSheetDepth) private var sheetDepth
    private var level: DS.Cut.SheetLevel { .resolve(parentDepth: sheetDepth) }
    var body: some View {
        CutSheet("Edit Profile", kind: .form, isCloseEnabled: !model.isSaving, close: cancel) {
            VStack(alignment: .leading, spacing: 24) {
                field("Display Name", placeholder: "Add your name", text: $draft.displayName, axis: .horizontal, lines: 1...1)
                field("Bio", placeholder: "Add a short training note", text: $draft.bio, axis: .vertical, lines: 3...6)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Private Profile", isOn: $draft.isPrivate).cutFont(.body).tint(DS.Cut.Colors.lime)
                    Text(CutEditProfileModel.privacyHelp).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                    CutHairline()
                }
                if let error = model.error {
                    Text(error).cutFont(.body).fixedSize(horizontal: false, vertical: true).accessibilityLabel("Error: \(error)")
                }
            }.padding(DS.Cut.Metrics.gutter)
        } footer: {
            Button(action: save) {
                ZStack { Text("Save").opacity(model.isSaving ? 0 : 1); if model.isSaving { ProgressView().tint(DS.Cut.Colors.ink) } }
            }
            .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true)).disabled(!model.canSave)
            .accessibilityLabel("Save profile")
            .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    private func field(_ label: String, placeholder: String, text: Binding<String>, axis: Axis, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            TextField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(DS.Cut.Colors.textSecondary), axis: axis)
                .cutFont(.body).lineLimit(lines).textFieldStyle(.plain).tint(DS.Cut.Colors.lime)
                .padding(16).background(RoundedRectangle(cornerRadius: 14).fill(level.control))
        }
    }
}
