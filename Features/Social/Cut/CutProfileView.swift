import SwiftUI

struct CutProfileActions {
    var refresh: () async -> Void = {}
    var retry: () -> Void = {}
    var perform: (CutProfileModel.Action) -> Void = { _ in }
    var openPost: (UUID) -> Void = { _ in }
    var acceptBattle: () -> Void = {}
    var declineBattle: () -> Void = {}
}

struct CutProfileView<AvatarPicker: View, Showcase: View>: View {
    let model: CutProfileModel
    var actions = CutProfileActions()
    @ViewBuilder var avatarPicker: () -> AvatarPicker
    @ViewBuilder var showcase: () -> Showcase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                switch model.state {
                case .loading:
                    title("Profile")
                    HStack(spacing: 12) { ProgressView(); Text("Loading profile").cutFont(.body) }
                case .failed(let error):
                    title(error == "Profile not found" ? "Profile Not Found" : "Couldn’t Load Profile")
                    Text(error).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                    Button("Try Again", action: actions.retry).buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
                case .loaded:
                    if let battle = model.battle { battleSection(battle) }
                    identity
                    rows(model.metadata)
                    if !model.ownStats.isEmpty { CutStatColumns(model.ownStats) }
                    showcase()
                    if let comparison = model.comparison {
                        section(comparison.title) {
                            Text(comparison.message).cutFont(.body)
                            Text(comparison.callout).cutFont(.body).foregroundStyle(DS.Cut.Colors.lime)
                            rows(Array(comparison.rows.prefix(2)))
                            comparisonBar("You", value: comparison.yourWeek, maximum: max(comparison.yourWeek, comparison.friendWeek, 1))
                            comparisonBar(model.name, value: comparison.friendWeek, maximum: max(comparison.yourWeek, comparison.friendWeek, 1))
                            CutSectionTitle("Consistency")
                            rows(Array(comparison.rows.dropFirst(2)))
                        }
                        section("Accountability Snapshot") { rows(model.accountability) }
                        section(model.friendshipTitle) {
                            friendshipActions
                            Text(model.friendshipHelp).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                    }
                    posts
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .refreshable {
            let refresh = Task { @MainActor in await actions.refresh() }
            await refresh.value
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                avatar
                name
                edit
            } else {
                HStack(alignment: .top, spacing: 16) { avatar; name; edit }
            }
            if let bio = model.bio, !bio.isEmpty { Text(bio).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary) }
        }
    }
    private var avatar: some View {
        CutSocialAvatar(initials: model.initials, url: model.avatarURL, size: 80)
            .overlay(alignment: .bottomTrailing) { avatarPicker() }
    }
    private var name: some View {
        VStack(alignment: .leading, spacing: 4) {
            title(model.name)
            if let handle = model.handle { Text(handle).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var edit: some View {
        if model.actions.contains(.edit) {
            Button("Edit") { actions.perform(.edit) }.buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                .accessibilityLabel("Edit profile")
        }
    }
    @ViewBuilder private var friendshipActions: some View {
        if model.actions.contains(.remove) {
            Menu {
                Button(model.actions.contains(.mute) ? "Mute Notifications" : "Unmute Notifications", systemImage: model.actions.contains(.mute) ? "bell.slash.fill" : "bell.fill") {
                    actions.perform(model.actions.contains(.mute) ? .mute : .unmute)
                }
                Button("Remove Friend", systemImage: "person.fill.xmark", role: .destructive) { actions.perform(.remove) }
            } label: {
                Label(model.actions.contains(.unmute) ? "Friends · Muted" : "Friends", systemImage: "checkmark.circle")
            }
            .buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
        } else if model.actions.contains(.add) {
            Button { actions.perform(.add) } label: {
                if model.isLoadingFriendship { ProgressView() } else { Text("Add Friend") }
            }.buttonStyle(CutPrimaryButtonStyle(fillsWidth: false)).disabled(model.isLoadingFriendship)
        } else if model.actions.contains(.cancel) {
            Button("Cancel Request") { actions.perform(.cancel) }.buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
        } else if model.actions.contains(.accept) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { accept; decline }
                VStack(alignment: .leading, spacing: 12) { accept; decline }
            }
        }
    }
    private var accept: some View { Button("Accept") { actions.perform(.accept) }.buttonStyle(CutPrimaryButtonStyle(fillsWidth: false)) }
    private var decline: some View { Button("Decline") { actions.perform(.decline) }.buttonStyle(CutSecondaryButtonStyle(fillsWidth: false)) }
    private var posts: some View {
        section("Recent Activity") {
            if model.isLoadingPosts {
                HStack(spacing: 12) { ProgressView(); Text("Loading posts").cutFont(.body) }
            } else if model.posts.isEmpty {
                Text("No workouts shared yet").cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.vertical, 16)
            } else {
                ForEach(model.posts) { post in
                    Button { actions.openPost(post.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            if let caption = post.caption { Text(caption).cutFont(.body).multilineTextAlignment(.leading) }
                            Label(post.title, systemImage: post.icon).cutFont(.title)
                            Text(post.date).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                            if !post.stats.isEmpty { Text(post.stats).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary) }
                            CutHairline().padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.vertical, 6)
                }
            }
        }
    }
    private func battleSection(_ battle: CutProfileModel.Battle) -> some View {
        section("Battle Challenge!") {
            Text(battle.challenger).cutFont(.body)
            rows(battle.rows)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { battleDecline; battleAccept }
                VStack(alignment: .leading, spacing: 12) { battleAccept; battleDecline }
            }
        }
    }
    private var battleAccept: some View { Button("Accept Challenge", action: actions.acceptBattle).buttonStyle(CutPrimaryButtonStyle(fillsWidth: false)) }
    private var battleDecline: some View { Button("Decline", action: actions.declineBattle).buttonStyle(CutSecondaryButtonStyle(fillsWidth: false)) }
    private func comparisonBar(_ label: String, value: Int, maximum: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(value)").cutFont(.secondary)
            GeometryReader { geometry in
                Rectangle().fill(DS.Cut.Colors.segmentTrack)
                    .overlay(alignment: .leading) {
                        SlantedSegmentShape().fill(label == "You" ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                            .frame(width: max(8, geometry.size.width * Double(value) / Double(maximum)))
                    }
            }.frame(height: 8)
        }.accessibilityElement(children: .combine)
    }
    private func rows(_ rows: [CutProfileModel.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(row.label).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        Spacer(minLength: 8)
                        Text(row.value).cutFont(.body).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.label).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        Text(row.value).cutFont(.body).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 10)
                CutHairline()
            }
        }
    }
    private func title(_ text: String) -> some View {
        Text(text.uppercased()).font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { CutSectionTitle(title); CutHairline(); content() }
    }
}
