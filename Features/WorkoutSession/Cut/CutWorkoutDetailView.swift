//
//  CutWorkoutDetailView.swift
//  WRKT
//
//  Workout records in the Cut language. A logged workout: the name as a modest hero with the
//  menu beside it, the date line, time and count stats as hairline columns, heart rate as
//  stat columns over a bar strip, zones as slanted bars, then every exercise with its sets as
//  hairline rows. An Apple Health strength workout: the name, the duration as the hero, the
//  stats, and adding exercise details as the one lime action. Plain values and closures only.
//

import SwiftUI

// MARK: - Workout detail

struct CutWorkoutDetailActions {
    var edit: () -> Void = {}
    var delete: () -> Void = {}
    /// The Stats button of an exercise.
    var showStats: (CutWorkoutDetailModel.Exercise) -> Void = { _ in }
    /// Tapping an exercise of the workout still running.
    var openSession: (CutWorkoutDetailModel.Exercise) -> Void = { _ in }
}

struct CutWorkoutDetailView: View {
    let model: CutWorkoutDetailModel
    var actions = CutWorkoutDetailActions()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if model.heartRate != nil {
                    heartRate.padding(.top, 36)
                }
                if let zones = model.zones {
                    CutWorkoutZonesSection(zones: zones).padding(.top, 36)
                }
                exercises.padding(.top, 36)
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutRecordTitle(title: model.title) {
                Menu {
                    Button("Edit workout", systemImage: "pencil", action: actions.edit)
                    Button("Delete workout", systemImage: "trash", role: .destructive, action: actions.delete)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            Text(model.dateLine)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if model.isEnhanced {
                Label("Enhanced with Apple Watch data", systemImage: "applewatch")
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if !model.statRows.isEmpty {
                VStack(spacing: 0) {
                    let rows = CutWorkoutDetailLogic.columnRows(model.statRows, maxColumns: isLargeText ? 2 : 4)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { CutHairline() }
                        CutStatColumns(row).padding(.vertical, 14)
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    // MARK: Heart rate

    @ViewBuilder
    private var heartRate: some View {
        if let heart = model.heartRate {
            VStack(alignment: .leading, spacing: 10) {
                let sampleCount = Text(heart.sampleCount)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                if isLargeText {
                    CutSectionTitle("Heart rate")
                    sampleCount
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        CutSectionTitle("Heart rate")
                        sampleCount.fixedSize()
                    }
                }
                CutHairline()
                if !heart.stats.isEmpty {
                    let rows = CutWorkoutDetailLogic.columnRows([heart.stats], maxColumns: isLargeText ? 2 : 4)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { CutHairline() }
                        CutStatColumns(row).padding(.top, 4)
                    }
                }
                if !heart.bars.isEmpty {
                    CutHeartRateBars(bars: heart.bars)
                        .padding(.top, 14)
                    if let start = heart.startLabel, let end = heart.endLabel {
                        HStack {
                            Text(start)
                            Spacer()
                            Text(end)
                        }
                        .cutFont(.secondary, monospacedDigits: true)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("From \(start) to \(end)"))
                    }
                }
            }
        }
    }

    // MARK: Exercises

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle("Exercises")
            CutHairline()
            if model.exercises.isEmpty {
                Text("No exercises in this workout.")
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.exercises) { exercise in
                        CutWorkoutExerciseBlock(exercise: exercise,
                                                showStats: { actions.showStats(exercise) },
                                                open: { actions.openSession(exercise) })
                    }
                }
            }
        }
    }
}

/// One exercise: the name with Stats beside it, a summary line, then one hairline row per set.
private struct CutWorkoutExerciseBlock: View {
    let exercise: CutWorkoutDetailModel.Exercise
    let showStats: () -> Void
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                if exercise.opensSession {
                    Button(action: open) {
                        HStack(spacing: 8) {
                            name
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the exercise in the current workout"))
                } else {
                    name.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Stats", action: showStats)
                    .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                    .fixedSize()
                    .accessibilityLabel(Text("\(exercise.name) stats"))
            }
            .padding(.top, 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.summary)
                if let timing = exercise.timing { Text(timing) }
            }
            .cutFont(.secondary)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
            .padding(.bottom, 8)
            ForEach(exercise.sets) { set in
                CutHairline()
                CutWorkoutSetRow(set: set)
            }
            CutHairline().padding(.top, 0)
        }
    }

    private var name: some View {
        Text(exercise.name)
            .cutFont(.title)
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct CutWorkoutSetRow: View {
    let set: CutWorkoutDetailModel.SetRow

    @ScaledMetric(relativeTo: .title3) private var numberWidth: CGFloat = 30
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(set.number)
                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .frame(minWidth: numberWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.value)
                    .cutFont(.body, monospacedDigits: true)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                if let timing = set.timing {
                    Text(timing)
                        .cutFont(.secondary, monospacedDigits: true)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                if let tag = set.tag, dynamicTypeSize.isAccessibilitySize {
                    Text(tag)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = set.tag, !dynamicTypeSize.isAccessibilitySize {
                Text(tag)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize()
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(["Set \(set.number)", set.value, set.tag, set.timing].compactMap { $0 }.joined(separator: ", ")))
    }
}

// MARK: - Shared record pieces

/// A record's title as a modest condensed hero with a round menu beside its first line.
struct CutRecordTitle<MenuContent: View>: View {
    let title: String
    @ViewBuilder var menu: () -> MenuContent

    /// Names of more than three words or 20 characters wrap rather than split in two lines.
    /// One word never wraps: it shrinks to fit instead.
    static func wraps(_ title: String) -> Bool {
        let words = title.split(whereSeparator: \.isWhitespace).count
        return words > 1 && (words > 3 || title.count > 20)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if Self.wraps(title) {
                    // A long name wraps at one size instead of shrinking each line on its own.
                    Text(title)
                        .cutHero(.xs, lines: 4, minimumScaleFactor: 0.7)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    CutHeroText(CutHeroText.balancedLines(title), hero: .xs, minimumScaleFactor: 0.5)
                }
            }
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            menu()
                .menuStyle(.button)
                .buttonStyle(CutIconButtonStyle(diameter: DS.Cut.Metrics.minTouchTarget))
                .fixedSize()
        }
    }
}

