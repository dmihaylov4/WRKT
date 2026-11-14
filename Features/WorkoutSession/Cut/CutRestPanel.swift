//
//  CutRestPanel.swift
//  WRKT
//
//  The rest timer in the Cut language, for the set logging sheet: a 64 pt lime countdown with
//  "rest left" beside it, a slanted progress bar, and outlined pills to add time, skip, or
//  cancel. Shown while a rest that a logged set started runs for that exercise.
//
//  Only the countdown and the bar observe the per-second ticker; the gate observes state
//  transitions.
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

/// A rest the screen shows: where the remaining time comes from, and the rest's full length
/// for the progress bar.
struct CutRestState: Equatable {
    var countdown: CutTrainCountdown
    var total: TimeInterval
}

struct CutRestPanel: View {
    let state: CutRestState
    var actions = CutRestActions()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch state.countdown {
                case .live: CutLiveRestReadout(total: state.total)
                case .fixed(let seconds): CutRestReadout(seconds: seconds, total: state.total)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { addButton; skipButton }
                    cancelButton
                }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }
            .padding(.top, 18)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        addButton
        skipButton
        cancelButton
    }

    private var addButton: some View {
        Button("+15 s", action: actions.addTime)
            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            .accessibilityLabel("Add 15 seconds")
    }

    private var skipButton: some View {
        Button("Skip rest") {
            Haptics.medium()
            actions.skip()
        }
        .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
    }

    private var cancelButton: some View {
        Button("Cancel rest", systemImage: "xmark") {
            actions.cancel()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: 44))
    }
}

/// Gives the content the running rest, if a rest that a logged set started runs for this
/// exercise. Observes the rest timer's state transitions only.
struct CutRestGate<Content: View>: View {
    let source: CutRestSource
    let hasCompletedSet: Bool
    /// The rest's length when the source does not know it (fixed captures).
    let fallbackTotal: TimeInterval
    @ViewBuilder let content: (CutRestState?) -> Content

    var body: some View {
        switch source {
        case .none:
            content(nil)
        case .fixed(let seconds):
            content(CutRestState(countdown: .fixed(seconds), total: max(fallbackTotal, seconds)))
        case .live(let exerciseID):
            CutLiveRestGate(exerciseID: exerciseID, hasCompletedSet: hasCompletedSet, content: content)
        }
    }
}

private struct CutLiveRestGate<Content: View>: View {
    let exerciseID: String
    let hasCompletedSet: Bool
    let content: (CutRestState?) -> Content
    @ObservedObject private var manager = RestTimerManager.shared

    private var rest: CutRestState? {
        // The legacy rest badge's rule: a running timer for this exercise that a logged set started.
        guard manager.isTimerFor(exerciseID: exerciseID), manager.isRunning, !manager.isManuallyStartedTimer,
              hasCompletedSet else { return nil }
        let total: TimeInterval = switch manager.state {
        case .running(_, _, _, let original, _), .paused(_, _, _, let original, _): original
        case .idle, .completed: 0
        }
        return CutRestState(countdown: .live, total: total)
    }

    var body: some View {
        content(rest)
            .animation(.easeInOut(duration: 0.2), value: rest == nil)
    }
}

/// The live countdown and bar: the only views here that observe the per-second ticker.
private struct CutLiveRestReadout: View {
    let total: TimeInterval
    @ObservedObject private var ticker = RestTimerManager.shared.ticker

    var body: some View {
        CutRestReadout(seconds: ticker.remainingSeconds, total: total)
    }
}

private struct CutRestReadout: View {
    let seconds: TimeInterval
    let total: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(CutTrainLogic.countdown(seconds))
                    .cutNumeral(.rest)
                    .foregroundStyle(DS.Cut.Colors.lime)
                    .fixedSize()
                Text("rest left")
                    .font(DS.Cut.Typography.font(.body).weight(.medium))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest")
            .accessibilityValue(Text(Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.minutes, .seconds]))))
            CutRestBar(fraction: CutRestLogic.remainingFraction(seconds: seconds, total: total))
        }
    }
}

/// The slanted 8 pt bar: lime for the rest that remains.
private struct CutRestBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(DS.Cut.Colors.segmentTrack)
            Rectangle().fill(DS.Cut.Colors.lime)
                .scaleEffect(x: fraction, y: 1, anchor: .leading)
        }
        .frame(height: 8)
        .clipShape(SlantedSegmentShape(slant: 8))
        .animation(.linear(duration: 0.3), value: fraction)
        .accessibilityHidden(true)
    }
}

enum CutRestLogic {
    /// The set that follows the rest: the first open set from the active one, then from the start.
    static func nextIndex(sets: [SetInput], activeSetIndex: Int) -> Int? {
        let start = min(max(0, activeSetIndex), sets.count)
        return sets[start...].firstIndex(where: { !$0.isCompleted })
            ?? sets[..<start].firstIndex(where: { !$0.isCompleted })
    }

    /// The last logged set, for "Sets so far".
    static func lastLoggedIndex(sets: [SetInput]) -> Int? {
        sets.lastIndex(where: \.isCompleted)
    }

    /// One set's values on one line: "85 kg x 6", "6 reps" without a weight, "12 reps", "0:45".
    static func value(_ set: SetInput, mode: CutSetMode, unit: WeightUnit) -> String {
        switch mode {
        case .weighted:
            set.weight > 0 ? CutSetLoggingLogic.rowValue(set, mode: .weighted, unit: unit) : "\(set.reps)\u{00A0}reps"
        case .bodyweight:
            "\(set.reps)\u{00A0}reps"
        case .timed:
            CutSetLoggingLogic.clock(set.durationSeconds)
        }
    }

    /// How much of the rest remains, 0...1.
    static func remainingFraction(seconds: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0, seconds.isFinite else { return 0 }
        return min(1, max(0, seconds / total))
    }
}
