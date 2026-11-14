//
//  WRKTWidgetsBundle.swift
//  WRKTWidgets
//
//  Widget Extension Bundle
//  Registers all widgets and Live Activities
//

import WidgetKit
import SwiftUI

@main
struct WRKTWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Live Activities
        RestTimerLiveActivity()

        // Home screen widgets
        WeeklyGoalWidget()
        TodayWidget()
        TodayAndWeekWidget()
    }
}
