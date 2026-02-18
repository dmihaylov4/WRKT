//
//  VirtualRunInviteBanner.swift
//  WRKT
//
//  Banner shown when receiving a virtual run invite
//

import SwiftUI
import Kingfisher

struct VirtualRunInviteBanner: View {
    let invite: VirtualRun
    let inviterProfile: UserProfile
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var isResponding = false

    var body: some View {
        HStack(spacing: 12) {
            // Inviter avatar
            if let urlString = inviterProfile.avatarUrl,
               let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(runBadge, alignment: .bottomTrailing)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.gray)
                    }
                    .overlay(runBadge, alignment: .bottomTrailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(inviterProfile.displayName ?? inviterProfile.username) wants to run!")
                    .font(.subheadline.bold())

                Text("Virtual run invitation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isResponding {
                ProgressView()
            } else {
                HStack(spacing: 8) {
                    Button {
                        isResponding = true
                        onDecline()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Circle())
                    }

                    Button {
                        isResponding = true
                        onAccept()
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                            .padding(8)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal)
    }

    private var runBadge: some View {
        Image(systemName: "figure.run")
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(4)
            .background(Color.blue)
            .clipShape(Circle())
    }
}
