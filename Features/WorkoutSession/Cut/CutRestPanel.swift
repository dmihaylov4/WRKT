//
//  CutRestPanel.swift
//  WRKT
//
//  The rest timer in the Cut language: the countdown as a huge numeral, the next set as one
//  line, and pills to add time, skip, or cancel. Shown in place of the exercise hero on the
//  set logging screen while a rest that a logged set started runs for that exercise.
//
//  Only CutRestCountdown observes the per-second ticker; the gate observes state transitions.
//

import SwiftUI

struct CutRestActions {
    /// RestTimerManager.adjustTime(by: 15), as the Train hero's "+15 s".
    var addTime: () -> Void = {}
    /// RestTimerManager.skipTimer(): ends the rest now (the next set follows as after a full rest).
    var skip: () -> Void = {}
    /// RestTimerManager.stopTimer(): the legacy badge's cancel.
    var cancel: () -> Void = {}
}

struct CutRestPanel: View {
    let countdown: CutTrainCountdown
    let nextLine: String?
    var actions = CutRestActions()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch countdown {
                case .live: CutRestCountdown()
                case .fixed(let seconds): CutRestNumeral(seconds: seconds)
                }
            }
            .foregroundStyle(DS.Cut.Colors.lime)
            if let nextLine {
                Text(nextLine)
                    .cutFont(.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }
            .padding(.top, 20)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        Button("+15 s", action: actions.addTime)
            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            .accessibilityLabel("Add 15 seconds")
        Button("Skip rest") {
            Haptics.medium()
            actions.skip()
        }
        .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
        Button("Cancel rest", systemImage: "xmark") {
            actions.cancel()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: 44))
    }
}

/// Shows the rest panel while a rest that a logged set started runs for this exercise,
/// otherwise the given content. Observes the rest timer's state transitions only.
struct CutRestSlot<Content: View>: View {
    let source: CutRestSource
    let hasCompletedSet: Bool
    let nextLine: String?
    let actions: CutRestActions
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch source {
        case .none:
            content()
        case .fixed(let seconds):
            CutRestPanel(countdown: .fixed(seconds), nextLine: nextLine, actions: actions)
        case .live(let exerciseID):
            CutLiveRestGate(exerciseID: exerciseID, hasCompletedSet: hasCompletedSet, nextLine: nextLine,
                            actions: actions, content: content)
        }
    }
}

private struct CutLiveRestGate<Content: View>: View {
    let exerciseID: String
    let hasCompletedSet: Bool
    let nextLine: String?
    let actions: CutRestActions
    let content: () -> Content
    @ObservedObject private var manager = RestTimerManager.shared

    var body: some View {
        // The legacy rest badge's rule: a running timer for this exercise that a logged set started.
        if manager.isTimerFor(exerciseID: exerciseID), manager.isRunning, !manager.isManuallyStartedTimer, hasCompletedSet {
            CutRestPanel(countdown: .live, nextLine: nextLine, actions: actions)
                .transition(.opacity)
        } else {
            content()
        }
    }
}

/// The live countdown: the only view here that observes the per-second ticker.
private struct CutRestCountdown: View {
    @ObservedObject private var ticker = RestTimerManager.shared.ticker

    var body: some View {
        CutRestNumeral(seconds: ticker.remainingSeconds)
    }
}

private struct CutRestNumeral: View {
    let seconds: TimeInterval

    var body: some View {
        Text(CutTrainLogic.countdown(seconds))
            .font(DS.Cut.Typography.condensed(size: DS.Cut.Typography.Hero.xxl.size, monospacedDigits: true))
            .tracking(DS.Cut.Typography.Hero.xxl.tracking)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .accessibilityLabel("Rest")
            .accessibilityValue(Text(Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.minutes, .seconds]))))
    }
}

enum CutRestLogic {
    /// "Next: set 3, 85 kg x 6", or "Last set logged." while resting after the last set.
    static func nextLine(sets: [SetInput], activeSetIndex: Int, mode: CutSetMode, unit: WeightUnit) -> String? {
        let start = min(max(0, activeSetIndex), sets.count)
        // The first open set from the active one, then from the start.
        guard let index = sets[start...].firstIndex(where: { !$0.isCompleted })
                ?? sets[..<start].firstIndex(where: { !$0.isCompleted }) else {
            // Every set is logged. Whether a set follows depends on the auto add setting, the
            // four set cap and skip or cancel, so the line does not promise one.
            return sets.isEmpty ? nil : "Last set logged."
        }
        let set = sets[index]
        let value: String? = switch mode {
        case .weighted: set.weight > 0 && set.reps > 0 ? CutSetLoggingLogic.rowValue(set, mode: .weighted, unit: unit)
            : set.reps > 0 ? "\(set.reps) reps" : nil
        case .bodyweight: set.reps > 0 ? "\(set.reps) reps" : nil
        case .timed: set.durationSeconds > 0 ? CutSetLoggingLogic.clock(set.durationSeconds) : nil
        }
        return value.map { "Next: set \(index + 1), \($0)" } ?? "Next: set \(index + 1)"
    }
}
