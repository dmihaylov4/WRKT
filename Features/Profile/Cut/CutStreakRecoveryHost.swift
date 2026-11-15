//
//  CutStreakRecoveryHost.swift
//  WRKT
//
//  StreakRecoverySheet's behaviour behind the Cut sheet: every button closes the sheet first,
//  then Join a challenge and Challenge a friend run the caller's closures.
//

import SwiftUI

struct CutStreakRecoveryHost: View {
    let brokenStreak: Int
    @Binding var isPresented: Bool
    var onJoinChallenge: () -> Void
    var onChallengeFriend: () -> Void

    var body: some View {
        CutStreakRecoveryView(
            model: CutStreakRecoveryLogic.model(brokenStreak: brokenStreak),
            actions: CutStreakRecoveryActions(
                joinChallenge: {
                    isPresented = false
                    onJoinChallenge()
                },
                challengeFriend: {
                    isPresented = false
                    onChallengeFriend()
                },
                later: { isPresented = false }
            )
        )
    }
}
