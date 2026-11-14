import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in capture of the home screen widgets from fixture values. Runs only with
/// VOLIA_CAPTURE_WIDGETS=1 (pass TEST_RUNNER_VOLIA_CAPTURE_WIDGETS=1 to xcodebuild). Writes to
/// /private/tmp/volia-widgets, or to VOLIA_CAPTURE_DIR when set, one PNG per state:
///   widgets-<state>.png   weekly goal (small), Today (small) and Today and week (medium)
/// The widget container background is drawn by WidgetKit, so the board paints the same
/// background and the system corner radius behind each view.
@MainActor
struct HomeWidgetCaptureTests {
    private static let small = CGSize(width: 170, height: 170)
    private static let medium = CGSize(width: 364, height: 170)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WIDGETS"] == "1"))
    func captureWidgetStates() throws {
        let environment = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-widgets")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let saturday = calendar.date(byAdding: .day, value: 3, to: now)!
        let streak = HomeWidgetContent.Week(strengthDone: 2, strengthTarget: 4, cardioMinutes: 45,
                                            cardioTarget: 150, streakWeeks: 3)
        let met = HomeWidgetContent.Week(strengthDone: 4, strengthTarget: 4, cardioMinutes: 160,
                                         cardioTarget: 150, streakWeeks: 12)
        let rolledOver = HomeWidgetContent.Week(strengthDone: 0, strengthTarget: 4, cardioMinutes: 0,
                                                cardioTarget: 150, streakWeeks: nil)

        let states: [(String, HomeWidgetContent)] = [
            ("planned", .init(today: .planned(name: "Upper Body", exerciseCount: 5), week: streak)),
            ("planned-carried", .init(today: .planned(name: "Full Body Strength", exerciseCount: nil), week: rolledOver)),
            ("in-progress", .init(today: .inProgress(name: "Live workout"), week: streak)),
            ("long-name", .init(today: .planned(name: "Upper Body Hypertrophy Block", exerciseCount: 12), week: streak)),
            ("rest-day", .init(today: .restDay(next: .init(name: "Lower Body", date: tomorrow)), week: streak)),
            ("done-today", .init(today: .doneToday(next: .init(name: "Pull", date: saturday)), week: met)),
            ("no-plan", .init(today: .noPlan, week: nil)),
            ("empty", .empty),
        ]
        for (name, content) in states {
            try save(WidgetBoard(content: content, now: now), to: root.appendingPathComponent("widgets-\(name).png"))
        }
    }

    private func save(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        try #require(image.pngData()).write(to: url)
    }

    /// The three widgets on a home screen-like gray, at the iPhone Pro sizes.
    private struct WidgetBoard: View {
        let content: HomeWidgetContent
        let now: Date

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 24) {
                    tile(WeeklyGoalWidgetView(content: content), size: HomeWidgetCaptureTests.small, background: .black)
                    tile(TodayWidgetView(content: content, now: now), size: HomeWidgetCaptureTests.small,
                         background: HomeWidgetLogic.fieldIsLime(content.today) ? HomeWidgetStyle.lime : HomeWidgetStyle.darkField)
                }
                tile(TodayAndWeekWidgetView(content: content, now: now), size: HomeWidgetCaptureTests.medium, background: .black)
            }
            .padding(24)
            .background(Color(red: 0.24, green: 0.27, blue: 0.33))
        }

        private func tile(_ view: some View, size: CGSize, background: Color) -> some View {
            view
                .frame(width: size.width, height: size.height)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
