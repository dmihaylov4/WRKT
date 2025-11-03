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
    let weeklyStreak: Int
    let currentWeekProgress: WeeklyProgress?

    private var showingCurrentMonth: Bool {
        Calendar.current.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(monthAnchor.formatted(.dateTime.year().month(.wide)))
                    .font(.title3.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

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

            // Current week progress
            if let progress = currentWeekProgress {
                CurrentWeekProgressBanner(progress: progress)
                    .padding(.horizontal, 16)
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

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var isPlannedWorkoutCompleted: Bool {
        stats.isPlannedWorkoutCompleted(completedWorkouts: store.completedWorkouts)
    }

    private var backgroundColor: Color {
        if inSuperWeek {
            // Super week: premium golden/amber glow
            return DS.Theme.accent.opacity(0.25)
        } else if inCompletedWeek {
            return DS.Theme.accent.opacity(0.15)
        } else if inCurrentWeek {
            return DS.Theme.accent.opacity(0.08)
        } else if inActiveStreak {
            return DS.Theme.accent.opacity(0.22)
        } else {
            return DS.Theme.cardTop
        }
    }

    private var borderColor: Color {
        if isSelected { return DS.Theme.accent }
        if inSuperWeek { return DS.Theme.accent }  // Super week: full accent border
        if inCompletedWeek { return DS.Theme.accent.opacity(0.6) }
        if isToday { return DS.Semantic.border }
        return DS.Semantic.border.opacity(0.6)
    }

    private var borderWidth: CGFloat {
        if inSuperWeek || isSelected { return 2.5 }  // Thicker border for super weeks
        if inCompletedWeek { return 2 }
        return 1
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(borderColor, lineWidth: borderWidth)
                    )

                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundStyle(.white)
            }
            .frame(height: cellHeight)

            // tiny markers - workout indicators at bottom
            HStack(spacing: 4) {
                // Planned workout completed: checkmark
                if stats.hasPlannedWorkout && isPlannedWorkoutCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Theme.accent)
                }
                // Strength workout: dumbbell icon (in-app OR HealthKit)
                else if stats.hasStrengthActivity {
                    // Show count if multiple strength sessions
                    if stats.totalStrengthSessions > 1 {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(DS.Theme.accent)
                            Text("\(stats.totalStrengthSessions)")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(1)
                                .background(DS.Theme.accent, in: Circle())
                                .offset(x: 2, y: -2)
                        }
                    } else {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DS.Theme.accent)
                    }
                }

                // Planned workouts not completed
                if stats.hasPlannedWorkout && !isPlannedWorkoutCompleted && !stats.hasStrengthActivity {
                    if stats.isPlannedScheduled {
                        // Scheduled: outlined capsule
                        Capsule()
                            .stroke(DS.Theme.accent, lineWidth: 1.5)
                            .frame(width: 12, height: 4)
                    } else if stats.isPlannedPartial {
                        // Partial: yellow
                        Capsule().fill(.yellow).frame(width: 12, height: 4)
                    } else if stats.isPlannedSkipped {
                        // Skipped: gray
                        Capsule().fill(.gray.opacity(0.5)).frame(width: 12, height: 4)
                    }
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .opacity(inMonth ? 1.0 : 0.45)
        .overlay(alignment: .top) {
            // Cardio activity icons: centered on top border like "walking on the cell"
            if !stats.cardioActivities.isEmpty {
                let uniqueTypes = Array(Set(stats.cardioActivities)).sorted { $0.rawValue < $1.rawValue }
                HStack(spacing: 2) {
                    ForEach(uniqueTypes, id: \.self) { activityType in
                        Image(systemName: activityType.icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.Theme.accent)
                    }
                }
                .offset(y: -5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if inCompletedWeek && isToday {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.black)
                    .padding(4)
                    .background(DS.Theme.accent, in: Circle())
                    .offset(x: 4, y: -4)
            } else if inActiveStreak && isToday {
                Image(systemName: "flame.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.black)
                    .padding(4)
                    .background(DS.Theme.accent, in: Circle())
                    .offset(x: 4, y: -4)
            }
        }
    }
}
