//
//  CutStreakRecoveryModel.swift
//  WRKT
//
//  What the Cut streak recovery sheet says after a weekly streak breaks: the title with the
//  streak's length and StreakRecoverySheet's sentence and actions.
//

import Foundation

struct CutStreakRecoveryModel: Equatable {
    var title: String
    var line = "The fastest way to rebuild: make the next streak public from the start."
}

enum CutStreakRecoveryLogic {
    static func model(brokenStreak: Int) -> CutStreakRecoveryModel {
        CutStreakRecoveryModel(title: "\(brokenStreak)-week streak ended")
    }
}
