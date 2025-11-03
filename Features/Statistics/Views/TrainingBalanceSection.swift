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
                .foregroundStyle(.white.opacity(0.5))
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
        VStack(alignment: .leading, spacing: 20) {
            // Premium section header
            HStack(alignment: .center, spacing: 12) {
                // Icon with gradient background
                ZStack {
                    LinearGradient(
                        colors: [DS.Theme.accent.opacity(0.3), DS.Theme.accent.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Image(systemName: "scale.3d")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DS.Theme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Training Balance")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Last \(weeks) weeks")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                InfoButton(
                    title: "Training Balance",
                    message: "Analytics to help you maintain balanced training across muscle groups, movement patterns, and training styles to reduce injury risk and optimize development."
                )
            }
            .padding(.bottom, 4)

            // Content cards with subtle separators
            VStack(spacing: 16) {
                // 3A: Push/Pull Balance
                if !pushPull.isEmpty {
                    PushPullBalanceCard(data: pushPull)
                } else {
                    EmptyDataCard(message: "No push/pull data found")
                }

                if !pushPull.isEmpty && !muscleFreq.isEmpty {
                    Divider()
                        .background(.white.opacity(0.08))
                }

                // 3B: Muscle Group Frequency
                if !muscleFreq.isEmpty {
                    MuscleFrequencyHeatMap(muscles: muscleFreq)
                }

                if !muscleFreq.isEmpty && !movementPatterns.isEmpty {
                    Divider()
                        .background(.white.opacity(0.08))
                }

                // 3C: Movement Pattern Balance
                if !movementPatterns.isEmpty {
                    MovementPatternCard(data: movementPatterns)
                }

                // Empty state
                if pushPull.isEmpty && muscleFreq.isEmpty && movementPatterns.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "scale.3d")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))

                        Text("No balance data yet")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))

                        Text("Complete workouts to see balance analytics")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DS.Theme.cardTop, DS.Theme.cardBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Empty Data Card
private struct EmptyDataCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.4))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))

            Spacer()
        }
        .padding(16)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
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
            return (DS.Status.error, "Too much pushing", "exclamationmark.triangle.fill")
        case 0.8..<1.0:
            return (DS.Status.warning, "Slightly push-heavy", "exclamationmark.triangle")
        case 1.0..<1.5:
            return (DS.Status.success, "Well balanced", "checkmark.circle.fill")
        case 1.5..<2.0:
            return (DS.Status.warning, "Slightly pull-heavy", "exclamationmark.triangle")
        case 10..<Double.infinity:
            return (DS.Status.error, "No push exercises", "exclamationmark.triangle.fill")
        default:
            return (DS.Status.error, "Too much pulling", "exclamationmark.triangle.fill")
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
                            .foregroundStyle(.white.opacity(0.9))
                        InfoButton(
                            title: "Push/Pull Balance",
                            message: "Tracks your ratio of pulling exercises (rows, pull-ups) to pushing exercises (bench press, overhead press). Optimal ratio is 1.0-1.5 (pull:push) to maintain shoulder health and posture. The ratio shows horizontal (H) and vertical (V) volume breakdown."
                        )
                    }
                    Text("Optimal ratio: 1.0-1.5 (pull:push)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
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
                        color: DS.Charts.push,
                        details: "H: \(shortVol(latest.horizontalPushVolume)) / V: \(shortVol(latest.verticalPushVolume))"
                    )

                    // Pull volume
                    BalanceBar(
                        label: "Pull",
                        value: latest.pullVolume,
                        total: latest.pushVolume + latest.pullVolume,
                        color: DS.Charts.pull,
                        details: "H: \(shortVol(latest.horizontalPullVolume)) / V: \(shortVol(latest.verticalPullVolume))"
                    )
                }
            }
        }
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
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(String(format: "%.0f%%", percentage))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * (percentage / 100))
                }
            }
            .frame(height: 8)

            Text(details)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
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
                        .foregroundStyle(.white.opacity(0.9))
                    InfoButton(
                        title: "Muscle Recovery Status",
                        message: "Shows when each muscle group was last trained (last 7 days) with color-coded recovery status. Green = recently trained (0-2 days), yellow/orange = moderate rest (3-6 days), red = not trained recently (7+ days). Frequency shows how many times trained in the last week."
                    )
                }
                Text("Last trained (last 7 days)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Grid of muscle tiles
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(sortedMuscles.prefix(12), id: \.muscleGroup) { muscle in
                    MuscleTile(muscle: muscle)
                }
            }
        }
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
            return (DS.Status.success, "Fresh")
        case 3...4:
            return (DS.Calendar.partial, "\(daysSince)d ago")
        case 5...6:
            return (DS.Status.warning, "\(daysSince)d ago")
        default:
            return (DS.Status.error, "\(daysSince)d+ ago")
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(muscle.muscleGroup)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(status.text)
                .font(.caption2)
                .foregroundStyle(status.color)

            Text("\(muscle.weeklyFrequency)×")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(status.color.opacity(0.4), lineWidth: 1))
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
                        .foregroundStyle(.white.opacity(0.9))
                    InfoButton(
                        title: "Movement Patterns",
                        message: "Analyzes the balance between different exercise types. Compound exercises work multiple joints/muscles (squats, deadlifts), while isolation targets single muscles (bicep curls). Bilateral uses both limbs (barbell bench), unilateral works one side (dumbbell rows). Hinge patterns (deadlifts) vs squat patterns (squats) for lower body."
                    )
                }
                Text("Exercise variety breakdown")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let latest = latest {
                VStack(spacing: 12) {
                    // Compound vs Isolation
                    PatternRow(
                        left: "Compound",
                        leftValue: latest.compoundVolume,
                        right: "Isolation",
                        rightValue: latest.isolationVolume,
                        leftColor: DS.Charts.push,
                        rightColor: DS.Charts.push.opacity(0.6)
                    )

                    Divider()
                        .background(.white.opacity(0.08))

                    // Bilateral vs Unilateral
                    PatternRow(
                        left: "Bilateral",
                        leftValue: latest.bilateralVolume,
                        right: "Unilateral",
                        rightValue: latest.unilateralVolume,
                        leftColor: DS.Charts.legs,
                        rightColor: DS.Charts.legs.opacity(0.6)
                    )

                    // Lower body: Hinge vs Squat (only show if there's data)
                    if latest.hingeVolume > 0 || latest.squatVolume > 0 {
                        Divider()
                            .background(.white.opacity(0.08))

                        PatternRow(
                            left: "Hinge",
                            leftValue: latest.hingeVolume,
                            right: "Squat",
                            rightValue: latest.squatVolume,
                            leftColor: DS.Charts.pull,
                            rightColor: DS.Calendar.partial
                        )
                    }
                }
            }
        }
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
                        .foregroundStyle(.white.opacity(0.9))
                } icon: {
                    Circle()
                        .fill(leftColor)
                        .frame(width: 8, height: 8)
                }

                Spacer()

                Text(String(format: "%.0f%%", leftPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
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
                        .foregroundStyle(.white.opacity(0.9))
                } icon: {
                    Circle()
                        .fill(rightColor)
                        .frame(width: 8, height: 8)
                }

                Spacer()

                Text(String(format: "%.0f%%", rightPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
