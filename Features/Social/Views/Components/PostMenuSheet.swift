import SwiftUI

/// Menu sheet for post actions (Edit, Delete, Share, Report)
struct PostMenuSheet: View {
    let post: PostWithAuthor
    let isOwnPost: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onReport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isOwnPost {
                    // Own post actions
                    Section {
                        Button {
                            dismiss()
                            onEdit()
                        } label: {
                            Label("Edit Post", systemImage: "pencil")
                                .foregroundStyle(DS.Semantic.textPrimary)
                        }

                        Button(role: .destructive) {
                            dismiss()
                            onDelete()
                        } label: {
                            Label("Delete Post", systemImage: "trash")
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        onShare()
                    } label: {
                        Label("Share Post", systemImage: "square.and.arrow.up")
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }
                }

                if !isOwnPost {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                            onReport()
                        } label: {
                            Label("Report Post", systemImage: "exclamationmark.triangle")
                        }
                    }
                }
            }
            .navigationTitle("Post Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// Preview removed to avoid complex initializations
