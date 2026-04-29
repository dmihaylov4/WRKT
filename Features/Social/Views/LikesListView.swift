// LikesListView.swift
// Sheet showing who liked a specific post.

import SwiftUI
import Kingfisher

struct LikesListView: View {
    let postId: UUID
    let postRepository: PostRepository

    @State private var likers: [UserProfile] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Liked by")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsFont(.title3)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .background(DS.Semantic.border)

            if isLoading {
                Spacer()
                ProgressView()
                    .tint(DS.Semantic.brand)
                Spacer()
            } else if likers.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "heart")
                        .font(.system(size: 36))
                        .foregroundStyle(DS.Semantic.textSecondary)
                    Text("No likes yet")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(likers) { user in
                            LikerRow(user: user)

                            if user.id != likers.last?.id {
                                Divider()
                                    .padding(.leading, 72)
                                    .background(DS.Semantic.border)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color.black)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
        .task {
            await loadLikers()
        }
    }

    private func loadLikers() async {
        isLoading = true
        likers = (try? await postRepository.fetchPostLikes(postId: postId)) ?? []
        isLoading = false
    }
}

// MARK: - Liker Row

private struct LikerRow: View {
    let user: UserProfile

    var body: some View {
        HStack(spacing: 12) {
            // Chamfered avatar
            KFImage(URL(string: user.avatarUrl ?? ""))
                .placeholder {
                    ChamferedRectangleAlt(.small)
                        .fill(DS.Semantic.brandSoft)
                        .overlay(
                            Text(user.username.prefix(1).uppercased())
                                .dsFont(.subheadline, weight: .bold)
                                .foregroundStyle(DS.Semantic.brand)
                        )
                }
                .fade(duration: 0.2)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(ChamferedRectangleAlt(.small))

            // Name + username
            VStack(alignment: .leading, spacing: 2) {
                if let displayName = user.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                    Text("@\(user.username)")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                } else {
                    Text("@\(user.username)")
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
