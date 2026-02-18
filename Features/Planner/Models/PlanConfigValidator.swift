//
//  PlanConfigValidator.swift
//  WRKT
//
//  Validation logic for plan configurations

import Foundation

struct PlanConfigValidator {

    // MARK: - Step Validation

    static func canProceedFromStep(_ step: Int, config: PlanConfig) -> Bool {
        if config.isCreatingCustom {
            return canProceedFromCustomStep(step, config: config)
        } else {
            return canProceedFromPredefinedStep(step, config: config)
        }
    }

    private static func canProceedFromCustomStep(_ step: Int, config: PlanConfig) -> Bool {
        switch step {
        case 0:
            return true // User selected "Create Custom"

        case 1:
            // Name + Parts validation
            return isValidSplitName(config.customSplitName) &&
                   isValidPartCount(config.numberOfParts) &&
                   areValidPartNames(config.partNames, count: config.numberOfParts)

        case 2:
            // Exercises validation
            return areValidPartExercises(
                config.partExercises,
                partNames: config.partNames,
                numberOfParts: config.numberOfParts
            )

        case 3:
            return config.trainingDaysPerWeek > 0 && config.restDayPlacement != nil

        case 4:
            return config.programWeeks > 0

        default:
            return true
        }
    }

    private static func canProceedFromPredefinedStep(_ step: Int, config: PlanConfig) -> Bool {
        switch step {
        case 0:
            return config.selectedTemplate != nil

        case 1:
            return config.trainingDaysPerWeek > 0

        case 2:
            return config.restDayPlacement != nil

        case 3:
            return config.wantsToCustomize != nil

        case 4:
            return config.programWeeks > 0

        default:
            return true
        }
    }

    // MARK: - Full Configuration Validation

    static func isValidConfiguration(_ config: PlanConfig) -> Bool {
        if config.isCreatingCustom {
            return isValidCustomConfiguration(config)
        } else {
            return isValidPredefinedConfiguration(config)
        }
    }

    private static func isValidPredefinedConfiguration(_ config: PlanConfig) -> Bool {
        return config.selectedTemplate != nil &&
               config.trainingDaysPerWeek > 0 &&
               config.restDayPlacement != nil &&
               config.wantsToCustomize != nil &&
               config.programWeeks > 0
    }

    private static func isValidCustomConfiguration(_ config: PlanConfig) -> Bool {
        guard isValidSplitName(config.customSplitName) else { return false }
        guard isValidPartCount(config.numberOfParts) else { return false }
        guard areValidPartNames(config.partNames, count: config.numberOfParts) else { return false }
        guard areValidPartExercises(config.partExercises, partNames: config.partNames, numberOfParts: config.numberOfParts) else { return false }
        guard isRestPlacementCompatible(config) else { return false }

        return config.trainingDaysPerWeek > 0 && config.programWeeks > 0
    }

    // MARK: - Component Validators

    static func isValidSplitName(_ name: String) -> Bool {
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func isValidPartCount(_ count: Int) -> Bool {
        return count >= PlannerConstants.CustomSplit.minParts &&
               count <= PlannerConstants.CustomSplit.maxParts
    }

    static func areValidPartNames(_ names: [String], count: Int) -> Bool {
        guard names.count == count else { return false }
        guard !names.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }
        guard Set(names).count == count else { return false } // No duplicates
        return true
    }

    static func areValidPartExercises(
        _ exercises: [String: [ExerciseTemplate]],
        partNames: [String],
        numberOfParts: Int
    ) -> Bool {
        guard exercises.count == numberOfParts else { return false }

        for partName in partNames {
            guard let partExercises = exercises[partName] else { return false }
            guard partExercises.count >= PlannerConstants.ExerciseLimits.minPerPart &&
                  partExercises.count <= PlannerConstants.ExerciseLimits.maxPerPart else {
                return false
            }
        }

        return true
    }

    static func isRestPlacementCompatible(_ config: PlanConfig) -> Bool {
        guard let placement = config.restDayPlacement else { return false }

        switch placement {
        case .afterEachWorkout:
            return config.numberOfParts * 2 <= PlannerConstants.TrainingFrequency.daysInWeek

        case .afterEverySecondWorkout:
            let totalDays = config.numberOfParts + (config.numberOfParts / 2)
            return totalDays <= PlannerConstants.TrainingFrequency.daysInWeek

        case .weekends:
            return config.trainingDaysPerWeek <= 5

        case .custom:
            return true
        }
    }

    // MARK: - Available Options

    static func availableRestOptions(for config: PlanConfig) -> [PlanConfig.RestDayPlacement] {
        var options: [PlanConfig.RestDayPlacement] = []
        let daysInWeek = PlannerConstants.TrainingFrequency.daysInWeek

        if config.numberOfParts * 2 <= daysInWeek && config.trainingDaysPerWeek < 6 {
            options.append(.afterEachWorkout)
        }

        if config.numberOfParts + (config.numberOfParts / 2) <= daysInWeek && config.trainingDaysPerWeek <= 4 {
            options.append(.afterEverySecondWorkout)
        }

        if config.trainingDaysPerWeek <= 5 {
            options.append(.weekends)
        }

        options.append(.custom([]))
        return options
    }
}
