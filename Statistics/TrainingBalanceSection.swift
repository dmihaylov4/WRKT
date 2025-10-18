//
//  TrainingBalanceSection.swift
//  WRKT
//
//  Priority 3: Training Balance Analytics

import SwiftUI
import SwiftData

// MARK: - Info Button Component (shared)
private struct InfoButton: View {
    let title: String
    let message: String
    @State private var showingAlert = false

    var body: some View {
        Button {
            showingAlert = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .alert(title, isPresented: $showingAlert) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

// MARK: - Section Container
struct TrainingBalanceSection: View {
    @Query private var pushPull: [PushPullBalance]
    @Query private var muscleFreq: [MuscleGroupFrequency]
    @Query private var movementPatterns: [MovementPatternBalance]

    private let weeks: Int

    init(weeks: Int = 12) {
        self.weeks = weeks

        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: .now) ?? .distantPast

        _pushPull = Query(
            filter: #Predicate<PushPullBalance> { $0.weekStart >= cutoff },
            sort: \PushPullBalance.weekStart,
            order: .forward
        )

        _movementPatterns = Query(
            filter: #Predicate<MovementPatternBalance> { $0.weekStart >= cutoff },
            sort: \MovementPatternBalance.weekStart,
            order: .forward
        )

        _muscleFreq = Query(sort: \MuscleGroupFrequency.lastTrained, order: .reverse)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Label("Training Balance", systemImage: "scale.3d")
                    .font(.headline)
                Spacer()
                InfoButton(
                    title: "Training Balance",
                    message: "Analytics to help you maintain balanced training across muscle groups, movement patterns, and training styles to reduce injury risk and optimize development."
                )
            }

        

            // 3A: Push/Pull Balance
            if !pushPull.isEmpty {
                PushPullBalanceCard(data: pushPull)
            } else {
                Text("No push/pull data found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 3B: Muscle Group Frequency
            if !muscleFreq.isEmpty {
                MuscleFrequencyHeatMap(muscles: muscleFreq)
            }

            // 3C: Movement Pattern Balance
            if !movementPatterns.isEmpty {
                MovementPatternCard(data: movementPatterns)
            }

            // Empty state
            if pushPull.isEmpty && muscleFreq.isEmpty && movementPatterns.isEmpty {
                ContentUnavailableView(
                    "No balance data yet",
                    systemImage: "scale.3d",
                    description: Text("Complete workouts to see balance analytics")
                )
            }
        }
    }
}

// MARK: - 3A: Push/Pull Balance Card
private struct PushPullBalanceCard: View {
    let data: [PushPullBalance]

    private var latest: PushPullBalance? { data.last }
    private var ratioStatus: (color: Color, message: String, icon: String) {
        guard let ratio = latest?.ratio else { return (.secondary, "No data", "minus.circle") }

        // Optimal ratio: 1.0-1.5 (equal to slightly more pulling)
        switch ratio {
        case 0.0:
            return (.secondary, "No pull exercises", "exclamationmark.triangle")
        case 0..<0.8:
            return (.red, "Too much pushing", "exclamationmark.triangle.fill")
        case 0.8..<1.0:
            return (.orange, "Slightly push-heavy", "exclamationmark.triangle")
        case 1.0..<1.5:
            return (.green, "Well balanced", "checkmark.circle.fill")
        case 1.5..<2.0:
            return (.orange, "Slightly pull-heavy", "exclamationmark.triangle")
        default:
            return (.red, "Too much pulling", "exclamationmark.triangle.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with status
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Label("Push/Pull Balance", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.weight(.semibold))
                        InfoButton(
                            title: "Push/Pull Balance",
                            message: "Tracks your ratio of pulling exercises (rows, pull-ups) to pushing exercises (bench press, overhead press). Optimal ratio is 1.0-1.5 (pull:push) to maintain shoulder health and posture. The ratio shows horizontal (H) and vertical (V) volume breakdown."
                        )
                    }
                    Text("Optimal ratio: 1.0-1.5 (pull:push)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if let latest = latest {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: ratioStatus.icon)
                                .font(.caption)
                            Text(String(format: "%.2f", latest.ratio))
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        .foregroundStyle(ratioStatus.color)

                        Text(ratioStatus.message)
                            .font(.caption2)
                            .foregroundStyle(ratioStatus.color)
                    }
                }
            }

            // Visual breakdown
            if let latest = latest {
                VStack(spacing: 8) {
                    // Push volume
                    BalanceBar(
                        label: "Push",
                        value: latest.pushVolume,
                        total: latest.pushVolume + latest.pullVolume,
                        color: .blue,
                        details: "H: \(shortVol(latest.horizontalPushVolume)) / V: \(shortVol(latest.verticalPushVolume))"
                    )

                    // Pull volume
                    BalanceBar(
                        label: "Pull",
                        value: latest.pullVolume,
                        total: latest.pushVolume + latest.pullVolume,
                        color: .green,
                        details: "H: \(shortVol(latest.horizontalPullVolume)) / V: \(shortVol(latest.verticalPullVolume))"
                    )
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))
    }

    private func shortVol(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v/1000) : String(Int(v))
    }
}

