//
//  HomeWidgets.swift
//  WRKTWidgets
//
//  Home screen widgets: Weekly goal (small), Today (small), Today and week (medium).
//  The provider reads only the snapshot the app writes to the app group container and
//  schedules an entry at the next midnight, so "Today" never outlives its day.
//

import SwiftUI
import WidgetKit

struct HomeWidgetEntry: TimelineEntry {
    let date: Date
    let content: HomeWidgetContent
}

struct HomeWidgetProvider: TimelineProvider {
    var store = HomeWidgetSnapshotStore()

    func placeholder(in context: Context) -> HomeWidgetEntry {
        HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.planned)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeWidgetEntry) -> Void) {
        let now = Date.now
        let snapshot = store.read()
        // The gallery shows the design until the app has written real values.
        let content = snapshot == nil && context.isPreview
            ? HomeWidgetPreviewData.planned
            : HomeWidgetLogic.content(for: snapshot, now: now)
        completion(HomeWidgetEntry(date: now, content: content))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
        let now = Date.now
        let snapshot = store.read()
        let entries = HomeWidgetLogic.entryDates(now: now, snapshot: snapshot).map { date in
            HomeWidgetEntry(date: date, content: HomeWidgetLogic.content(for: snapshot, now: date))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetShared.Kind.weeklyGoal, provider: HomeWidgetProvider()) { entry in
            WeeklyGoalWidgetView(content: entry.content)
        }
        .configurationDisplayName("Weekly goal")
        .description("Strength sessions and cardio minutes against your weekly goal.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetShared.Kind.today, provider: HomeWidgetProvider()) { entry in
            TodayWidgetView(content: entry.content, now: entry.date)
        }
        .configurationDisplayName("Today")
        .description("Today's planned session.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct TodayAndWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetShared.Kind.todayAndWeek, provider: HomeWidgetProvider()) { entry in
            TodayAndWeekWidgetView(content: entry.content, now: entry.date)
        }
        .configurationDisplayName("Today and week")
        .description("Today's session with your weekly goal and streak.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

enum HomeWidgetPreviewData {
    static let week = HomeWidgetContent.Week(strengthDone: 2, strengthTarget: 3,
                                             cardioMinutes: 143, cardioTarget: 183, streakWeeks: 6)
    static let next = HomeWidgetSnapshot.Session(name: "Lower Body", date: .now.addingTimeInterval(86_400))

    static let planned = HomeWidgetContent(today: .planned(name: "Upper Body", exerciseCount: 6), week: week)
    static let inProgress = HomeWidgetContent(today: .inProgress(name: "Upper Body"), week: week)
    static let restDay = HomeWidgetContent(today: .restDay(next: next), week: week)
    static let doneToday = HomeWidgetContent(today: .doneToday(next: next), week: week)
    static let noPlan = HomeWidgetContent(today: .noPlan, week: week)
    static let unknown = HomeWidgetContent(today: .unknown, week: nil)
    static let freshWeek = HomeWidgetContent(
        today: .planned(name: "Push", exerciseCount: nil),
        week: .init(strengthDone: 0, strengthTarget: 3, cardioMinutes: 0, cardioTarget: 150, streakWeeks: nil)
    )

    static let all: [HomeWidgetContent] = [planned, inProgress, restDay, doneToday, noPlan, unknown, freshWeek]
}

#Preview("Weekly goal", as: .systemSmall) {
    WeeklyGoalWidget()
} timeline: {
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.planned)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.freshWeek)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.unknown)
}

#Preview("Today", as: .systemSmall) {
    TodayWidget()
} timeline: {
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.planned)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.inProgress)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.restDay)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.doneToday)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.noPlan)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.unknown)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.freshWeek)
}

#Preview("Today and week", as: .systemMedium) {
    TodayAndWeekWidget()
} timeline: {
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.planned)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.inProgress)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.restDay)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.doneToday)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.noPlan)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.unknown)
    HomeWidgetEntry(date: .now, content: HomeWidgetPreviewData.freshWeek)
}
