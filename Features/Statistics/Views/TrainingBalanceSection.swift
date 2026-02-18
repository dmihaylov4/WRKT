//
//  TrainingBalanceSection.swift
//  WRKT
//
//  Priority 3: Training Balance Analytics

import SwiftUI
import SwiftData
import SVGView

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
            ChamferedRectangle(.xl)
                .fill(Color.black)
                .overlay(
                    ChamferedRectangle(.xl)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
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

    @State private var selectedView: RecoveryViewMode = .enhanced
    @State private var selectedSide: BodySide = .front
    @State private var showDebugSheet = false

    enum RecoveryViewMode {
        case enhanced // SVG body view
        case grid     // Traditional grid
    }

    enum BodySide {
        case front, back
    }

    private var sortedMuscles: [MuscleGroupFrequency] {
        muscles.sorted { $0.lastTrained > $1.lastTrained }
    }

    // All major muscle groups for visualization (not used directly, but kept for reference)
    private static let allMuscleGroups = [
        "Chest", "Back", "Shoulders", "Biceps", "Triceps",
        "Quadriceps", "Hamstrings", "Glutes", "Calves",
        "Abs", "Forearms", "Adductors", "Hip Flexors", "Neck"
    ]

    // Map muscle group names to raw muscle names for SVG
    // These names will be processed by MuscleLexicon.tokens() which handles the conversion
    private static let muscleGroupToRawMuscles: [String: [String]] = [
        "Back": [
            "Latissimus Dorsi", "Lats",
            "Trapezius Upper", "Trapezius Middle", "Trapezius Lower",
            "Rhomboids", "Rhomboid",
            "Erector Spinae",
            "Infraspinatus", "Teres Minor"
        ],
        "Chest": [
            "Pectoralis Major", "Chest", "Pecs",
            "Pectoralis Minor",
            "Serratus Anterior"
        ],
        "Shoulders": [
            "Deltoid", "Deltoids"  // Generic shoulder exercises
        ],
        "Anterior Deltoids": [
            "Deltoid Anterior", "Anterior Deltoid", "Anterior Deltoids",
            "Front Delts", "Front Deltoid",
            "deltoid-anterior"  // Exact SVG ID
        ],
        "Lateral Deltoids": [
            "Deltoid Lateral", "Lateral Deltoid", "Lateral Deltoids",
            "Side Delts", "Middle Delts", "Middle Deltoid",
            "Deltoid-Exterior",  // Lateral/middle deltoid from SVG
            "Deltoid-Lateral",   // New SVG ID for lateral deltoid
            "deltoid-lateral"  // Exact SVG ID
        ],
        "Posterior Deltoids": [
            "Deltoid Posterior", "Posterior Deltoid", "Posterior Deltoids",
            "Rear Delts", "Rear Deltoid",
            "deltoid-posterior"  // Exact SVG ID
        ],
        "Biceps": [
            "Biceps Brachii", "Biceps",
            "Brachialis",
            "Brachioradialis"
        ],
        "Triceps": [
            "Triceps Brachii", "Triceps"
        ],
        "Quadriceps": [
            "Quadriceps", "Quads",
            "Sartorius"  // Hip flexor/knee flexor from SVG
        ],
        "Hamstrings": [
            "Hamstrings", "Hamstring",
            "Biceps Femoris",
            "Semitendinosus",
            "Semimembranosus"
        ],
        "Glutes": [
            "Gluteus Maximus", "Glute Max"
        ],
        "Calves": [
            "Gastrocnemius",
            "Soleus",
            "Tibialis Anterior", "Tibialis-Anterior",  // Shin muscle from SVG
            "tibialis-anterior",  // Exact SVG ID (lowercase)
            "Next-to-Soleus",  // Likely peroneals/fibularis from SVG
            "next-to-soleus",  // Exact SVG ID (lowercase)
            "Extensor Digitorum Longus",  // Toe extensor
            "extensor-digitorum-longus"  // Exact SVG ID
        ],
        "Abs": [
            "Rectus Abdominis", "Abs", "Abdominals",
            "Obliques", "External Oblique", "Internal Oblique"
        ],
        "Forearms": [
            "Forearm Flexors", "Wrist Flexors",
            "Forearm Extensors", "Wrist Extensors",
            "Brachioradialis",
            "Supinator"
        ],
        // Additional muscle groups that might not be tracked but should show as green
        "Adductors": [
            "Adductor Magnus", "Adductor Longus", "Adductor Brevis",
            "Gracilis", "Pectineus", "Hip Adductors"
        ],
        "Hip Flexors": [
            "Hip Flexors"
        ],
        "Neck": [
            "Splenius", "Splenius Capitis", "Splenius Cervicis",
            "Levator Scapulae"
        ],
        "Abductors": [
            "Abductors", "TFL"
        ]
    ]

    // Map muscles to recovery status for SVG coloring
    // Default: All muscles are green (ready/fresh)
    // Override: Trained muscles show their actual recovery status
    private var muscleRecoveryMap: [String: RecoveryStatus] {
        var map: [String: RecoveryStatus] = [:]

        // First, set all muscles to ready (default green for untrained muscles)
        for (groupName, rawMuscles) in Self.muscleGroupToRawMuscles {
            for rawMuscle in rawMuscles {
                map[rawMuscle] = .ready
            }
        }

        // Debug: Log tracked muscles
        AppLogger.debug("TrainingBalance: Found \(muscles.count) tracked muscle groups (will override default green)", category: AppLogger.statistics)
        for muscle in muscles {
            AppLogger.debug("  - \(muscle.muscleGroup): last trained \(muscle.lastTrained.formatted(date: .abbreviated, time: .omitted))", category: AppLogger.statistics)
        }

        // Then override with actual training data for muscles that have been worked
        for muscle in muscles {
            let daysSince = Calendar.current.dateComponents([.day], from: muscle.lastTrained, to: .now).day ?? 999
            let status: RecoveryStatus = {
                switch daysSince {
                case 0...1: return .fatigued  // 0-1 days: still fatigued (0-48h)
                case 2: return .recovering    // 2 days ago: 48-72h recovery
                case 3: return .recovered     // 3 days ago: 72-96h mostly recovered
                default: return .ready        // 4+ days: fully recovered
                }
            }()

            // Map normalized muscle group name to raw muscle names
            if let rawMuscles = Self.muscleGroupToRawMuscles[muscle.muscleGroup] {
                AppLogger.debug("  → Mapping '\(muscle.muscleGroup)' to \(rawMuscles.count) raw muscles with status \(status.label)", category: AppLogger.statistics)
                for rawMuscle in rawMuscles {
                    map[rawMuscle] = status
                }
            } else {
                AppLogger.warning("  ⚠️ No mapping found for muscle group '\(muscle.muscleGroup)'", category: AppLogger.statistics)
            }
        }

        AppLogger.debug("TrainingBalance: Final recovery map has \(map.count) entries", category: AppLogger.statistics)
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Label("Muscle Recovery Status", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    InfoButton(
                        title: "Muscle Recovery Status",
                        message: "Shows when each muscle group was last trained with color-coded recovery status. Red = fatigued (0-1 days/0-48h), yellow = recovering (2 days/48-72h), light green = recovered (3 days/72-96h), green = ready (4+ days/96h+). Based on muscle recovery science."
                    )

                    Spacer()

                    // View mode toggle
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedView = selectedView == .enhanced ? .grid : .enhanced
                        }
                    } label: {
                        Image(systemName: selectedView == .enhanced ? "square.grid.3x3.fill" : "figure.stand")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(6)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedView == .enhanced ? "Visual recovery map" : "Last trained (last 7 days)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))

                    // Debug: Show tracked muscle count
                    Button {
                        showDebugSheet = true
                    } label: {
                        Text("Tracking \(muscles.count) muscle groups · Tap for details")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content based on view mode
            if selectedView == .enhanced {
                EnhancedRecoveryView(
                    muscles: muscles,
                    recoveryMap: muscleRecoveryMap,
                    selectedSide: $selectedSide
                )
            } else {
                // Grid of muscle tiles
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(sortedMuscles.prefix(12), id: \.muscleGroup) { muscle in
                        MuscleTile(muscle: muscle)
                    }
                }
            }
        }
        .sheet(isPresented: $showDebugSheet) {
            NavigationStack {
                List {
                    Section("Tracked Muscle Groups") {
                        ForEach(sortedMuscles, id: \.muscleGroup) { muscle in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(muscle.muscleGroup)
                                    .font(.headline)
                                HStack {
                                    Text("Last trained: \(muscle.lastTrained, style: .date)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    let daysSince = Calendar.current.dateComponents([.day], from: muscle.lastTrained, to: .now).day ?? 999
                                    Text("\(daysSince) days ago")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Muscle Recovery Debug")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showDebugSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
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
        // Recovery status based on science (48-72h optimal recovery):
        // Day 0-1 (today/yesterday, 0-48h): Fatigued (red) - still fatigued
        // Day 2 (2 days ago, 48-72h): Recovering (yellow) - in recovery phase
        // Day 3 (3 days ago, 72-96h): Recovered (light green) - mostly recovered
        // Day 4+ (96h+): Ready (green) - fully recovered
        switch daysSince {
        case 0:
            return (DS.Status.error, "Today")
        case 1:
            return (DS.Status.error, "Yesterday")
        case 2:
            return (DS.Status.warning, "2d ago")
        case 3:
            return (DS.Calendar.partial, "3d ago")
        default:
            return (DS.Status.success, "Ready")
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

// MARK: - Recovery Status Enum

private enum RecoveryStatus {
    case fatigued   // 0-1 days - red
    case recovering // 2-3 days - yellow/orange
    case recovered  // 4-5 days - light green
    case ready      // 6+ days - green

    var color: Color {
        switch self {
        case .fatigued: return DS.Status.error
        case .recovering: return DS.Status.warning
        case .recovered: return DS.Calendar.partial
        case .ready: return DS.Status.success
        }
    }

    var label: String {
        switch self {
        case .fatigued: return "Fatigued"
        case .recovering: return "Recovering"
        case .recovered: return "Recovered"
        case .ready: return "Ready"
        }
    }

    var description: String {
        switch self {
        case .fatigued: return "0-1d"
        case .recovering: return "2d"
        case .recovered: return "3d"
        case .ready: return "4+d"
        }
    }
}

// MARK: - Enhanced Recovery View (SVG Body)

private struct EnhancedRecoveryView: View {
    let muscles: [MuscleGroupFrequency]
    let recoveryMap: [String: RecoveryStatus]
    @Binding var selectedSide: MuscleFrequencyHeatMap.BodySide

    // Convert muscle groups to sets for SVG highlighting
    private func musclesForStatus(_ status: RecoveryStatus) -> Set<String> {
        Set(recoveryMap.filter { $0.value == status }.keys)
    }

    private var fatiguedMuscles: Set<String> { musclesForStatus(.fatigued) }
    private var recoveringMuscles: Set<String> { musclesForStatus(.recovering) }
    private var recoveredMuscles: Set<String> { musclesForStatus(.recovered) }
    private var readyMuscles: Set<String> { musclesForStatus(.ready) }

    var body: some View {
        VStack(spacing: 16) {
            // Side toggle (Front/Back)
            HStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        selectedSide = .front
                    }
                } label: {
                    Text("Front")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedSide == .front ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedSide == .front 
                                ? Color.white.opacity(0.15) 
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.25)) {
                        selectedSide = .back
                    }
                } label: {
                    Text("Back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedSide == .back ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedSide == .back 
                                ? Color.white.opacity(0.15) 
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 1))

            // SVG Body Diagram with recovery coloring
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.03))

                // Body SVG
                RecoveryBodyView(
                    side: selectedSide == .front ? RecoverySVGBodyView.Side.front : RecoverySVGBodyView.Side.back,
                    fatigued: fatiguedMuscles,
                    recovering: recoveringMuscles,
                    recovered: recoveredMuscles,
                    ready: readyMuscles
                )
                .frame(height: 320)
                .padding(.vertical, 16)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

            // Legend
            RecoveryLegend()
        }
    }
}

// MARK: - Recovery Body View (SVG with color overlay)

private struct RecoveryBodyView: View {
    let side: RecoverySVGBodyView.Side
    let fatigued: Set<String>
    let recovering: Set<String>
    let recovered: Set<String>
    let ready: Set<String>

    var body: some View {
        RecoverySVGBodyView(
            side: side,
            fatigued: fatigued,
            recovering: recovering,
            recovered: recovered,
            ready: ready
        )
    }
}

// MARK: - Recovery SVG Body View (Custom colors)

private struct RecoverySVGBodyView: View {
    enum Side: Hashable { case front, back }

    let side: Side
    let fatigued: Set<String>
    let recovering: Set<String>
    let recovered: Set<String>
    let ready: Set<String>

    var body: some View {
        RecoverySVGBodyViewInner(
            side: side,
            fatigued: fatigued,
            recovering: recovering,
            recovered: recovered,
            ready: ready
        )
        .id(side) // Force recreation when side changes
    }
}

// Inner view that handles the actual SVG rendering
private struct RecoverySVGBodyViewInner: View {
    let side: RecoverySVGBodyView.Side
    let fatigued: Set<String>
    let recovering: Set<String>
    let recovered: Set<String>
    let ready: Set<String>

    private var highlightKey: String {
        let fatigued_str = fatigued.sorted().joined(separator: ",")
        let recovering_str = recovering.sorted().joined(separator: ",")
        let recovered_str = recovered.sorted().joined(separator: ",")
        let ready_str = ready.sorted().joined(separator: ",")
        return fatigued_str + "|" + recovering_str + "|" + recovered_str + "|" + ready_str
    }

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: side == .front ? "torso" : "torso_back",
                                         withExtension: "svg") {
                let svg = SVGView(contentsOf: url)
                svg
                    .aspectRatio(contentMode: .fit)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            applyRecoveryHighlights(into: svg)
                        }
                    }
                    .onChange(of: highlightKey) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            applyRecoveryHighlights(into: svg)
                        }
                    }
            } else {
                Rectangle().fill(.secondary.opacity(0.15))
                    .overlay(Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary))
                    .aspectRatio(0.56, contentMode: .fit)
            }
        }
    }

    private func applyRecoveryHighlights(into root: SVGView) {
        let idx = MuscleIndex.shared

        // Helper to get IDs from muscle names
        func getIDs(for muscles: Set<String>) -> Set<String> {
            var ids = Set<String>()
            for muscle in muscles {
                // First, try token-based lookup
                let tokens = MuscleLexicon.tokens(for: muscle)
                let foundIDs = idx.ids(forClassTokens: tokens, side: side == .front ? .front : .back)
                ids.formUnion(foundIDs)

                // Also try direct ID lookup (for elements without class attributes)
                // Convert muscle name to potential SVG ID format
                let directID = muscle.lowercased().replacingOccurrences(of: " ", with: "-")
                ids.insert(directID)
            }
            return ids
        }

        // Get SVG IDs for each recovery status
        var fatiguedIDs = getIDs(for: fatigued)
        var recoveringIDs = getIDs(for: recovering).subtracting(fatiguedIDs)
        var recoveredIDs = getIDs(for: recovered).subtracting(fatiguedIDs).subtracting(recoveringIDs)
        var readyIDs = getIDs(for: ready).subtracting(fatiguedIDs).subtracting(recoveringIDs).subtracting(recoveredIDs)

        // Debug: Log what we're coloring
        AppLogger.debug("RecoverySVG (\(side == .front ? "front" : "back")): Coloring \(fatiguedIDs.count) fatigued, \(recoveringIDs.count) recovering, \(recoveredIDs.count) recovered, \(readyIDs.count) ready", category: AppLogger.statistics)
        if !readyIDs.isEmpty {
            AppLogger.debug("  Ready IDs: \(Array(readyIDs).sorted().joined(separator: ", "))", category: AppLogger.statistics)
        }

        // Apply colors with custom recovery colors instead of purple
        colorMuscles(ids: Array(readyIDs), in: root, colorName: "green", opacity: 0.7)
        colorMuscles(ids: Array(recoveredIDs), in: root, colorName: "lightgreen", opacity: 0.7)
        colorMuscles(ids: Array(recoveringIDs), in: root, colorName: "orange", opacity: 0.7)
        colorMuscles(ids: Array(fatiguedIDs), in: root, colorName: "red", opacity: 0.7)
    }

    private func paintNode(_ node: SVGNode, colorName: String, targetOpacity: Double) {
        if let shape = node as? SVGShape {
            shape.fill = SVGColor.by(name: colorName)
            shape.opacity = targetOpacity
        } else if let group = node as? SVGGroup {
            group.opacity = max(group.opacity, targetOpacity)
            for child in group.contents {
                paintNode(child, colorName: colorName, targetOpacity: targetOpacity)
            }
        } else {
            node.opacity = max(node.opacity, targetOpacity)
        }
    }

    private func colorMuscles(ids: [String], in root: SVGView, colorName: String, opacity: Double) {
        for id in ids {
            if let node = root.getNode(byId: id) {
                paintNode(node, colorName: colorName, targetOpacity: opacity)
            }
        }
    }
}

// MARK: - Recovery Legend

private struct RecoveryLegend: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                LegendItem(color: DS.Status.error, label: "Fatigued", detail: "0-1d")
                LegendItem(color: DS.Status.warning, label: "Recovering", detail: "2d")
            }
            HStack(spacing: 12) {
                LegendItem(color: DS.Calendar.partial, label: "Recovered", detail: "3d")
                LegendItem(color: DS.Status.success, label: "Ready", detail: "4+d")
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
