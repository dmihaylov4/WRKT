//
//  CutStreakRecoveryView.swift
//  WRKT
//
//  The streak recovery sheet in the Cut language: the ended streak as a modest condensed title,
//  one sentence, Join a challenge and Challenge a friend as hairline rows, Maybe later as plain
//  secondary text. Sized to its content. Plain values and closures.
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

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CutHeroText(CutHeroText.balancedLines(model.title), hero: .xs, minimumScaleFactor: 0.6)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text(model.line)
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                CutHairlineList {
                    CutSettingsLinkRow("Join a challenge", action: actions.joinChallenge)
                    CutSettingsLinkRow("Challenge a friend", action: actions.challengeFriend)
                }
                .padding(.top, 20)
                Button(action: actions.later) {
                    Text("Maybe later")
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: DS.Cut.Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 32)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .presentationDetents([.height(max(contentHeight, 300))])
        .presentationBackground(DS.Cut.Colors.background)
        .presentationDragIndicator(.visible)
    }
}