/// Heart rate over the workout as a strip of bars, as on the Cut cardio detail.
struct CutHeartRateBars: View {
    let bars: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                Rectangle()
                    .fill(DS.Cut.Colors.lime.opacity(0.25 + 0.75 * value))
                    .frame(height: 72 * value)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 72, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate over the workout"))
    }
}

/// Time in each zone as slanted bars on the lime ramp, as on the Cut cardio detail.
struct CutWorkoutZonesSection: View {
    let zones: CutWorkoutDetailModel.Zones

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle("Heart rate zones")
            if let method = zones.method {
                Text(method)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CutHairline()
            if zones.rows.isEmpty {
                Text("No heart rate zone data")
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .padding(.top, 4)
            } else if dynamicTypeSize.isAccessibilitySize {
                // Large text: the bar runs the full width under its label and time.
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(zones.rows) { zone in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(zone.label).cutFont(.title)
                                Spacer(minLength: 8)
                                Text(zone.time)
                                    .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                            }
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            CutCardioBar(fraction: zone.fraction,
                                         fill: DS.Cut.Colors.lime.opacity(0.35 + 0.13 * Double(zone.id)))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(zone.label), \(zone.time)"))
                    }
                }
                .padding(.top, 8)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    ForEach(zones.rows) { zone in
                        GridRow {
                            Text(zone.label)
                                .cutFont(.title)
                                .foregroundStyle(DS.Cut.Colors.textPrimary)
                                .fixedSize()
                                .accessibilityLabel(Text("\(zone.label), \(zone.time)"))
                            CutCardioBar(fraction: zone.fraction,
                                         fill: DS.Cut.Colors.lime.opacity(0.35 + 0.13 * Double(zone.id)))
                            Text(zone.time)
                                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                .foregroundStyle(DS.Cut.Colors.textPrimary)
                                .fixedSize()
                                .gridColumnAlignment(.trailing)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Apple Health strength

struct CutHealthStrengthActions {
    /// Edit the converted workout, or add exercise details to a new one.
    var edit: () -> Void = {}
    var delete: () -> Void = {}
}

struct CutHealthStrengthView: View {
    let model: CutHealthStrengthModel
    var actions = CutHealthStrengthActions()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                details.padding(.top, 28)
                if let notes = model.notes {
                    VStack(alignment: .leading, spacing: 10) {
                        CutSectionTitle("Notes")
                        CutHairline()
                        Text(notes)
                            .cutFont(.body)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 36)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutRecordTitle(title: model.title) {
                Menu {
                    Button(model.editTitle, systemImage: model.details == .added ? "pencil" : "plus", action: actions.edit)
                    Button("Delete workout", systemImage: "trash", role: .destructive, action: actions.delete)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.dateLine)
                Label(model.sourceLine, systemImage: "applewatch")
            }
            .cutFont(.secondary)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(model.hero.value)
                    .font(DS.Cut.Typography.condensed(size: DS.Cut.Typography.Hero.l.size, monospacedDigits: true))
                    .tracking(DS.Cut.Typography.Hero.l.tracking)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit = model.hero.unit {
                    Text(unit).cutHero(.xs).fixedSize()
                }
            }
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Duration \(model.hero.value) \(model.hero.unit ?? "")"))
            .padding(.top, 14)
            if !model.stats.isEmpty {
                CutStatColumns(model.stats).padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        switch model.details {
        case .canAdd:
            Button(action: actions.edit) {
                VStack(spacing: 0) {
                    CutHairline()
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add exercise details")
                                .cutHero(.xs, lines: 2, minimumScaleFactor: 0.6)
                                .foregroundStyle(DS.Cut.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Exercises, sets and weights. The Health data is kept.")
                                .cutFont(.secondary)
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        CutTile(systemImage: "plus", side: 48)
                    }
                    .padding(.vertical, 16)
                    CutHairline()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        case .added:
            VStack(alignment: .leading, spacing: 10) {
                CutHairline()
                Label("Exercise details added", systemImage: "checkmark")
                    .cutFont(.title)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                Text("This Apple Watch workout now includes its exercises and sets. The Health data is kept.")
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                CutHairline().padding(.top, 4)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
