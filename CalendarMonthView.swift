//  CalendarMonthView.swift (revised)
//  WRKT
//
//  A brighter, streak-first calendar with a simple, workout-centric day detail.
//

import SwiftUI
import Foundation

// MARK: - Theme
private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = Color(hex: "#F4E409")
}

// MARK: - Tiny helpers
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:(a, r, g, b) = (255, 244, 228, 9)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? { indices.contains(idx) ? self[idx] : nil }
}

private func timeOnly(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

private func hms(_ seconds: Int) -> String {
    String(format: "%02d:%02d:%02d", seconds/3600, (seconds%3600)/60, seconds%60)
}


// MARK: - Calendar View
struct CalendarMonthView: View {
    @EnvironmentObject var store: WorkoutStore

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date = .now

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let cellHeight: CGFloat = 44

    // Convenience
    private var startOfCurrentMonth: Date { Calendar.current.dateInterval(of: .month, for: .now)!.start }
    private var hasActiveWorkout: Bool { (store.currentWorkout?.entries.isEmpty == false) }

    // Streak
    private var streakLength: Int { max(store.streak(), 0) }
    private func hasActivity(on d: Date) -> Bool {
        !store.workouts(on: d).isEmpty || !store.runs(on: d).isEmpty
    }
    private func isInActiveStreak(_ d: Date) -> Bool {
        guard streakLength > 0 else { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let windowStart = cal.date(byAdding: .day, value: -(streakLength - 1), to: today) else { return false }
        let startOfD = cal.startOfDay(for: d)
        let inWindow = (startOfD >= windowStart) && (startOfD <= today)
        return inWindow && hasActivity(on: d)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            MonthHeader(
                monthAnchor: $monthAnchor,
                canGoForward: canGoForward,
                onBack: { bump(-1) },
                onForward: { bump(+1) },
                onToday: { jumpToToday() },
                streak: store.streak()
            )
            .padding(.top, 12)

            // Weekday labels
            WeekdayRow().padding(.horizontal, 16)

            // Month grid
            let days = daysInMonth()
            let rows = max(1, days.count / 7)
            let gridHeight = CGFloat(rows) * cellHeight + CGFloat((rows - 1)) * 6

            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let stats = dayStat(for: day)
                    let inMonth = Calendar.current.isDate(day, equalTo: monthAnchor, toGranularity: .month)
                    DayCellV2(
                        date: day,
                        stats: stats,
                        isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay),
                        inMonth: inMonth,
                        inActiveStreak: isInActiveStreak(day),
                        cellHeight: cellHeight
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDay = day }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(height: gridHeight)

            Divider().overlay(Theme.border)

            // Day detail — simplified & workout-centric
            ScrollView {
                DayDetail(date: selectedDay)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
        .safeAreaInset(edge: .bottom) { if hasActiveWorkout { Color.clear.frame(height: 65) } }
    }

    // MARK: - Navigation helpers
    private var canGoForward: Bool {
        let cal = Calendar.current
        if let next = cal.date(byAdding: .month, value: 1, to: monthAnchor) {
            return next <= startOfCurrentMonth
        }
        return false
    }

    private func bump(_ delta: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        if delta > 0 {
            guard canGoForward else { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(); return }
            monthAnchor = next
        } else {
            monthAnchor = next
        }
        if let first = cal.dateInterval(of: .month, for: monthAnchor)?.start {
            selectedDay = first
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func jumpToToday() {
        monthAnchor = .now
        selectedDay = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Data helpers
    private func daysInMonth() -> [Date] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: monthAnchor) else { return [] }
        var days: [Date] = []
        var d = interval.start

        // pad first row
        let wd = Calendar.current.component(.weekday, from: d) - Calendar.current.firstWeekday
        let pad = wd < 0 ? wd + 7 : wd
        for i in stride(from: pad, to: 0, by: -1) {
            if let prev = Calendar.current.date(byAdding: .day, value: -i, to: d) { days.append(prev) }
        }
        // month days
        while d < interval.end {
            days.append(d)
            d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d
        }
        // pad last row
        while days.count % 7 != 0 {
            days.append(days.last!.addingTimeInterval(86_400))
        }
        return days
    }

    private func dayStat(for date: Date) -> DayStat {
        DayStat(
            date: date,
            workoutCount: store.workouts(on: date).count,
            runCount: store.runs(on: date).count
        )
    }
}

// MARK: - Header (no forward into the future)
private struct MonthHeader: View {
    @Binding var monthAnchor: Date
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onToday: () -> Void
    let streak: Int

    private var showingCurrentMonth: Bool {
        Calendar.current.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(monthAnchor.formatted(.dateTime.year().month(.wide)))
                    .font(.title3.bold())
                    .foregroundStyle(Theme.text)

                Spacer()

                HStack(spacing: 6) {
                    Button { onBack() } label: { Image(systemName: "chevron.left") }
                    Button { onForward() } label: { Image(systemName: "chevron.right") }
                        .opacity(canGoForward ? 1.0 : 0.35)
                        .disabled(!canGoForward)
                }
                .buttonStyle(.plain)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surface2, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))

                if !showingCurrentMonth {
                    Button("Today", action: onToday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 16)

            if streak > 0 {
                StreakBanner(streak: streak)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct StreakBanner: View {
    let streak: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, Theme.accent)
                .padding(8)
                .background(Theme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)-day streak")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("Don’t break the chain.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()

            ProgressView(value: min(Double(streak)/30.0, 1.0))
                .tint(Theme.accent)
                .frame(width: 80)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Weekday labels
private struct WeekdayRow: View {
    var body: some View {
        let sym = Calendar.current.shortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        let days = Array(sym[first..<sym.count] + sym[0..<first])

        HStack {
            ForEach(days, id: \.self) { d in
                Text(d.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Day cell
private struct DayCellV2: View {
    let date: Date
    let stats: DayStat
    let isSelected: Bool
    let inMonth: Bool
    let inActiveStreak: Bool
    let cellHeight: CGFloat

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(inActiveStreak ? Theme.accent.opacity(0.22) : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(borderColor, lineWidth: isSelected || inActiveStreak ? 2 : 1)
                    )

                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundStyle(.white)
            }
            .frame(height: cellHeight)

            // tiny markers
            HStack(spacing: 4) {
                if stats.workoutCount > 0 { Capsule().fill(Theme.accent).frame(width: 12, height: 4) }
                if stats.runCount > 0 { Capsule().fill(.white.opacity(0.75)).frame(width: 12, height: 4) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .opacity(inMonth ? 1.0 : 0.45)
        .overlay(alignment: .topTrailing) {
            if inActiveStreak && isToday {
                Image(systemName: "flame.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.black)
                    .padding(4)
                    .background(Theme.accent, in: Circle())
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var borderColor: Color {
        if isSelected { return Theme.accent }
        if isToday { return Theme.border }
        return Theme.border.opacity(0.6)
    }
}

// MARK: - Day Detail (simplified)
private struct DayDetail: View {
    @EnvironmentObject var store: WorkoutStore
    let date: Date

    private var workouts: [CompletedWorkout] { store.workouts(on: date) }
    private var runs: [Run] { store.runs(on: date) }

    // Aggregates (workouts only)
    private var workoutCount: Int { workouts.count }
    private var exerciseCount: Int {
        workouts.reduce(0) { $0 + $1.entries.count }
    }
    private var setCount: Int {
        workouts.reduce(0) { sum, w in sum + w.entries.reduce(0) { $0 + $1.sets.count } }
    }
    private var repCount: Int {
        workouts.reduce(0) { sum, w in
            sum + w.entries.reduce(0) { $0 + $1.sets.reduce(0) { $0 + max(0, $1.reps) } }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Daily Summary — workouts only
            DailySummaryCard(date: date, workoutCount: workoutCount, exerciseCount: exerciseCount, setCount: setCount, repCount: repCount)

            if workouts.isEmpty && runs.isEmpty {
                ContentUnavailableView("No activity", systemImage: "calendar")
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            } else {
                // Workouts list — EACH ROW = start time (compact, zero clutter)
                if !workouts.isEmpty {
                    VStack(spacing: 0) {
                        SectionHeader(title: "Workouts", count: workouts.count)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        Rectangle().fill(Theme.border).frame(height: 1)

                        ForEach(workouts, id: \.id) { w in
                            WorkoutRow(workout: w)
                            if w.id != workouts.last?.id {
                                Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }

                // Runs (kept minimal)
                if !runs.isEmpty {
                    VStack(spacing: 0) {
                        SectionHeader(title: "Runs", count: runs.count)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        Rectangle().fill(Theme.border).frame(height: 1)

                        ForEach(runs) { r in
                            HStack {
                                Text(timeOnly(r.date))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(String(format: "%.2f km", max(0, r.distanceKm)))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Theme.text)
                                Text("•")
                                    .foregroundStyle(Theme.secondary)
                                Text(hms(max(0, r.durationSec)))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)

                            if r.id != runs.last?.id {
                                Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Subviews
    private struct DailySummaryCard: View {
        let date: Date
        let workoutCount: Int
        let exerciseCount: Int
        let setCount: Int
        let repCount: Int

        private struct Tile: Identifiable, Equatable {
            let id = UUID()
            let title: String
            let value: String
        }

        private var tiles: [Tile] {
            [
                .init(title: "Workouts",  value: "\(workoutCount)"),
                .init(title: "Exercises", value: "\(exerciseCount)"),
                .init(title: "Sets",      value: "\(setCount)"),
                .init(title: "Reps",      value: "\(repCount)")
            ]
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(.headline).foregroundStyle(Theme.text)
                    Spacer()
                    if workoutCount > 0 {
                        Text("Daily summary")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }

                SummaryGrid(tiles: tiles)
                    .frame(height: 108)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }

        private struct SummaryGrid: View {
            let tiles: [Tile] // expects 4

            var body: some View {
                ZStack {
                    VStack(spacing: 0) { Spacer(); HLine(); Spacer() }
                    HStack(spacing: 0) { Spacer(); VLine(); Spacer() }

                    VStack(spacing: 0) {
                        HStack(spacing: 0) { cell(tiles[safe: 0]); VLine(); cell(tiles[safe: 1]) }
                        HLine()
                        HStack(spacing: 0) { cell(tiles[safe: 2]); VLine(); cell(tiles[safe: 3]) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .background(Theme.surface2.opacity(0.0))
            }

            private func cell(_ t: Tile?) -> some View {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t?.title ?? "—")
                        .font(.caption2).foregroundStyle(Theme.secondary)
                    Text(t?.value ?? "—")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.clear)
            }

            private struct VLine: View { var body: some View { Rectangle().fill(Theme.border).frame(width: 1) } }
            private struct HLine: View { var body: some View { Rectangle().fill(Theme.border).frame(height: 1) } }
        }
    }

    private struct SectionHeader: View {
        let title: String
        let count: Int
        var body: some View {
            HStack {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
            }
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
    }

    private struct WorkoutRow: View {
        let workout: CompletedWorkout

        var body: some View {
            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                HStack {
                    Label {
                        Text(timeOnly(workout.date))
                            .foregroundStyle(Theme.text)
                    } icon: {
                        Image(systemName: "dumbbell")
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.secondary)
                        .opacity(0.6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
