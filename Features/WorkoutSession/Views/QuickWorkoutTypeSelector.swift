//  QuickWorkoutTypeSelector.swift
//  WRKT
//
//  Quick workout type selection for today's workout
//

import SwiftUI

struct QuickWorkoutTypeSelector: View {
    let date: Date
    var title: String = "Start Workout"
    let onSelect: (WorkoutType) -> Void
    @Environment(\.dismiss) var dismiss

    enum WorkoutType {
        case upperBody
        case lowerBody
        case custom

        var title: String {
            switch self {
            case .upperBody: return "Upper Body"
            case .lowerBody: return "Lower Body"
            case .custom: return "Custom"
            }
        }

        var subtitle: String {
            switch self {
            case .upperBody: return "Chest, Back, Shoulders, Arms"
            case .lowerBody: return "Quads, Hamstrings, Glutes, Calves"
            case .custom: return "Browse all exercises"
            }
        }

        var icon: String {
            switch self {
            case .upperBody: return "figure.arms.open"
            case .lowerBody: return "figure.walk"
            case .custom: return "magnifyingglass"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Text("What are you training today?")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    // Quick options
                    WorkoutTypeCard(type: .upperBody, onTap: handleSelection)
                    WorkoutTypeCard(type: .lowerBody, onTap: handleSelection)

                    // Divider
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(height: 1)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(height: 1)
                    }
                    .padding(.vertical, 8)

                    // Custom browse
                    WorkoutTypeCard(type: .custom, onTap: handleSelection)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(DS.Semantic.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func handleSelection(_ type: WorkoutType) {
        onSelect(type)
        // Don't dismiss here - let parent handle the transition
        // This avoids jarring sheet close -> fullScreen open animation
    }
}

// MARK: - Workout Type Card

private struct WorkoutTypeCard: View {
    let type: QuickWorkoutTypeSelector.WorkoutType
    let onTap: (QuickWorkoutTypeSelector.WorkoutType) -> Void

    var body: some View {
        Button {
            onTap(type)
            Haptics.light()
        } label: {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(DS.Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(DS.Theme.accent.opacity(0.1), in: Circle())

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.title)
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(type.subtitle)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .opacity(0.6)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )
            .contentShape(ChamferedRectangle(.large))
        }
        .buttonStyle(.plain)
    }
}

