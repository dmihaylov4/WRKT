import SwiftUI

/// View for editing a post's caption and visibility
struct EditPostView: View {
    let post: PostWithAuthor
    let onSave: @MainActor @Sendable (String?, PostVisibility) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var caption: String
    @State private var visibility: PostVisibility
    @State private var isSaving = false
    @State private var error: String?

    init(post: PostWithAuthor, onSave: @escaping @MainActor @Sendable (String?, PostVisibility) async -> Void) {
        self.post = post
        self.onSave = onSave
        _caption = State(initialValue: post.post.caption ?? "")
        _visibility = State(initialValue: post.post.visibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Caption (optional)", text: $caption, axis: .vertical)
                        .lineLimit(5...10)
                        .disabled(isSaving)
                } header: {
                    Text("Caption")
                } footer: {
                    Text("You can only edit the caption and visibility. The workout details and photos cannot be changed.")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Section("Visibility") {
                    Picker("Who can see this post", selection: $visibility) {
                        ForEach([PostVisibility.publicPost, .friends, .privatePost], id: \.self) { vis in
                            Label(vis.displayName, systemImage: vis.icon)
                                .tag(vis)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(isSaving)
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await saveChanges()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || !hasChanges)
                }
            }
        }
    }

    private var hasChanges: Bool {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalCaption = post.post.caption ?? ""
        return trimmedCaption != originalCaption || visibility != post.post.visibility
    }

    private func saveChanges() async {
        isSaving = true
        error = nil

        // Capture values before async operations to avoid concurrency issues
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = trimmedCaption.isEmpty ? nil : trimmedCaption
        let currentVisibility = visibility

        await onSave(finalCaption, currentVisibility)
        Haptics.success()
        dismiss()
    }
}

// Preview removed to avoid complex initializations
