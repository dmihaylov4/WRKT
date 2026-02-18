//  CalendarGrid.swift
//  WRKT
//
//  Calendar grid display components including month header, weekday labels, and day cells
//

import SwiftUI

// MARK: - Month Header
struct MonthHeader: View {
    @Binding var monthAnchor: Date
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onToday: () -> Void
    let onPlannerTap: () -> Void
    let weeklyStreak: Int
    let currentWeekProgress: WeeklyProgress?
    let selectedWeekProgress: WeeklyProgress?  // NEW: For showing selected week stats
    var captureButtonFrame: ((CGRect) -> Void)? = nil

    private var showingCurrentMonth: Bool {
        Calendar.current.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Month name with Create Plan button
                HStack(spacing: 8) {
                    Text(monthAnchor.formatted(.dateTime.year().month(.wide)))
                        .font(.title3.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Button {
                        onPlannerTap()
                    } label: {
                        Text("PLAN")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DS.Theme.accent, in: ChamferedRectangle(.small))
                    }
                    .background(GeometryReader { geometry in
                        Color.clear.preference(
                            key: PlannerButtonFrameKey.self,
                            value: geometry.frame(in: .global)
                        )
                    })
                    .onPreferenceChange(PlannerButtonFrameKey.self) { frame in
                        captureButtonFrame?(frame)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Button { onBack() } label: { Image(systemName: "chevron.left") }
                    Button { onForward() } label: { Image(systemName: "chevron.right") }
                        .opacity(canGoForward ? 1.0 : 0.35)
                        .disabled(!canGoForward)
                }
                .buttonStyle(.plain)
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.Theme.cardTop, in: Capsule())
                .overlay(Capsule().stroke(DS.Semantic.border, lineWidth: 1))

                if !showingCurrentMonth {
                    Button("Today", action: onToday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DS.Theme.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 16)

            // Weekly goal streak banner
            if weeklyStreak > 0 {
                WeeklyStreakBanner(streak: weeklyStreak)
                    .padding(.horizontal, 16)
            }

            // Week progress - show selected week if tapped, otherwise current week
            if let progress = selectedWeekProgress ?? currentWeekProgress {
                CurrentWeekProgressBanner(progress: progress)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedWeekProgress)
            }
        }
    }
}

