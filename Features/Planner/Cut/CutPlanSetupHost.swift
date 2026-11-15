//
//  CutPlanSetupHost.swift
//  WRKT
//
//  Drives the Cut new program flow over PlannerSetupCarouselView's own PlanConfig. The carousel
//  keeps its launch modes, its "active plan exists" alert, its error alert and its generate path;
//  this host only moves between screens and writes the values each screen collects.
//

import SwiftUI

struct CutPlanSetupHost: View {
    @ObservedObject var config: PlanConfig
    let purpose: CutPlanSetupPurpose
    /// PlannerSetupCarouselView.generatePlan: saves the plan and dismisses, or shows its error alert.
    let generate: () -> Void

    @EnvironmentObject private var customSplitStore: CustomSplitStore
    @EnvironmentObject private var repo: ExerciseRepository
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @AppStorage("weight_step_kg") private var weightStepKg: Double = 2.5

    @State private var screen: CutPlanSetupScreen = .split
    @State private var draft = CutPlanSetupDraft()
    @State private var replacesPlan = false
    @State private var pickingStart = false
    @State private var startSelection = Date()
    @State private var editingExercise: CutPlanExerciseItem?
    @State private var pickingPart: CutPlanPartItem?
    @State private var splitToDelete: SplitTemplate?
    @StateObject private var searchVM = ExerciseSearchVM()

    private var calendar: Calendar { .current }
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        let position = CutPlanSetupLogic.step(screen, isCustom: config.isCreatingCustom)
        CutPlanSetupView(content: content, step: position.number, total: position.total, isFirst: screen == .split, actions: actions)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { replacesPlan = (try? deps.plannerStore.activeSplit()) != nil }
            .sheet(isPresented: $pickingStart) {
                NavigationStack {
                    CutPlanStartDateView(date: $startSelection, done: {
                        CutPlanSetupLogic.setStart(startSelection, config: config, draft: &draft, calendar: calendar)
                        pickingStart = false
                    }, close: { pickingStart = false })
                }
            }
            .sheet(item: $editingExercise) { item in
                NavigationStack {
                    CutExerciseEditView(
                        model: CutExerciseEditLogic.model(name: item.exercise.exerciseName, sets: item.exercise.sets, reps: item.exercise.reps,
                                                          weight: item.exercise.startingWeight, context: .setup, unitLabel: "kg", weightStep: weightStepKg),
                        save: { sets, reps, weight in
                            CutPlanSetupLogic.updateExercise(at: item.index, dayID: item.dayID, sets: sets, reps: reps, weight: weight, config: config)
                            editingExercise = nil
                        },
                        close: { editingExercise = nil }
                    )
                }
            }
            .sheet(isPresented: $searchVM.isShowingSearch) {
                ExerciseSearchSheet(searchVM: searchVM, onSelect: { exercise in
                    if case .customize(let dayID) = screen {
                        CutPlanSetupLogic.addExercise(id: exercise.id, name: exercise.name, dayID: dayID, config: config)
                    }
                    searchVM.isShowingSearch = false
                })
                .environmentObject(repo)
            }
            .sheet(item: $pickingPart) { item in
                CustomSplitExercisePicker(config: config, partName: item.name)
                    .environmentObject(repo)
            }
            .alert("Delete Custom Split", isPresented: Binding(get: { splitToDelete != nil }, set: { if !$0 { splitToDelete = nil } })) {
                Button("Cancel", role: .cancel) { splitToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let split = splitToDelete {
                        if config.selectedTemplate?.id == split.id { config.selectedTemplate = nil }
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

    private var content: CutPlanSetupContent {
        switch screen {
        case .split: return .split(CutPlanSetupLogic.splitModel(config, saved: customSplitStore.customSplits))
        case .customName: return .customName(CutPlanSetupLogic.customNameModel(config))
        case .customExercises: return .customExercises(CutPlanSetupLogic.customExercisesModel(config))
        case .days: return .days(CutPlanSetupLogic.daysModel(config, draft: draft, calendar: calendar))
        case .customize(let dayID): return .customize(CutPlanSetupLogic.customizeModel(dayID: dayID, config: config, unit: unit))
        case .review: return .review(CutPlanSetupLogic.reviewModel(config, purpose: purpose, replacesPlan: replacesPlan, calendar: calendar, locale: .current))
        }
    }

    private func go(_ next: CutPlanSetupScreen?) {
        guard let next else { return }
        withAnimation(.easeInOut(duration: 0.25)) { screen = next }
    }

    private var actions: CutPlanSetupActions {
        CutPlanSetupActions(
            back: {
                if let previous = CutPlanSetupLogic.back(from: screen, isCustom: config.isCreatingCustom) { go(previous) } else { dismiss() }
            },
            next: {
                if screen == .days { CutPlanSetupLogic.prepareForReview(config) }
                go(CutPlanSetupLogic.next(after: screen, isCustom: config.isCreatingCustom))
            },
            chooseTemplate: { id in
                guard let template = (SplitTemplates.all + customSplitStore.customSplits).first(where: { $0.id == id }) else { return }
                Haptics.light()
                CutPlanSetupLogic.choose(template, config: config)
            },
            chooseBuildOwn: {
                Haptics.light()
                CutPlanSetupLogic.chooseBuildOwn(config)
            },
            deleteSaved: { id in splitToDelete = customSplitStore.customSplits.first { $0.id == id } },
            toggleDay: { day in
                Haptics.light()
                CutPlanSetupLogic.toggle(day, config: config, draft: &draft, calendar: calendar)
            },
            setWeeks: { config.programWeeks = $0 },
            openDay: { dayID in
                if config.isCreatingCustom { pickingPart = .init(name: dayID) } else { go(.customize(dayID)) }
            },
            changeStart: {
                startSelection = draft.baseStart ?? config.startDate
                pickingStart = true
            },
            start: {
                CutPlanSetupLogic.prepareForReview(config)
                generate()
            },
            editExercise: { index in
                guard case .customize(let dayID) = screen else { return }
                let list = CutPlanSetupLogic.exercises(dayID: dayID, config: config)
                guard list.indices.contains(index) else { return }
                editingExercise = .init(dayID: dayID, index: index, exercise: list[index])
            },
            removeExercise: { index in
                guard case .customize(let dayID) = screen else { return }
                CutPlanSetupLogic.removeExercise(at: index, dayID: dayID, config: config)
            },
            addExercise: { searchVM.isShowingSearch = true },
            setName: { config.customSplitName = $0 },
            setPartCount: { CutPlanSetupLogic.setPartCount($0, config: config) },
            setPartName: { CutPlanSetupLogic.setPartName($1, at: $0, config: config) },
            quickFill: { CutPlanSetupLogic.quickFill(config) },
            openPart: { pickingPart = .init(name: $0) }
        )
    }
}

private struct CutPlanExerciseItem: Identifiable {
    let dayID: String
    let index: Int
    let exercise: ExerciseTemplate
    var id: String { "\(dayID)-\(index)" }
}

private struct CutPlanPartItem: Identifiable {
    let name: String
    var id: String { name }
}
