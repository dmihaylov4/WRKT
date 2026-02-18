//  FilteredExerciseBrowser.swift
//  WRKT
//
//  Filtered exercise browser for quick workout flows
//

import SwiftUI

struct FilteredExerciseBrowser: View {
    let muscleFilter: MuscleFilter?
    let title: String
    @Environment(\.dismiss) var dismiss

    // Based on workout type, show appropriate subregions
    private var subregions: [String] {
        guard let filter = muscleFilter else {
            // Custom = show all subregions
            return MuscleTaxonomy.subregions(for: .upper) + MuscleTaxonomy.subregions(for: .lower)
        }

        switch filter {
        case .upperBody:
            return MuscleTaxonomy.subregions(for: .upper)
        case .lowerBody:
            return MuscleTaxonomy.subregions(for: .lower)
        case .fullBody:
            // Full body = both regions
            return MuscleTaxonomy.subregions(for: .upper) + MuscleTaxonomy.subregions(for: .lower)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(subregions, id: \.self) { subregion in
                    NavigationLink(value: subregion) {
                        SubregionRow(title: subregion)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { subregion in
                MuscleExerciseListView(
                    state: .constant(.subregion(subregion)),
                    subregion: subregion
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Subregion Row

private struct SubregionRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(DS.Theme.accent)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

