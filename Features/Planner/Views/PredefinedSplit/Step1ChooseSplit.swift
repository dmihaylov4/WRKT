//
//  Step1ChooseSplit.swift
//  WRKT
//
//  Step 1: Choose training split

import SwiftUI

struct Step1ChooseSplit: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void
    @EnvironmentObject var customSplitStore: CustomSplitStore

    @State private var splitToDelete: SplitTemplate?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your training split")
                    .font(.title2.bold())
                    .padding(.horizontal)

                Text("Select a program that matches your goals and schedule.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Predefined splits
                ForEach(SplitTemplates.all) { template in
                    SplitTemplateCard(
                        template: template,
                        isSelected: config.selectedTemplate?.id == template.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            config.selectedTemplate = template
                            config.isCreatingCustom = false
                        }
                        onAutoAdvance()
                    }
                }

                // Divider with "OR"
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("OR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                }
                .padding(.vertical, 8)
                .padding(.horizontal)

                // Create custom split button
                CreateCustomSplitCard(
                    isSelected: config.isCreatingCustom
                ) {
                    withAnimation {
                        config.isCreatingCustom = true
                        config.selectedTemplate = nil
                        onAutoAdvance()
                    }
                }

                // Existing custom splits
                if !customSplitStore.customSplits.isEmpty {
                    Text("Your Custom Splits")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    ForEach(customSplitStore.customSplits) { template in
                        SplitTemplateCard(
                            template: template,
                            isSelected: config.selectedTemplate?.id == template.id
                        ) {
                            withAnimation {
                                config.selectedTemplate = template
                                config.isCreatingCustom = false
                                onAutoAdvance()
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                splitToDelete = template
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete Split", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .alert("Delete Custom Split", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                splitToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let split = splitToDelete {
                    // Deselect if this was the selected template
                    if config.selectedTemplate?.id == split.id {
                        config.selectedTemplate = nil
                    }
                    customSplitStore.delete(split.id)
                    splitToDelete = nil
                }
            }
        } message: {
            if let split = splitToDelete {
                Text("Are you sure you want to delete '\(split.name)'? This action cannot be undone.")
            }
        }
    }
}
