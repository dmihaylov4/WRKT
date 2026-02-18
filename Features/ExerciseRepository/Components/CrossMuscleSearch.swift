//
//  CrossMuscleSearch.swift
//  WRKT
//
//  Cross-muscle search suggestion components
//

import SwiftUI

// MARK: - Muscle Suggestion Model

/// Model for search suggestions from other muscle groups
struct MuscleSuggestion {
    let muscle: String
    let region: String
    let exercises: [Exercise]
    let totalCount: Int
}

// MARK: - Cross Muscle Suggestion Section

/// Expandable section showing exercises found in other muscle groups
struct CrossMuscleSuggestionSection: View {
    let suggestion: MuscleSuggestion
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelectExercise: (Exercise) -> Void
    let onShowAll: () -> Void

    var body: some View {
        Section {
            // Header - tap to expand/collapse
            Button(action: onToggle) {
                HStack(spacing: 16) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(DS.Palette.marone)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Found in \(suggestion.muscle)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)

                            Text(suggestion.region)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.15), in: ChamferedRectangle(.micro))
                        }

                        Text("\(suggestion.totalCount) exercise\(suggestion.totalCount == 1 ? "" : "s") match your search")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(
                    ChamferedRectangle(.large)
                        .fill(DS.Palette.marone.opacity(0.2))
                )
                .overlay(
                    ChamferedRectangle(.large)
                        .stroke(DS.Palette.marone.opacity(0.4), lineWidth: 1.5)
                )
                .shadow(color: DS.Palette.marone.opacity(0.15), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // Exercises list (shown when expanded)
            if isExpanded {
                ForEach(suggestion.exercises, id: \.id) { exercise in
                    Button {
                        onSelectExercise(exercise)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(exercise.name)
                                        .font(.body)
                                        .foregroundStyle(.white)

                                    if exercise.isCustom {
                                        CustomExerciseBadge()
                                    }
                                }

                                if let equipment = exercise.equipment {
                                    Text(equipment)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }

                            Spacer()

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                                .foregroundStyle(DS.Palette.marone.opacity(0.6))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(DS.Semantic.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }

                // "Show all" button if there are more exercises
                if suggestion.totalCount > suggestion.exercises.count {
                    Button {
                        onShowAll()
                    } label: {
                        HStack(spacing: 8) {
                            Text("+ \(suggestion.totalCount - suggestion.exercises.count) more")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DS.Palette.marone)

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.body)
                                .foregroundStyle(DS.Palette.marone)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DS.Palette.marone.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DS.Palette.marone.opacity(0.3), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
    }
}
