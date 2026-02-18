//
//  CollapsibleFiltersSection.swift
//  WRKT
//
//  Expandable/collapsible section for Equipment and Movement filters
//

import SwiftUI

struct CollapsibleFiltersSection: View {
    @Binding var equipment: EquipBucket
    @Binding var movement: MoveBucket
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                Haptics.light()
            } label: {
                HStack {
                    Text("More Filters")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(DS.Semantic.fillSubtle)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                FiltersBar(equip: $equipment, move: $movement)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Preview

#Preview("Collapsed") {
    VStack {
        CollapsibleFiltersSection(
            equipment: .constant(.all),
            movement: .constant(.all),
            isExpanded: .constant(false)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}

#Preview("Expanded") {
    VStack {
        CollapsibleFiltersSection(
            equipment: .constant(.barbell),
            movement: .constant(.push),
            isExpanded: .constant(true)
        )
        Spacer()
    }
    .padding()
    .background(DS.Semantic.surface)
}
