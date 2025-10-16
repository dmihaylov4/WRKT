//  CalendarMonthView (revised).swift
//  WRKT
//
//  A brighter, streak-first calendar. Only navigates to past months.
//  Shows a concise daily summary and clearer activity cards.
//

import SwiftUI
import Foundation

// MARK: - Theme (kept consistent with app)
private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = Color(hex: "#F4E409")
}

private struct SetSummary: Identifiable, Equatable {
    let id = UUID()
    let reps: Int
    let weightKg: Double
}

private struct ExerciseRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let sets: Int
    let reps: Int
    let topKg: Double
    let volumeKg: Double
    let breakdown: [SetSummary]
}

private struct ExercisePeekCard: View {
    let row: ExerciseRow
    let unit: WeightUnit
    let onClose: () -> Void

    private var topDisplay: String {
        let v = unit == .kg ? row.topKg : row.topKg * 2.20462
        return v > 0 ? String(format: unit == .kg ? "%.0f kg" : "%.0f lb", v.rounded()) : "—"
    }
    private var volDisplay: String {
        let v = unit == .kg ? row.volumeKg : row.volumeKg * 2.20462
        return v > 0 ? String(format: unit == .kg ? "%.0f kg" : "%.0f lb", v.rounded()) : "—"
    }
    private func wDisplay(_ kg: Double) -> String {
        let v = unit == .kg ? kg : kg * 2.20462
        return v > 0 ? String(format: unit == .kg ? "%.0f kg" : "%.0f lb", v.rounded()) : "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            PeekTiles(
                tiles: [
                    .init(title: "Sets",   value: "\(row.sets)"),
                    .init(title: "Reps",   value: "\(row.reps)"),
                    .init(title: "Top",    value: topDisplay),
                    .init(title: "Volume", value: volDisplay),
                ]
            )
            .frame(height: 96)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(row.breakdown.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accent, in: Capsule())
                }

                ForEach(Array(row.breakdown.enumerated()), id: \.offset) { idx, s in
                    HStack {
                        Text("#\(idx + 1)")
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 34, alignment: .leading)

                        Spacer(minLength: 0)

                        Text("\(s.reps)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .frame(width: 54, alignment: .trailing)

                        Text(wDisplay(s.weightKg))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    if idx < row.breakdown.count - 1 {
                        Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(radius: 22, y: 6)
    }
}

private struct PeekTiles: View {
    struct Tile: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let value: String
    }
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
    }

    private func cell(_ t: Tile?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t?.title ?? "—").font(.caption2).foregroundStyle(Theme.secondary)
            Text(t?.value ?? "—")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private struct VLine: View { var body: some View { Rectangle().fill(Theme.border).frame(width: 1) } }
    private struct HLine: View { var body: some View { Rectangle().fill(Theme.border).frame(height: 1) } }
}


