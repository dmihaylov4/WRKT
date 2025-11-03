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
        // Register Live Activities here
        RestTimerLiveActivity()

        // Future: Add static widgets here
        // WorkoutStatsWidget()
        // WeeklyProgressWidget()
    }
}
