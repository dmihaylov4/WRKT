//
//  SearchBarComponent.swift
//  WRKT
//
//  Search bar UI component for exercise browsing
//

import SwiftUI

// MARK: - Search Bar

struct ExerciseSearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search exercises...", text: $text)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            Button("Cancel") {
                onCancel()
            }
            .foregroundStyle(DS.Palette.marone)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.Semantic.surface)
    }
}
