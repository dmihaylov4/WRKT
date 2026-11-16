//
//  CutStreakRecoveryView.swift
//  WRKT
//
//  The streak recovery sheet in the Cut language: the ended streak as a modest condensed title,
//  one sentence, Join a challenge and Challenge a friend as choice rows. The round Close runs
//  the same Maybe later action. Sized to its content. Plain values and closures.
//

import SwiftUI

struct CutStreakRecoveryActions {
    var joinChallenge: () -> Void = {}
    var challengeFriend: () -> Void = {}
    var later: () -> Void = {}
}

struct CutStreakRecoveryView: View {
    let model: CutStreakRecoveryModel
    var actions = CutStreakRecoveryActions()

    var body: some View {
        CutSheet(model.title, kind: .choice, close: actions.later) {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.line).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                CutSheetInset {
                    CutSettingsLinkRow("Join a challenge", action: actions.joinChallenge)
                    CutHairline()
                    CutSettingsLinkRow("Challenge a friend", action: actions.challengeFriend)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 12).padding(.bottom, 24)
        }
    }
}