struct CalendarMonthView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var peek: ExerciseRow? = nil          // NEW
    @State private var scrimInteractive = false
    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date = .now

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let cellHeight: CGFloat = 44
    
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue   // NEW
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    // Convenience
    private var hasActiveWorkout: Bool {
        guard let c = store.currentWorkout else { return false }
        return !c.entries.isEmpty
    }
    private var startOfCurrentMonth: Date { Calendar.current.dateInterval(of: .month, for: .now)!.start }
    private var isShowingCurrentMonth: Bool { Calendar.current.isDate(monthAnchor, equalTo: .now, toGranularity: .month) }

    // Streak helpers
    private var streakLength: Int { max(store.streak(), 0) }
    private func hasActivity(on d: Date) -> Bool {
        !store.workouts(on: d).isEmpty || !store.runs(on: d).isEmpty
    }
    private func isInActiveStreak(_ d: Date) -> Bool {
        guard streakLength > 0 else { return false }
        // d must be within [today - (streakLength-1), today] and have activity
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let windowStart = cal.date(byAdding: .day, value: -(streakLength - 1), to: today) else { return false }
        let startOfD = cal.startOfDay(for: d)
        let inWindow = (startOfD >= windowStart) && (startOfD <= today)
        return inWindow && hasActivity(on: d)
    }

    var body: some View {
        ZStack{
            VStack(spacing: 14) {
                MonthHeader(
                    monthAnchor: $monthAnchor,
                    canGoForward: canGoForward,
                    onBack: { bump(-1) },
                    onForward: { bump(+1) },
                    onToday: { jumpToToday() },
                    streak: store.streak()
                )
                .padding(.top, 12)
                
                WeekdayRow().padding(.horizontal, 16)
                
                // --- MONTH GRID
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
                Spacer(minLength: 16)
                Divider().overlay(Theme.border)
                
                // --- DAY DETAIL
                ScrollView {
                                   DayDetail(date: selectedDay, onSelect: { row in     // CHANGED
                                       withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                           peek = row
                                       }
                                       scrimInteractive = false
                                       DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scrimInteractive = true }
                                   })
                                   .padding(.horizontal, 16)
                                   .padding(.bottom, 6)
                               }
                               .frame(maxHeight: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.accent)
            .safeAreaInset(edge: .bottom) { if hasActiveWorkout { Color.clear.frame(height: 65) } }
            
            if let sel = peek {
                           ZStack(alignment: .bottom) {
                               Color.black.opacity(0.35)
                                   .ignoresSafeArea()
                                   .allowsHitTesting(scrimInteractive)
                                   .onTapGesture { withAnimation(.spring()) { peek = nil } }

                               ExercisePeekCard(row: sel, unit: unit) {           // CHANGED
                                                      withAnimation(.spring()) { peek = nil }
                                                  }
                               .padding(.horizontal, 16)
                               .padding(.bottom, 16)
                               .transition(.move(edge: .bottom).combined(with: .opacity))
                           }
                           .frame(maxWidth: .infinity, maxHeight: .infinity)
                           .allowsHitTesting(true)
                           .zIndex(999)
                       }
                   }
                   .animation(.spring(response: 0.35, dampingFraction: 0.88), value: peek != nil) // NEW
        
    }

    // MARK: - Nav helpers
    private var canGoForward: Bool {
        // disallow moving beyond current month
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
            // forward
            guard canGoForward else { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(); return }
            monthAnchor = next
        } else {
            monthAnchor = next
        }
        // keep selected day within shown month (pick first day of month)
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

            // subtle progress hint across a 30-day window
            ProgressView(value: min(Double(streak)/30.0, 1.0))
                .tint(Theme.accent)
                .frame(width: 80)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// Weekday labels
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

// MARK: - Day cell (brighter, with streak emphasis)
struct DayCellV2: View {
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
                // Base
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(inActiveStreak ? Theme.accent.opacity(0.22) : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(borderColor, lineWidth: isSelected || inActiveStreak ? 2 : 1)
                    )

