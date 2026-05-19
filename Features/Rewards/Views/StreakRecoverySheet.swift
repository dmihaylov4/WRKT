//
//  StreakRecoverySheet.swift
//  WRKT
//

import SwiftUI

extension Notification.Name {
    static let navigateToCompeteTab = Notification.Name("navigateToCompeteTab")
    static let openBattleCreateSheet = Notification.Name("openBattleCreateSheet")
}

struct StreakRecoverySheet: View {
    let brokenStreak: Int
    @Binding var isPresented: Bool
    var onJoinChallenge: () -> Void
    var onChallengeFriend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DS.Semantic.border)
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("\(brokenStreak)-Week Streak Ended")
                        .font(.title2.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("The fastest way to rebuild: make the next streak public from the start.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                VStack(spacing: 12) {
                    Button {
                        isPresented = false
                        onJoinChallenge()
                    } label: {
                        Label("Join a Challenge", systemImage: "star.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        isPresented = false
                        onChallengeFriend()
                    } label: {
                        Label("Challenge a Friend", systemImage: "flag.2.crossed.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Maybe Later") {
                        isPresented = false
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .background(DS.Semantic.card)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
    }
}
