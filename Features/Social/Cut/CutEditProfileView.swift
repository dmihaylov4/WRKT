import SwiftUI

struct CutEditProfileView: View {
    let model: CutEditProfileModel
    @Binding var draft: CutEditProfileDraft
    var save: () -> Void = {}
    var cancel: () -> Void = {}
    @State private var contentHeight: CGFloat = 500
    @State private var headerHeight: CGFloat = 68
    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("EDIT PROFILE").font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
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
                }
                .padding(DS.Cut.Metrics.gutter)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .presentationDetents([.height(min(720, max(320, contentHeight + headerHeight + 24))), .large])
        .presentationDragIndicator(.visible)
        .shellPresentationBackground(DS.Cut.Colors.background)
    }
    private var header: some View {
        HStack {
            Button("Cancel", action: cancel).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                .disabled(model.isSaving)
            Spacer(minLength: 12)
            Button(action: save) {
                ZStack { Text("Save").opacity(model.isSaving ? 0 : 1); if model.isSaving { ProgressView().tint(DS.Cut.Colors.ink) } }
            }.buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false)).disabled(!model.canSave)
            .accessibilityLabel("Save profile")
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.vertical, 12)
        .background(DS.Cut.Colors.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>, axis: Axis, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            TextField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(DS.Cut.Colors.textSecondary), axis: axis)
                .cutFont(.body).lineLimit(lines).textFieldStyle(.plain).tint(DS.Cut.Colors.lime)
            CutHairline()
        }
    }
}
