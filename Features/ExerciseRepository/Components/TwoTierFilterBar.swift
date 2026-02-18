//
//  TwoTierFilterBar.swift
//  WRKT
//
//  Two-tier filter system: Muscle groups (always visible) + collapsible Equipment/Movement
//

import SwiftUI

struct TwoTierFilterBar: View {
    let bodyRegion: BodyRegion
    @Binding var selectedMuscle: String?
    @Binding var selectedDeepFilter: String?
    @Binding var equipment: EquipBucket
    @Binding var movement: MoveBucket
    @Binding var isSecondaryExpanded: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Tier 1: Muscle Group Filter (always visible)
            MuscleGroupFilterRow(
                bodyRegion: bodyRegion,
                selected: $selectedMuscle,
                deepSelected: $selectedDeepFilter
            )

            // Tier 1b: Deep Filter (conditional - only for Chest and Back)
            if let muscle = selectedMuscle,
               let deepOptions = MuscleTaxonomy.deepSubregions(for: muscle) {
                DeepFilterRow(
                    muscleGroup: muscle,
                    options: deepOptions,
                    selected: $selectedDeepFilter
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Tier 2: Secondary Filters (collapsible)
            CollapsibleFiltersSection(
                equipment: $equipment,
                movement: $movement,
                isExpanded: $isSecondaryExpanded
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedMuscle)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedDeepFilter)
    }
}

// MARK: - Deep Filter Row

private struct DeepFilterRow: View {
    let muscleGroup: String
    let options: [String]
    @Binding var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(muscleGroup.uppercased()) REGION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        MuscleChip(
                            title: option,
                            isSelected: selected == option,
                            onTap: {
                                if selected == option {
                                    // Deselect if tapping same option
                                    selected = nil
                                } else {
                                    // Select new option
                                    selected = option
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Preview

#Preview("Upper Body - No Selection") {
    VStack {
        TwoTierFilterBar(
            bodyRegion: .upper,
            selectedMuscle: .constant(nil),
            selectedDeepFilter: .constant(nil),
            equipment: .constant(.all),
            movement: .constant(.all),
            isSecondaryExpanded: .constant(false)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}

#Preview("Upper Body - Chest Selected") {
    VStack {
        TwoTierFilterBar(
            bodyRegion: .upper,
            selectedMuscle: .constant("Chest"),
            selectedDeepFilter: .constant(nil),
            equipment: .constant(.all),
            movement: .constant(.all),
            isSecondaryExpanded: .constant(false)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}

#Preview("Upper Body - Chest + Upper Chest Selected") {
    VStack {
        TwoTierFilterBar(
            bodyRegion: .upper,
            selectedMuscle: .constant("Chest"),
            selectedDeepFilter: .constant("Upper Chest"),
            equipment: .constant(.all),
            movement: .constant(.all),
            isSecondaryExpanded: .constant(false)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}

#Preview("Upper Body - Filters Expanded") {
    VStack {
        TwoTierFilterBar(
            bodyRegion: .upper,
            selectedMuscle: .constant("Back"),
            selectedDeepFilter: .constant("Lats"),
            equipment: .constant(.barbell),
            movement: .constant(.pull),
            isSecondaryExpanded: .constant(true)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}

#Preview("Lower Body") {
    VStack {
        TwoTierFilterBar(
            bodyRegion: .lower,
            selectedMuscle: .constant("Quads"),
            selectedDeepFilter: .constant(nil),
            equipment: .constant(.all),
            movement: .constant(.all),
            isSecondaryExpanded: .constant(false)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}