// MARK: - Weekday Row
struct WeekdayRow: View {
    var body: some View {
        let sym = Calendar.current.shortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        let days = Array(sym[first..<sym.count] + sym[0..<first])

        HStack {
            ForEach(days, id: \.self) { d in
                Text(d.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Day Cell
struct DayCellV2: View {
    @EnvironmentObject var store: WorkoutStoreV2

    let date: Date
    let stats: DayStat
    let isSelected: Bool
    let inMonth: Bool
    let inActiveStreak: Bool
    let inCompletedWeek: Bool
    let inSuperWeek: Bool
    let inCurrentWeek: Bool
    let cellHeight: CGFloat
    let showWeekdayLabel: Bool // Only show on first row

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var isPlannedWorkoutCompleted: Bool {
        stats.isPlannedWorkoutCompleted(completedWorkouts: store.completedWorkouts)
    }

    private var backgroundColor: Color {
        // Simplified: only show background for selected or today
        if isSelected {
            return DS.Theme.accent.opacity(0.12)
        } else {
            return DS.Theme.cardTop
        }
    }

    private var borderColor: Color {
        if isSelected { return DS.Theme.accent }
        if isToday { return DS.Theme.accent.opacity(0.5) }
        return DS.Semantic.border.opacity(0.6)
    }

    private var borderWidth: CGFloat {
        if isSelected { return 2.5 }
        if isToday { return 2 }
        return 1
    }

    private var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE" // Short weekday (Mon, Tue, etc.)
        return formatter.string(from: date).uppercased()
    }

    var body: some View {
        ZStack {
            // Background and border for entire cell (including activity bar area)
            TopLeftChamferedRectangle(.small, cornerRadius: 10)
                .fill(backgroundColor)
                .overlay(
                    TopLeftChamferedRectangle(.small, cornerRadius: 10)
                        .stroke(borderColor, lineWidth: borderWidth)
                )

            // Content
            VStack(spacing: 0) {
                ZStack {
                    // Large cardio icon background (only when cardio only, no strength)
                    if !stats.cardioActivities.isEmpty && !stats.hasStrengthActivity && !stats.hasPlannedWorkout {
                        let iconName = stats.cardioActivities.first?.icon ?? "figure.run"
                        Image(systemName: iconName)
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(DS.Theme.accent.opacity(0.12))
                            .frame(width: 32, height: 32)
                            .clipped()
                            .offset(y: 0)
                    }

                    // Day number with optional weekday label above (first row only)
                    VStack(spacing: 1) {
                        if showWeekdayLabel {
                            Text(weekdayLabel)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.footnote.weight(isToday ? .bold : .regular))
                            .foregroundStyle(.white)
                    }

                }
                .frame(height: cellHeight)

                // Bottom activity bar - always present for consistent cell height
                activityBar
                    .frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .opacity(inMonth ? 1.0 : 0.45)
    }

    @ViewBuilder
    private var plannedWorkoutIndicator: some View {
        if isPlannedWorkoutCompleted {
            // Completed: checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(DS.Theme.accent)
        } else if stats.isPlannedScheduled {
            // Scheduled: outlined circle
            Circle()
                .stroke(DS.Theme.accent, lineWidth: 2)
                .frame(width: 8, height: 8)
        } else if stats.isPlannedPartial {
            // Partial: half-filled circle
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(.yellow, lineWidth: 2)
                .frame(width: 8, height: 8)
        } else if stats.isPlannedSkipped {
            // Skipped: X mark
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.gray.opacity(0.5))
        }
    }

    @ViewBuilder
    private var activityBar: some View {
        // Show activity bar for workouts OR planned workouts
        if stats.hasStrengthActivity || !stats.cardioActivities.isEmpty || stats.hasPlannedWorkout {
            HStack(spacing: 0) {
                // Strength activity section
                if stats.hasStrengthActivity {
                    ZStack {
                        Rectangle()
                            .fill(activityBarColor)
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 6, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 6, height: 6, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Cardio activity section
                if !stats.cardioActivities.isEmpty {
                    let iconName = stats.cardioActivities.first?.icon ?? "figure.run"
                    ZStack {
                        Rectangle()
                            .fill(activityBarColor)
                        Image(systemName: iconName)
                            .font(.system(size: 6, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 6, height: 6, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Planned workout section (if no actual workouts completed)
                if stats.hasPlannedWorkout && !stats.hasStrengthActivity && stats.cardioActivities.isEmpty {
                    ZStack {
                        Rectangle()
                            .fill(plannedWorkoutBarColor)
                        plannedWorkoutBarIcon
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    style: .continuous
                )
            )
        } else {
            // Empty space to maintain consistent cell height
            Color.clear
        }
    }

    private var isPastDay: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayStart = calendar.startOfDay(for: date)
        return dayStart < today
    }

    private var activityBarColor: Color {
        let baseColor: Color
        if isSelected {
            baseColor = DS.Theme.accent
        } else {
            baseColor = DS.Theme.accent.opacity(0.5)
        }

        // Reduce opacity for past days
        return isPastDay ? baseColor.opacity(0.6) : baseColor
    }

    private var plannedWorkoutBarColor: Color {
        if isPlannedWorkoutCompleted {
            return activityBarColor
        } else if stats.isPlannedScheduled {
            return isPastDay ? DS.Theme.accent.opacity(0.15) : DS.Theme.accent.opacity(0.25)
        } else if stats.isPlannedPartial {
            return .yellow.opacity(isPastDay ? 0.3 : 0.5)
        } else if stats.isPlannedSkipped {
            return .gray.opacity(isPastDay ? 0.15 : 0.25)
        }
        return DS.Theme.accent.opacity(0.25)
    }

    @ViewBuilder
    private var plannedWorkoutBarIcon: some View {
        if isPlannedWorkoutCompleted {
            Image(systemName: "checkmark")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.black)
        } else if stats.isPlannedScheduled {
            Circle()
                .stroke(.black, lineWidth: 1.5)
                .frame(width: 5, height: 5)
        } else if stats.isPlannedPartial {
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(.black, lineWidth: 1.5)
                .frame(width: 5, height: 5)
                .rotationEffect(.degrees(-90))
        } else if stats.isPlannedSkipped {
            Image(systemName: "xmark")
                .font(.system(size: 5, weight: .semibold))
                .foregroundStyle(.black)
        }
    }
}

// MARK: - Week Status Indicator
/// Displays week completion status as flame icons
struct WeekStatusIndicator: View {
    let isCompletedWeek: Bool
    let isSuperWeek: Bool
    let isCurrentWeek: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Flame centered vertically to match day numbers
            if isSuperWeek {
                // Super week: bright maroon flame with glow
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Theme.accent)
                    .shadow(color: DS.Theme.accent.opacity(0.5), radius: 4)
            } else if isCompletedWeek {
                // Completed week: solid maroon flame
                Image(systemName: "flame.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Theme.accent)
            } else if isCurrentWeek {
                // Current week in progress: outlined maroon flame
                Image(systemName: "flame")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Theme.accent.opacity(0.6))
            } else {
                // Incomplete week: grayed out flame
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.gray.opacity(0.3))
            }
        }
        .frame(width: 36, height: 52)  // Match total cell height (44 + 8 for activity bar)
        .contentShape(Rectangle())
        .onTapGesture {
            if let handler = onTap {
                Haptics.light()
                handler()
            }
        }
    }
}

// MARK: - Preference Key for Planner Button Frame
struct PlannerButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
