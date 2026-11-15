//
//  CutProgramPreviewHost.swift
//  WRKT
//
//  Wires the friend program preview to ProgramInviteViewModel: the same load, accept, activate,
//  decline and day reorder as ProgramPreviewView, and the same in-place exercise edits.
//

import SwiftUI

struct CutProgramPreviewHost: View {
    let inviteID: UUID
    let bottomActionPadding: CGFloat
    let onChanged: (() async -> Void)?

    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProgramInviteViewModel?
    @State private var operation: CutProgramPreviewOperation?
    @State private var openDay: CutProgramDayItem?

    var body: some View {
        CutProgramPreviewView(model: CutProgramPreviewLogic.model(facts), operation: operation,
                              bottomPadding: bottomActionPadding, actions: actions)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard viewModel == nil else { return }
                let model = ProgramInviteViewModel(repo: deps.programSharingRepository, plannerStore: deps.plannerStore,
                                                   profileRepo: deps.profileRepository)
                await model.load(inviteID: inviteID)
                guard !Task.isCancelled else { return }
                viewModel = model
            }
            .sheet(item: $openDay) { item in
                NavigationStack {
                    CutProgramDayHost(block: item.block, title: item.title)
                }
            }
    }

    private var facts: CutProgramPreviewFacts {
        guard let viewModel else {
            return .init(loaded: false, inviteStatus: nil, hasProgram: false, blocks: nil, imported: false, acting: false)
        }
        return .init(
            loaded: true,
            inviteStatus: viewModel.invite?.status,
            hasProgram: viewModel.program != nil,
            programName: viewModel.program?.name,
            note: viewModel.program?.description,
            senderDisplayName: viewModel.senderProfile?.displayName,
            senderUsername: viewModel.senderProfile?.username,
            senderAvatarURL: viewModel.senderProfile?.avatarUrl,
            blocks: viewModel.previewSplit?.orderedPlanBlocks.map {
                .init(id: $0.id, name: $0.dayName, isRest: $0.isRestDay, exerciseNames: $0.exercises.map(\.exerciseName))
            },
            imported: viewModel.importedSplit != nil,
            acting: viewModel.isActing || operation != nil,
            availability: viewModel.availabilityMessage,
            error: viewModel.errorMessage
        )
    }

    private var actions: CutProgramPreviewActions {
        CutProgramPreviewActions(
            back: { dismiss() },
            openDay: { id in
                guard let blocks = viewModel?.previewSplit?.orderedPlanBlocks,
                      let index = blocks.firstIndex(where: { $0.id == id }), !blocks[index].isRestDay else { return }
                openDay = .init(block: blocks[index], title: CutProgramPreviewLogic.day(
                    .init(id: id, name: blocks[index].dayName, isRest: false, exerciseNames: []), index: index).title)
            },
            moveDay: { source, target in viewModel?.dropBlock(id: source, on: target) },
            start: { Task { await start() } },
            save: { Task { await save() } },
            decline: { Task { await decline() } },
            done: { dismiss() }
        )
    }

    /// Accept (when not yet in the library), then activate: the legacy Add to Library then Activate Now.
    private func start() async {
        guard let viewModel, operation == nil else { return }
        operation = .start
        defer { operation = nil }
        if viewModel.importedSplit == nil {
            guard await viewModel.acceptInvite() else { return }
            viewModel.successMessage = nil
            await onChanged?()
        }
        if viewModel.activateImportedProgram() {
            dismiss()
            Task { await onChanged?() }
        }
    }

    private func save() async {
        guard let viewModel, operation == nil else { return }
        operation = .save
        defer { operation = nil }
        guard await viewModel.acceptInvite() else { return }
        viewModel.successMessage = nil
        await onChanged?()
        dismiss()
    }

    private func decline() async {
        guard let viewModel, operation == nil else { return }
        operation = .decline
        defer { operation = nil }
        guard await viewModel.declineInvite() else { return }
        viewModel.successMessage = nil
        await onChanged?()
        dismiss()
    }
}

private struct CutProgramDayItem: Identifiable {
    let block: PlanBlock
    let title: String
    var id: UUID { block.id }
}

/// One day of the preview copy, with the exercise edit sheet stacked on top.
private struct CutProgramDayHost: View {
    let block: PlanBlock
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CutProgramExerciseItem?
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @AppStorage("weight_step_kg") private var weightStepKg: Double = 2.5
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        CutProgramDaySheetView(
            model: CutProgramPreviewLogic.daySheet(title: title, exercises: block.exercises.map {
                (id: $0.id, name: $0.exerciseName, sets: $0.sets, reps: $0.reps, weight: $0.startingWeight)
            }, unit: unit),
            edit: { id in editing = block.exercises.first { $0.id == id }.map(CutProgramExerciseItem.init) },
            close: { dismiss() }
        )
        .sheet(item: $editing) { item in
            NavigationStack {
                CutExerciseEditView(
                    model: CutExerciseEditLogic.model(name: item.exercise.exerciseName, sets: item.exercise.sets, reps: item.exercise.reps,
                                                      weight: item.exercise.startingWeight, context: .invite,
                                                      unitLabel: unit.label, weightStep: weightStepKg),
                    level: .stacked,
                    save: { sets, reps, weight in
                        item.exercise.sets = sets
                        item.exercise.reps = reps
                        item.exercise.startingWeight = weight
                        editing = nil
                    },
                    close: { editing = nil }
                )
            }
        }
    }
}

private struct CutProgramExerciseItem: Identifiable {
    let exercise: PlanBlockExercise
    var id: UUID { exercise.id }
}