// MARK: - Balance Bar Component
private struct BalanceBar: View {
    let label: String
    let value: Double
    let total: Double
    let color: Color
    let details: String

    private var percentage: Double {
        total > 0 ? (value / total) * 100 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.0f%%", percentage))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * (percentage / 100))
                }
            }
            .frame(height: 8)

            Text(details)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 3B: Muscle Group Frequency Heat Map
private struct MuscleFrequencyHeatMap: View {
    let muscles: [MuscleGroupFrequency]

    private var sortedMuscles: [MuscleGroupFrequency] {
        muscles.sorted { $0.lastTrained > $1.lastTrained }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Label("Muscle Recovery Status", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                    InfoButton(
                        title: "Muscle Recovery Status",
                        message: "Shows when each muscle group was last trained (last 7 days) with color-coded recovery status. Green = recently trained (0-2 days), yellow/orange = moderate rest (3-6 days), red = not trained recently (7+ days). Frequency shows how many times trained in the last week."
                    )
                }
                Text("Last trained (last 7 days)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Grid of muscle tiles
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(sortedMuscles.prefix(12), id: \.muscleGroup) { muscle in
                    MuscleTile(muscle: muscle)
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))
    }
}

// MARK: - Muscle Tile Component
private struct MuscleTile: View {
    let muscle: MuscleGroupFrequency

    private var daysSince: Int {
        Calendar.current.dateComponents([.day], from: muscle.lastTrained, to: .now).day ?? 999
    }

    private var status: (color: Color, text: String) {
        switch daysSince {
        case 0...2:
            return (.green, "Fresh")
        case 3...4:
            return (.yellow, "\(daysSince)d ago")
        case 5...6:
            return (.orange, "\(daysSince)d ago")
        default:
            return (.red, "\(daysSince)d+ ago")
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(muscle.muscleGroup)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(status.text)
                .font(.caption2)
                .foregroundStyle(status.color)

            Text("\(muscle.weeklyFrequency)×")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(status.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(status.color.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - 3C: Movement Pattern Balance
private struct MovementPatternCard: View {
    let data: [MovementPatternBalance]

    private var latest: MovementPatternBalance? { data.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Label("Movement Patterns", systemImage: "figure.walk")
                        .font(.subheadline.weight(.semibold))
                    InfoButton(
                        title: "Movement Patterns",
                        message: "Analyzes the balance between different exercise types. Compound exercises work multiple joints/muscles (squats, deadlifts), while isolation targets single muscles (bicep curls). Bilateral uses both limbs (barbell bench), unilateral works one side (dumbbell rows). Hinge patterns (deadlifts) vs squat patterns (squats) for lower body."
                    )
                }
                Text("Exercise variety breakdown")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let latest = latest {
                VStack(spacing: 12) {
                    // Compound vs Isolation
                    PatternRow(
                        left: "Compound",
                        leftValue: latest.compoundVolume,
                        right: "Isolation",
                        rightValue: latest.isolationVolume,
                        leftColor: .purple,
                        rightColor: .pink
                    )

                    Divider()

                    // Bilateral vs Unilateral
                    PatternRow(
                        left: "Bilateral",
                        leftValue: latest.bilateralVolume,
                        right: "Unilateral",
                        rightValue: latest.unilateralVolume,
                        leftColor: .blue,
                        rightColor: .cyan
                    )

                    // Lower body: Hinge vs Squat (only show if there's data)
                    if latest.hingeVolume > 0 || latest.squatVolume > 0 {
                        Divider()

                        PatternRow(
                            left: "Hinge",
                            leftValue: latest.hingeVolume,
                            right: "Squat",
                            rightValue: latest.squatVolume,
                            leftColor: .orange,
                            rightColor: .yellow
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))
    }
}

// MARK: - Pattern Row Component
private struct PatternRow: View {
    let left: String
    let leftValue: Double
    let right: String
    let rightValue: Double
    let leftColor: Color
    let rightColor: Color

    private var total: Double { leftValue + rightValue }
    private var leftPercent: Double { total > 0 ? (leftValue / total) * 100 : 50 }
    private var rightPercent: Double { 100 - leftPercent }

    var body: some View {
        VStack(spacing: 6) {
            // Labels and values
            HStack {
                Label {
                    Text(left)
                        .font(.caption.weight(.medium))
                } icon: {
                    Circle()
                        .fill(leftColor)
                        .frame(width: 8, height: 8)
                }

                Spacer()

                Text(String(format: "%.0f%%", leftPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Split bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(leftColor)
                        .frame(width: geo.size.width * (leftPercent / 100))

                    Rectangle()
                        .fill(rightColor)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 8)

            HStack {
                Label {
                    Text(right)
                        .font(.caption.weight(.medium))
                } icon: {
                    Circle()
                        .fill(rightColor)
                        .frame(width: 8, height: 8)
                }

                Spacer()

                Text(String(format: "%.0f%%", rightPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
