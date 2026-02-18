//
//  MuscleGroupFilterRow.swift
//  WRKT
//
//  Horizontal scrolling muscle group filter with "All" option
//

import SwiftUI

struct MuscleGroupFilterRow: View {
    let bodyRegion: BodyRegion
    @Binding var selected: String?
    @Binding var deepSelected: String?

    private var muscles: [String] {
        MuscleTaxonomy.subregions(for: bodyRegion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MUSCLE GROUP")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" chip
                    MuscleChip(
                        title: "All",
                        isSelected: selected == nil,
                        onTap: {
                            selected = nil
                            deepSelected = nil  // Clear deep filter when selecting All
                        }
                    )

                    // Individual muscle chips
                    ForEach(muscles, id: \.self) { muscle in
                        MuscleChip(
                            title: muscle,
                            isSelected: selected == muscle,
                            onTap: {
                                if selected == muscle {
                                    // Deselect if tapping same muscle
                                    selected = nil
                                    deepSelected = nil
                                } else {
                                    // Select new muscle
                                    selected = muscle
                                    deepSelected = nil  // Clear deep filter when changing muscle
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

#Preview("Upper Body") {
    VStack {
        MuscleGroupFilterRow(
            bodyRegion: .upper,
            selected: .constant(nil),
            deepSelected: .constant(nil)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}

#Preview("Lower Body - Chest Selected") {
    VStack {
        MuscleGroupFilterRow(
            bodyRegion: .upper,
            selected: .constant("Chest"),
            deepSelected: .constant(nil)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}

#Preview("Lower Body") {
    VStack {
        MuscleGroupFilterRow(
            bodyRegion: .lower,
            selected: .constant(nil),
            deepSelected: .constant(nil)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}
