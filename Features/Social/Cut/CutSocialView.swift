//
//  CutSocialView.swift
//  WRKT
//
//  The Social tab in the Cut language: a one-row header, underline tabs for Feed, Compete and
//  Friends, the feed as posts on the surface separated by hairlines, and the Friends pane as
//  hairline rows. Takes plain values and closures, so every state renders without the app's
//  services (see CutSocialHost for live data).
//

import SwiftUI
import Kingfisher

// MARK: - Shell

/// What the header and tabs do. Every closure calls an existing flow.
struct CutSocialShellActions {
    var select: (SocialView.SocialSection) -> Void = { _ in }
    var openProfile: () -> Void = {}
    var openActivity: () -> Void = {}
    var createPost: () -> Void = {}
    var startBattle: () -> Void = {}
}

/// Header and tabs above the selected pane. The pane scrolls on its own below them.
struct CutSocialShell<Pane: View>: View {
    let header: CutSocialHeaderModel
    let section: SocialView.SocialSection
    var actions = CutSocialShellActions()
    @ViewBuilder var pane: () -> Pane

    var body: some View {
        VStack(spacing: 0) {
            CutTabHeader("Social") {
                if header.showsProfile {
                    Button(action: actions.openProfile) {
                        CutSocialAvatar(initials: header.initials ?? "", url: header.avatarURL, size: DS.Cut.Metrics.headerIconButton, fallbackSymbol: "person")
                    }
                    .accessibilityLabel(Text("Open profile"))
                }
                Button("Activity", systemImage: "bell", action: actions.openActivity)
                    .overlay(alignment: .topTrailing) {
                        if let badge = CutSocialLogic.badge(header.notifications) {
                            CutSocialBadge(text: badge).offset(x: 6, y: -6)
                        }
                    }
                    .accessibilityValue(Text(header.notifications > 0 ? "\(header.notifications) unread" : ""))
                Menu {
                    Button("Create post", systemImage: "square.and.pencil", action: actions.createPost)
                    Button("Start battle", systemImage: "bolt", action: actions.startBattle)
                } label: {
                    Label("New", systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(CutIconButtonStyle(tone: .lime))
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)

            CutSocialTabs(section: section, friendRequests: header.friendRequests, select: actions.select)
                .padding(.top, 14)

            pane()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}

/// Underline tabs for Feed, Compete and Friends, with the request count beside Friends.
private struct CutSocialTabs: View {
    let section: SocialView.SocialSection
    let friendRequests: Int
    let select: (SocialView.SocialSection) -> Void

    var body: some View {
        CutUnderlineTabs(
            [SocialView.SocialSection.feed, .compete, .friends],
            selection: section,
            title: \.rawValue,
            badge: { $0 == .friends ? CutSocialLogic.badge(friendRequests) : nil },
            accessibilityLabel: { $0 == .friends && friendRequests > 0 ? "Friends, \(friendRequests) requests" : $0.rawValue },
            select: select
        )
    }
}

// MARK: - Feed

/// What the feed's controls do. Ids are post ids unless named otherwise.
struct CutSocialFeedActions {
    var refresh: () async -> Void = {}
    var retry: () -> Void = {}
    var loadNewPosts: () -> Void = {}
    var sync: () -> Void = {}
    var dismissError: () -> Void = {}
    var findFriends: () -> Void = {}
    var openArena: (CutSocialArenaItem.Target) -> Void = { _ in }
    var rowAppeared: (UUID) -> Void = { _ in }
    var like: (UUID) -> Void = { _ in }
    var openPost: (UUID) -> Void = { _ in }
    /// A user id: the author or the partner.
    var openProfile: (UUID) -> Void = { _ in }
    var perform: (CutSocialPostRow.Action, UUID) -> Void = { _, _ in }
}

struct CutSocialFeedView<Media: View>: View {
    let model: CutSocialFeedModel
    var actions = CutSocialFeedActions()
    /// Photos and route maps under a post's stats (resolved by the host).
    @ViewBuilder var media: (CutSocialPostRow) -> Media

    @State private var pending: PendingConfirmation?

    private struct PendingConfirmation: Identifiable {
        let action: CutSocialPostRow.Action
        let postId: UUID
        var id: String { "\(action)-\(postId)" }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let queued = model.offlineQueue {
                    offlineRow(queued: queued)
                }
                if let message = model.inlineError {
                    inlineErrorRow(message)
                }
                content
            }
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .scrollIndicators(.hidden)
        .refreshable { await actions.refresh() }
        .alert(item: $pending) { pending in
            Alert(
                title: Text(confirmationTitle(pending.action)),
                message: Text(confirmationMessage(pending.action)),
                primaryButton: .destructive(Text(confirmationButton(pending.action))) {
                    actions.perform(pending.action, pending.postId)
                },
                secondaryButton: .cancel()
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .loading:
            ForEach(0..<3, id: \.self) { _ in CutSocialSkeletonPost() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Loading posts"))
        case let .failed(title, message, canRetry):
            CutSocialMessage(title: title, line: message, button: canRetry ? "Try again" : nil, action: actions.retry)
        case .empty:
            CutSocialMessage(title: "No posts yet", line: "Add friends to see their workouts here.",
                             button: "Find friends", action: actions.findFriends)
        case let .posts(rows):
            if model.newPosts > 0 {
                Button {
                    Haptics.light()
                    actions.loadNewPosts()
                } label: {
                    Label(CutSocialLogic.newPostsLabel(model.newPosts), systemImage: "arrow.up")
                }
                .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 16)
            }
            if !model.arena.isEmpty {
                CutSocialArenaStrip(items: model.arena, open: actions.openArena)
                    .padding(.top, 16)
            }
            ForEach(rows) { row in
                CutSocialPostView(row: row, actions: actions, confirm: { action in
                    pending = PendingConfirmation(action: action, postId: row.id)
                }) {
                    media(row)
                }
                .onAppear { actions.rowAppeared(row.id) }
            }
            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            HStack(spacing: 10) {
                ProgressView().tint(DS.Cut.Colors.textSecondary)
                Text("Loading more").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if model.reachedEnd {
            Text("You're all caught up")
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    private func offlineRow(queued: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're offline").cutFont(.title).foregroundStyle(DS.Cut.Colors.textPrimary)
                    Text(CutSocialLogic.offlineLine(queued: queued)).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                Spacer(minLength: 8)
                if queued > 0 {
                    Button("Sync", action: actions.sync)
                        .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            CutHairline()
        }
    }

    private func inlineErrorRow(_ message: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(message)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Retry", action: actions.retry)
                    .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                Button("Dismiss", systemImage: "xmark", action: actions.dismissError)
                    .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: DS.Cut.Metrics.minTouchTarget))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            CutHairline()
        }
    }

    private func confirmationTitle(_ action: CutSocialPostRow.Action) -> String {
        switch action {
        case .delete: "Delete post"
        case .removeMe: "Remove me"
        default: "Report post"
        }
    }

    private func confirmationMessage(_ action: CutSocialPostRow.Action) -> String {
        switch action {
        case .delete: "This post and its comments are deleted. This cannot be undone."
        case .removeMe: "This post will no longer appear as one you shared together."
        default: "Report this post for inappropriate content? Our team will review it."
        }
    }

    private func confirmationButton(_ action: CutSocialPostRow.Action) -> String {
        switch action {
        case .delete: "Delete"
        case .removeMe: "Remove"
        default: "Report"
        }
    }
}

extension CutSocialFeedView where Media == EmptyView {
    init(model: CutSocialFeedModel, actions: CutSocialFeedActions = CutSocialFeedActions()) {
        self.init(model: model, actions: actions) { _ in EmptyView() }
    }
}

// MARK: - Post

private struct CutSocialPostView<Media: View>: View {
    let row: CutSocialPostRow
    let actions: CutSocialFeedActions
    let confirm: (CutSocialPostRow.Action) -> Void
    @ViewBuilder var media: () -> Media

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            VStack(alignment: .leading, spacing: 0) {
                if let caption = row.caption {
                    Text(caption)
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                Text(row.title)
                    .cutHero(.xs, lines: 2, minimumScaleFactor: 0.6)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                if !row.stats.isEmpty {
                    CutSocialStatColumns(stats: row.stats)
                        .padding(.top, 10)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.light()
                actions.openPost(row.id)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.openPost(row.id) }

            if row.showsMedia {
                media()
                    .padding(.top, 14)
            }
            actionRow
                .padding(.top, 16)
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { CutHairline() }
    }

    private var head: some View {
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                Button { actions.openProfile(row.author.id) } label: {
                    CutSocialAvatar(initials: row.author.initials, url: row.author.avatarURL, size: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open \(row.author.name)'s profile"))
                if let partner = row.partner {
                    Button { actions.openProfile(partner.id) } label: {
                        CutSocialAvatar(initials: partner.initials, url: partner.avatarURL, size: 44)
                            .overlay(Circle().strokeBorder(DS.Cut.Colors.background, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Open \(partner.name)'s profile"))
                }
            }
            Button { actions.openPost(row.id) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.names)
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .lineLimit(2)
                    Text(row.timeLine)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            menu
        }
    }

    private var menu: some View {
        Menu {
            ForEach(row.menu, id: \.self) { action in
                Button(CutSocialLogic.menuLabel(action), systemImage: icon(action),
                       role: CutSocialLogic.isDestructive(action) ? .destructive : nil) {
                    switch action {
                    case .delete, .removeMe, .report: confirm(action)
                    case .edit, .likes: actions.perform(action, row.id)
                    }
                }
            }
            ShareLink(item: CutSocialLogic.shareText) {
                Label("Share post", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More"))
    }

    private func icon(_ action: CutSocialPostRow.Action) -> String {
        switch action {
        case .edit: "pencil"
        case .delete: "trash"
        case .removeMe: "person.crop.circle.badge.xmark"
        case .likes: "heart"
        case .report: "exclamationmark.triangle"
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                actions.like(row.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: row.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(row.isLiked ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                    if row.likes > 0 { Text("\(row.likes)").monospacedDigit() }
                }
            }
            .accessibilityLabel(Text(CutSocialLogic.likeAccessibility(likes: row.likes, isLiked: row.isLiked)))
            Button {
                Haptics.light()
                actions.openPost(row.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left")
                    if row.comments > 0 { Text("\(row.comments)").monospacedDigit() }
                }
            }
            .accessibilityLabel(Text(CutSocialLogic.commentAccessibility(row.comments)))
            ShareLink(item: CutSocialLogic.shareText) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("Share"))
        }
        .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
    }
}

/// The post's stats as the shared Cut stat columns.
private struct CutSocialStatColumns: View {
    let stats: [CutSocialStat]

    var body: some View {
        CutStatColumns(stats.map { CutStatColumn(value: $0.value, label: $0.label, isHighlighted: $0.isHighlighted) })
    }
}

// MARK: - Arena

/// Active battles and challenges as one hairline strip of columns.
private struct CutSocialArenaStrip: View {
    let items: [CutSocialArenaItem]
    let open: (CutSocialArenaItem.Target) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CutHairline()
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle().fill(DS.Cut.Colors.hairline).frame(width: DS.Cut.Metrics.hairline)
                        }
                        Button { open(item.target) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.label)
                                    .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                                    .foregroundStyle(item.isLeading ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                                    .lineLimit(1)
                                Text(item.value)
                                    .cutNumeral(.medium)
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                CutSocialSplitBar(fraction: item.fraction)
                                    .padding(.top, 4)
                            }
                            .frame(width: 168, alignment: .leading)
                            .padding(.horizontal, DS.Cut.Metrics.gutter)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollIndicators(.hidden)
            CutHairline()
        }
    }
}

/// A slanted bar: lime for `fraction`, the rest as the empty track.
private struct CutSocialSplitBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = DS.Cut.clampedFraction(fraction)
            let gap: CGFloat = 4
            let lead = max(0, (proxy.size.width - gap) * clamped)
            HStack(spacing: gap) {
                if lead > 0 {
                    SlantedSegmentShape().fill(DS.Cut.Colors.lime).frame(width: lead)
                }
                SlantedSegmentShape().fill(DS.Cut.Colors.segmentTrack)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Friends

struct CutSocialFriendsActions {
    var refresh: () async -> Void = {}
    var openRequests: () -> Void = {}
    var openFriend: (UUID) -> Void = { _ in }
    var openFriends: () -> Void = {}
    var findFriends: () -> Void = {}
}

/// The Friends pane: requests, who trained in the last day, then My friends and Find friends.
struct CutSocialFriendsView: View {
    let model: CutSocialFriendsModel
    var actions = CutSocialFriendsActions()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: actions.openRequests) {
                    CutHairlineRow("Friend requests", value: CutSocialLogic.badge(model.requests),
                                   valueTone: .lime, showsChevron: true)
                }
                .buttonStyle(.plain)

                if !model.recentActivity.isEmpty {
                    CutSectionTitle("Recent activity")
                        .padding(.top, 28)
                        .padding(.bottom, 10)
                    CutHairlineList {
                        ForEach(model.recentActivity) { friend in
                            Button { actions.openFriend(friend.id) } label: { friendRow(friend) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                bigRow("My friends", trailing: {
                    if let count = model.friendsCount, count > 0 {
                        Text("\(count)")
                            .cutHero(.s)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                    }
                }, action: actions.openFriends)
                .padding(.top, model.recentActivity.isEmpty ? 12 : 20)

                bigRow("Find friends", trailing: {
                    CutTile(systemImage: "plus", side: 56)
                }, action: actions.findFriends)
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .scrollIndicators(.hidden)
        .refreshable { await actions.refresh() }
    }

    private func friendRow(_ friend: CutSocialFriendsModel.Row) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                CutSocialAvatar(initials: friend.initials, url: friend.avatarURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .lineLimit(1)
                    Text(friend.line)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            CutHairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func bigRow<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(title)
                        .cutHero(.s)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing()
                }
                .frame(minHeight: 76)
                .padding(.vertical, 6)
                CutHairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pieces

/// A round avatar: the photo when there is one, else initials (or a symbol) on the control fill.
struct CutSocialAvatar: View {
    let initials: String
    let url: String?
    let size: CGFloat
    var fallbackSymbol: String = "person.fill"

    var body: some View {
        ZStack {
            Circle().fill(DS.Cut.Colors.controlFill)
            if let url, let imageURL = URL(string: url), !url.isEmpty {
                KFImage(imageURL)
                    .placeholder { fallback }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallback: some View {
        if initials.isEmpty {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
        } else {
            Text(initials)
                .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .headline))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(4)
        }
    }
}

/// A count on an icon button: ink on lime.
private struct CutSocialBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.Cut.Typography.condensed(size: 15, weight: .extraBold, relativeTo: .subheadline, monospacedDigits: true))
            .foregroundStyle(DS.Cut.Colors.ink)
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 24)
            .background(Capsule().fill(DS.Cut.Colors.lime))
            .overlay(Capsule().strokeBorder(DS.Cut.Colors.background, lineWidth: 2))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// A big message in place of the feed: condensed title, one line, one button.
private struct CutSocialMessage: View {
    let title: String
    let line: String
    let button: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutHeroText(CutHeroText.balancedLines(title), hero: .s)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
            Text(line)
                .cutFont(.body)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            if let button {
                Button(button, action: action)
                    .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
                    .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 40)
    }
}

/// Quiet placeholder for a post while the first page loads.
private struct CutSocialSkeletonPost: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().frame(width: 120, height: 14)
                    Capsule().frame(width: 70, height: 12)
                }
            }
            Capsule().frame(width: 200, height: 26)
            HStack(spacing: 24) {
                ForEach(0..<3, id: \.self) { _ in Capsule().frame(width: 64, height: 26) }
            }
        }
        .foregroundStyle(DS.Cut.Colors.controlFill)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.vertical, 22)
        .overlay(alignment: .bottom) { CutHairline() }
    }
}
