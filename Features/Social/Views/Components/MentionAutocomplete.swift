//
//  MentionAutocomplete.swift
//  WRKT
//
//  Autocomplete dropdown for @mention suggestions
//

import SwiftUI

struct MentionAutocomplete: View {
    let suggestions: [UserProfile]
    let onSelect: (UserProfile) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { user in
                    Button {
                        onSelect(user)
                    } label: {
                        HStack(spacing: 12) {
                            // Profile picture
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text(user.username.prefix(1).uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(user.username)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)

                                if let fullName = user.displayName {
                                    Text(fullName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    if user.id != suggestions.last?.id {
                        Divider()
                    }
                }
            }
            .background(DS.card)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.horizontal)
        }
    }
}