                // Date label
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundStyle(.white)
            }
            .frame(height: cellHeight)

            // Activity markers (small and bright)
            HStack(spacing: 4) {
                if stats.workoutCount > 0 { Capsule().fill(Theme.accent).frame(width: 12, height: 4) }
                if stats.runCount > 0 { Capsule().fill(.white.opacity(0.75)).frame(width: 12, height: 4) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .opacity(inMonth ? 1.0 : 0.45)
        .overlay(alignment: .topTrailing) {
            // Tiny flame badge only on today when it’s part of the streak
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



// MARK: - Day detail (clear structure)
private struct DayDetail: View {
    @EnvironmentObject var store: WorkoutStore
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    @State private var scrimInteractive = false
    let date: Date
    @State private var selectedRow: ExerciseRow? = nil
    private var workouts: [CompletedWorkout] { store.workouts(on: date) }
    private var runs: [Run] { store.runs(on: date) }
    
    let onSelect: (ExerciseRow) -> Void        // NEW


    // Flatten workout entries into table rows
    private var rows: [ExerciseRow] {
        var result: [ExerciseRow] = []
        for w in workouts {
            for e in w.entries {
                let sets = e.sets
                let setsCount = sets.count
                let repsTotal = sets.reduce(0) { $0 + max(0, $1.reps) }
                let topKg = sets.map { max(0, $0.weight) }.max() ?? 0
                var volume: Double = 0
                var brk: [SetSummary] = []
                for s in sets {
                    let r = max(0, s.reps)
                    let kg = max(0, s.weight)
                    volume += Double(r) * kg
                    brk.append(SetSummary(reps: r, weightKg: kg))
                }
                result.append(
                    ExerciseRow(
                        id: e.id,
                        name: e.exerciseName,
                        sets: setsCount,
                        reps: repsTotal,
                        topKg: topKg,
                        volumeKg: volume,
                        breakdown: brk
                    )
                )
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top summary
            DailySummaryCard(date: date, workouts: workouts, runs: runs)

            if workouts.isEmpty && runs.isEmpty {
                ContentUnavailableView("No activity", systemImage: "calendar")
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            } else {
                if !rows.isEmpty {
                    // Workouts table
                    VStack(spacing: 0) {
                        TableHeader()
                        Divider().overlay(Theme.border)
                        ForEach(rows) { r in
                            TableRow(row: r, unit: unit, onSelect: onSelect) // CHANGED
                            Divider().overlay(Theme.border.opacity(0.6))
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }

                if !runs.isEmpty {
                    VStack(spacing: 0) {
                        // header row
                        HStack {
                            Text("Runs").font(.headline).foregroundStyle(Theme.text)
                            Spacer()
                            Text("\(runs.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.accent, in: Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        Text("Tap a row to see exercise details")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                            .padding(.top, 6)
                        Rectangle().fill(Theme.border).frame(height: 1)

                        // rows
                        ForEach(runs) { r in
                            HStack {
                                Text(r.date.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(String(format: "%.2f km", r.distanceKm))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Theme.text)
                                Text("•")
                                    .foregroundStyle(Theme.secondary)
                                Text(fmt(sec: r.durationSec))
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
                    .padding(.top, 6)
                   
                }
                
            }
        
            
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            if let sel = selectedRow {
                ZStack(alignment: .bottom) {
                    // SCRIM
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .allowsHitTesting(scrimInteractive)
                        .onTapGesture { withAnimation(.spring()) { selectedRow = nil } }

                    // CARD
                    ExercisePeekCard(row: sel, unit: unit) { withAnimation(.spring()) { selectedRow = nil } }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .onAppear {
                    scrimInteractive = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scrimInteractive = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)    // <-- claim the whole screen
                .allowsHitTesting(true)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: selectedRow != nil)
        .zIndex(selectedRow == nil ? 0 : 999)                        // <-- keep it on top
    }

    // MARK: - Table types & views
 
  

    private struct TableHeader: View {
        var body: some View {
            HStack(spacing: 8) {
                // No name column — four metrics only:
                Text("Sets").frame(width: 48, alignment: .trailing)
                Text("Reps").frame(width: 54, alignment: .trailing)
                Text("Weight").frame(width: 72, alignment: .trailing)
                Text("Volume").frame(width: 84, alignment: .trailing)
                Spacer(minLength: 0) // keep row fully tappable
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private struct TableRow: View {
        let row: ExerciseRow
        let unit: WeightUnit
        let onSelect: (ExerciseRow) -> Void

        private var topDisplay: String {
            let v = unit == .kg ? row.topKg : row.topKg * 2.20462
            return v > 0 ? String(format: unit == .kg ? "%.0f kg" : "%.0f lb", v.rounded()) : "—"
        }
        private var volDisplay: String {
            let v = unit == .kg ? row.volumeKg : row.volumeKg * 2.20462
            return v > 0 ? String(format: unit == .kg ? "%.0f kg" : "%.0f lb", v.rounded()) : "—"
        }

        var body: some View {
            HStack(spacing: 8) {
                Text("\(row.sets)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .frame(width: 48, alignment: .trailing)

                Text("\(row.reps)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .frame(width: 54, alignment: .trailing)

                Text(topDisplay)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .frame(width: 72, alignment: .trailing)

                Text(volDisplay)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .frame(width: 84, alignment: .trailing)

                Spacer(minLength: 0)

                // subtle affordance
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface.opacity(0.0001))
            .contentShape(Rectangle())
            .onTapGesture { onSelect(row) }
        }
    }

    private func fmt(sec: Int) -> String {
        String(format: "%02d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
    }
}

private struct DailySummaryCard: View {
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    let date: Date
    let workouts: [CompletedWorkout]
    
    let runs: [Run]

    // MARK: Aggregates
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
    private var volumeKg: Double {
        var total: Double = 0
        for w in workouts {
            for e in w.entries {
                for s in e.sets {
                    total += Double(max(0, s.reps)) * max(0, s.weight) // <- weight, not weightKg
                }
            }
        }
        return total
    }
    private var volumeDisplay: String {
        let v = unit == .kg ? volumeKg : volumeKg * 2.20462
        return String(format: unit == .kg ? "%.0f kg" : "%.0f lb", v.rounded())
    }
    private var runDistanceKm: Double { runs.reduce(0) { $0 + max(0, $1.distanceKm) } }
    private var runTimeSec: Int { runs.reduce(0) { $0 + max(0, $1.durationSec) } }

    // Choose exactly 4 tiles; if no workouts, show run tile in the last slot
    // Choose exactly 4 tiles; if no workouts, show run tile in the last slot
    private var tiles: [Tile] {
        let t1 = Tile(title: "Exercises", value: "\(exerciseCount)")
        let t2 = Tile(title: "Sets", value: "\(setCount)")
        let t3 = Tile(title: "Reps", value: "\(repCount)")

        let t4: Tile = {
            if exerciseCount > 0 {
                return Tile(title: "Volume", value: volumeDisplay)
            } else if runDistanceKm > 0 || runTimeSec > 0 {
                let dist = String(format: "%.2f", runDistanceKm)
                let runStr = "\(dist) km • \(fmt(sec: runTimeSec))"
                return Tile(title: "Run", value: runStr)
            } else {
                return Tile(title: "—", value: "—")
            }
        }()

        return [t1, t2, t3, t4]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.headline).foregroundStyle(Theme.text)
                Spacer()
                if !workouts.isEmpty || !runs.isEmpty {
                    Text("Daily summary")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }

            // 2×2 grid inside a single card with separators
            SummaryGrid(tiles: tiles)
                .frame(height: 108)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func fmt(sec: Int) -> String {
        String(format: "%02d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
    }

    // MARK: - Grid

    private struct Tile: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let value: String
    }

    private struct SummaryGrid: View {
        let tiles: [Tile] // expects 4

        var body: some View {
            ZStack {
                // separators
                VStack(spacing: 0) {
                    Spacer()
                    HLine()
                    Spacer()
                }
                HStack(spacing: 0) {
                    Spacer()
                    VLine()
                    Spacer()
                }

                // 2×2 content
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cell(tiles[safe: 0])
                        VLine()
                        cell(tiles[safe: 1])
                    }
                    HLine()
                    HStack(spacing: 0) {
                        cell(tiles[safe: 2])
                        VLine()
                        cell(tiles[safe: 3])
                    }
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

private extension Array {
    subscript(safe idx: Int) -> Element? { indices.contains(idx) ? self[idx] : nil }
}

private struct StatChip: View {
    let icon: String
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(Theme.secondary)
                Text(value).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.accent, in: Capsule())
        }
        .foregroundStyle(Theme.text)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}

private struct WorkoutCard2: View {
    let workout: CompletedWorkout
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Workout", systemImage: "dumbbell").labelStyle(.titleAndIcon)
                Spacer()
                Text(workout.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(Theme.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(workout.entries.prefix(5)) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(e.exerciseName).font(.subheadline)
                        Spacer()
                        let repStr = e.sets.map { String($0.reps) }.joined(separator: ", ")
                        Text(repStr)
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                if workout.entries.count > 5 {
                    Text("+\(workout.entries.count - 5) more…")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

private struct RunCard2: View {
    let run: Run
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Run", systemImage: "figure.run")
            Spacer()
            Text("\(run.distanceKm, specifier: "%.2f") km • \(format(sec: run.durationSec))")
        }
        .font(.subheadline)
        .foregroundStyle(Theme.text)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func format(sec: Int) -> String {
        String(format: "%02d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
    }
}

// MARK: - Supporting types

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
