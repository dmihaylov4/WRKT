// LiveWorkoutOverlayCard.swift
import SwiftUI

private enum Theme {
    static let brand         = Color(hex: "#F4E409")
    static let cardTop       = Color(hex: "#121212")   // opaque
    static let cardBottom    = Color(hex: "#333333")   // opaque
    static let cardBorder    = Color.white.opacity(0.08)
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.65)
}

struct LiveWorkoutOverlayCard: View {
    @EnvironmentObject var store: WorkoutStore

    let namespace: Namespace.ID
    let title: String
    let subtitle: String
    let showContent: Bool
    let onClose: () -> Void
    let startDate: Date

    @State private var dragOffset: CGFloat = 0
    @State private var editingEntry: WorkoutEntry? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
                .matchedGeometryEffect(id: "liveHeader", in: namespace)

            Divider().overlay(Theme.cardBorder).opacity(0.7)

            Group {
                if let current = store.currentWorkout, !current.entries.isEmpty {
                    content(for: current)
                } else {
                    ContentUnavailableView("No active workout", systemImage: "bolt.heart")
                        .padding(.vertical, 40)
                }
            }
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.98, anchor: .top)
            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: showContent)
        }
        .foregroundStyle(Theme.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.cardBottom, Theme.cardBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
                .matchedGeometryEffect(id: "liveCardBG", in: namespace)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 18, x: 0, y: 10)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in dragOffset = max(0, value.translation.height) }
                .onEnded { value in
                    let shouldClose = value.translation.height > 80 || value.velocity > 600
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                        if shouldClose { onClose() }
                        dragOffset = 0
                    }
                }
        )
        .sheet(item: $editingEntry) { entry in
            if let ex = store.exerciseForEntry(entry) {
                NavigationStack {
                    ExerciseSessionView(
                        exercise: ex,
                        currentEntryID: entry.id,
                        returnToHomeOnSave: false
                    )
                    .environmentObject(store)
                }
            } else {
                Text("Exercise not found")
            }
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.heart.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.brand)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    WorkoutTimerText(startDate: startDate)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            // Add: go to Home to pick an exercise (your earlier UX)
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
                NotificationCenter.default.post(name: .resetHomeToRoot, object: nil)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.brand)
            }
            .accessibilityLabel("Add exercise")

            // Close
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel("Close live workout")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Content
    @ViewBuilder
    private func content(for current: CurrentWorkout) -> some View {
        List {
            Section("In Progress") {
                ForEach(current.entries, id: \.id) { e in
                    LiveWorkoutRow(
                        entry: e,
                        onOpen:   { editingEntry = e },
                        onRemove: { store.removeEntry(entryID: e.id) },
                        onDuplicate: nil
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .headerProminence(.increased)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)             // don’t show default list bg
        .environment(\.colorScheme, .dark)               // keep our glass
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OverlayBottomActions(
                onFinish: {
                    // 1) Finish & get PR count to report
                    let result = store.finishCurrentWorkoutAndReturnPRs()   // (workoutId, prCount)
                    RewardsEngine.shared.process(event: "workout_completed", payload: ["workoutId": result.workoutId])
                    
                    // 2) Rewards events
                    let seen = Set(store.completedWorkouts.dropFirst().flatMap { $0.entries.map(\.exerciseID) })
                    let thisIDs = Set((store.completedWorkouts.first?.entries ?? []).map(\.exerciseID))
                    let newIDs = thisIDs.subtracting(seen)
                    for id in newIDs {
                        RewardsEngine.shared.process(event: "exercise_new", payload: ["exerciseId": id])
                    }
                    
                    RewardsEngine.shared.process(event: "workout_completed", payload: [
                        "workoutId": result.workoutId
                    ])
                    if result.prCount > 0 {
                        RewardsEngine.shared.process(event: "pr_achieved", payload: [
                            "count": result.prCount
                        ])
                    }
                    

                    // 3) Close UI
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
                },
                onDiscard: {
                    store.discardCurrentWorkout()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
                }
            )
            //OverlayBottomActions(
              //  onFinish: {
                //    store.finishCurrentWorkout()
                  //  UINotificationFeedbackGenerator().notificationOccurred(.success)
                    //withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
               // },
                //onDiscard: {
                  //  store.discardCurrentWorkout()
                    //UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    //withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
               // }
           // )
            //.background(LinearGradient(
              //  colors: [Theme.cardBottom.opacity(0.0), Theme.cardBottom.opacity(0.25)],
                //startPoint: .top, endPoint: .bottom
            //))
        }
    }
}

// MARK: - Helpers
private extension DragGesture.Value {
    var velocity: CGFloat {
        let dy = predictedEndLocation.y - location.y
        return abs(dy) * 10
    }
}

// MARK: - Bottom actions (dark/brand styling)
private struct OverlayBottomActions: View {
    let onFinish: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Swipe — looks good on dark
            SwipeToConfirm(
                text: "Slide to finish workout",
                systemImage: "checkmark.seal.fill",
                background: .thinMaterial,                   // ignored if trackColor set
                trackColor: Color(hex: "#151515"),           // ← solid track
                knobSize: 52,
                onConfirm: onFinish
            )
            .tint(Theme.brand)
            //.tint(Theme.brand)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) { onDiscard() } label: {
                HStack {
                    Spacer()
                    Label("Discard Workout", systemImage: "trash")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .foregroundStyle(Theme.textPrimary)
    }
}

// MARK: - Row
private struct LiveWorkoutRow: View {
    let entry: WorkoutEntry
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onDuplicate: (() -> Void)?

    private var summary: String {
        if entry.sets.isEmpty { return "No sets yet" }
        return entry.sets.map { "\($0.reps)×\(Int($0.weight))kg" }.joined(separator: "  •  ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.brand.opacity(0.18))
                Image(systemName: "dumbbell")
                    .foregroundStyle(Theme.brand)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.exerciseName)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.white.opacity(0.5))

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityLabel("Remove \(entry.exerciseName)")
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
            if let onDuplicate {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
            if let onDuplicate {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
        }
    }
}

// MARK: - Timer (numbers only, tiny neon pill)
struct WorkoutTimerText: View {
    let startDate: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(startDate))
            let h = Int(elapsed) / 3600
            let m = (Int(elapsed) % 3600) / 60
            let s = Int(elapsed) % 60
            Text(String(format: "%02d:%02d:%02d", h, m, s))
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(Theme.brand)
                .background(Theme.brand.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Theme.brand.opacity(0.35), lineWidth: 1))
        }
    }
}

// MARK: - Small hex Color helper
private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >>  8) & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
