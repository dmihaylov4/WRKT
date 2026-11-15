//
//  CutSocialPeopleView.swift
//  WRKT
//
//  The pushed Social lists in the Cut language: Activity, Friend requests, My friends and Find
//  friends. A condensed title in place of the nav bar title, then hairline rows on the surface.
//  Lists with swipe actions use a plain List so the system swipe stays. Takes plain values and
//  closures, so every state renders without the app's services (see CutSocialPeopleHost).
//

import SwiftUI

// MARK: - Activity

struct CutActivityActions {
    var refresh: () async -> Void = {}
    var retry: () -> Void = {}
    var dismissError: () -> Void = {}
    var open: (UUID) -> Void = { _ in }
    var markRead: (UUID) -> Void = { _ in }
    var delete: (UUID) -> Void = { _ in }
    var markAllRead: () -> Void = {}
    var clearAll: () -> Void = {}
}

struct CutActivityView: View {
    let model: CutActivityModel
    var actions = CutActivityActions()

    var body: some View {
        List {
            CutPeopleTitle("Activity")
                .cutListRow()
            if let error = model.inlineError {
                CutPeopleErrorRow(message: error, retry: actions.retry, dismiss: actions.dismissError)
                    .cutListRow()
            }
            switch model.content {
            case .loading:
                ForEach(0..<5, id: \.self) { _ in CutPeopleSkeletonRow().cutListRow() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Loading activity"))
            case .failed(let message):
                CutPeopleMessage(line: message, button: "Try again", action: actions.retry)
                    .cutListRow()
            case .empty:
                CutPeopleMessage(line: "When friends like, comment or challenge you, it shows here.")
                    .cutListRow()
            case .sections(let sections):
                ForEach(sections) { section in
                    CutSectionTitle(section.title)
                        .padding(.top, 24)
                        .padding(.bottom, 10)
                        .overlay(alignment: .bottom) { CutHairline() }
                        .cutListRow()
                    ForEach(section.rows) { row in
                        activityRow(row)
                            .cutListRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(row.id) }
                                if row.isUnread {
                                    Button("Mark read", systemImage: "envelope.open") { actions.markRead(row.id) }
                                }
                            }
                            .contextMenu {
                                if row.isUnread {
                                    Button("Mark read", systemImage: "envelope.open") { actions.markRead(row.id) }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(row.id) }
                            }
                    }
                }
            }
        }
        .cutPeopleList()
        .refreshable {
            let refresh = Task { await actions.refresh() }
            await refresh.value
        }
        .toolbar {
            if model.hasUnread || model.canClear {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if model.hasUnread {
                            Button("Mark all read", systemImage: "envelope.open", action: actions.markAllRead)
                        }
                        if model.canClear {
                            Button("Clear all", systemImage: "trash", role: .destructive, action: actions.clearAll)
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
    }

    private func activityRow(_ row: CutActivityModel.Row) -> some View {
        Button { actions.open(row.id) } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    CutSocialAvatar(initials: row.initials, url: row.avatarURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.message)
                            .cutFont(row.isUnread ? .title : .body)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.time)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if row.isUnread {
                        SlantedSegmentShape()
                            .fill(DS.Cut.Colors.lime)
                            .frame(width: 12, height: 8)
                            .accessibilityHidden(true)
                    }
                    if row.opens {
                        CutRowChevron()
                    }
                }
                .padding(.vertical, 12)
                .frame(minHeight: 64)
                CutHairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.opens)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(row.isUnread ? "Unread" : ""))
    }
}

// MARK: - Friend requests

struct CutFriendRequestsActions {
    var refresh: () async -> Void = {}
    var select: (CutFriendRequestsModel.Tab) -> Void = { _ in }
    var retry: () -> Void = {}
    var dismissError: () -> Void = {}
    var openProfile: (UUID) -> Void = { _ in }
    var accept: (UUID) -> Void = { _ in }
    var decline: (UUID) -> Void = { _ in }
    var cancel: (UUID) -> Void = { _ in }
    var findFriends: () -> Void = {}
}

struct CutFriendRequestsView: View {
    let model: CutFriendRequestsModel
    var actions = CutFriendRequestsActions()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CutPeopleTitle("Requests")
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                CutUnderlineTabs(
                    CutFriendRequestsModel.Tab.allCases,
                    selection: model.tab,
                    title: \.rawValue,
                    badge: { $0 == .incoming ? CutSocialLogic.badge(model.incomingCount) : nil },
                    accessibilityLabel: { $0 == .incoming && model.incomingCount > 0 ? "Requests, \(model.incomingCount)" : $0.rawValue },
                    select: actions.select
                )
                .padding(.top, 12)
                if let error = model.error {
                    CutPeopleErrorRow(message: error, retry: actions.retry, dismiss: actions.dismissError)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                }
                content
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
            }
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
            actions.select(CutSocialPeopleLogic.requestTab(afterHorizontalDrag: value.translation.width, vertical: value.translation.height, current: model.tab))
        })
        .scrollIndicators(.hidden)
        .refreshable {
            let refresh = Task { await actions.refresh() }
            await refresh.value
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .loading:
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in CutPeopleSkeletonRow() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading requests"))
        case .empty:
            CutPeopleMessage(line: CutSocialPeopleLogic.requestsEmptyLine(model.tab),
                             button: model.tab == .outgoing ? "Find friends" : nil, action: actions.findFriends)
        case .rows(let rows):
            ForEach(rows) { row in
                CutPersonRowView(row: row.person, open: actions.openProfile, hasActions: true) {
                    if let accept = row.acceptTitle {
                        HStack(spacing: 8) {
                            Button(accept) { actions.accept(row.id) }
                                .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
                                .accessibilityLabel(Text("\(accept) \(row.person.name)"))
                            Button("Decline", systemImage: "xmark") { actions.decline(row.id) }
                                .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: DS.Cut.Metrics.minTouchTarget))
                                .accessibilityLabel(Text("Decline \(row.person.name)"))
                        }
                    } else {
                        Button("Cancel") { actions.cancel(row.id) }
                            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                            .accessibilityLabel(Text("Cancel request to \(row.person.name)"))
                    }
                }
            }
        }
    }
}

// MARK: - Friends

struct CutFriendsListActions {
    var refresh: () async -> Void = {}
    var retry: () -> Void = {}
    var dismissError: () -> Void = {}
    var open: (UUID) -> Void = { _ in }
    var remove: (UUID) -> Void = { _ in }
    var findFriends: () -> Void = {}
}

struct CutFriendsListView: View {
    let model: CutFriendsListModel
    @Binding var query: String
    var actions = CutFriendsListActions()

    var body: some View {
        List {
            CutPeopleTitle("Friends")
                .cutListRow()
            if let error = model.inlineError {
                CutPeopleErrorRow(message: error, retry: actions.retry, dismiss: actions.dismissError).cutListRow()
            }
            if model.showsSearch {
                CutSearchField(prompt: "Search friends", text: $query)
                    .padding(.vertical, 12)
                    .cutListRow()
            }
            switch model.content {
            case .loading:
                ForEach(0..<5, id: \.self) { _ in CutPeopleSkeletonRow().cutListRow() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Loading friends"))
            case .failed(let message):
                CutPeopleMessage(line: message, button: "Try again", action: actions.retry)
                    .cutListRow()
            case .empty:
                CutPeopleMessage(line: "No friends yet. Find people and send a friend request.",
                                 button: "Find friends", action: actions.findFriends)
                    .cutListRow()
            case .noResults(let query):
                Text("No friends match \"\(query)\".")
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .padding(.top, 20)
                    .cutListRow()
            case .rows(let rows):
                CutHairline().cutListRow()
                ForEach(rows) { row in
                    CutPersonRowView(row: row, open: { _ in actions.open(row.id) }) {
                        CutRowChevron()
                    }
                    .cutListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Remove", systemImage: "person.fill.xmark", role: .destructive) { actions.remove(row.id) }
                    }
                    .contextMenu {
                        Button("Remove friend", systemImage: "person.fill.xmark", role: .destructive) { actions.remove(row.id) }
                    }
                }
            }
        }
        .cutPeopleList()
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            let refresh = Task { await actions.refresh() }
            await refresh.value
        }
    }
}

// MARK: - Find friends

struct CutUserSearchView: View {
    let model: CutUserSearchModel
    @Binding var query: String
    var open: (UUID) -> Void = { _ in }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CutPeopleTitle("Find friends")
                CutSearchField(prompt: "Search by username", text: $query, submitLabel: .search)
                    .padding(.vertical, 12)
                content
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .idle:
            line("Search by username to find people.")
        case .searching:
            HStack(spacing: 10) {
                ProgressView().tint(DS.Cut.Colors.textSecondary)
                Text("Searching").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            }
            .padding(.top, 20)
            .accessibilityElement(children: .combine)
        case .failed(let message):
            line(message)
        case .noResults:
            line("No one found. Try a different username.")
        case .rows(let rows):
            CutHairline()
            ForEach(rows) { row in
                CutPersonRowView(row: row, open: open) { CutRowChevron() }
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .cutFont(.body)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 20)
    }
}

// MARK: - Pieces

/// The one line a list shows in place of rows (empty or failed), with an optional button.
/// The screen's title already carries the heading, so no second hero.
private struct CutPeopleMessage: View {
    let line: String
    var button: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(line)
                .cutFont(.body)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button, action: action)
                    .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }
}

/// The condensed title a pushed list shows instead of a nav bar title.
private struct CutPeopleTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

/// A person on the surface: avatar and name open the profile; the trailing slot holds the
/// row's actions or a chevron. Draws its own bottom hairline.
private struct CutPersonRowView<Trailing: View>: View {
    let row: CutSocialPersonRow
    let open: (UUID) -> Void
    var hasActions = false
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if hasActions && dynamicTypeSize >= .xxxLarge {
                    VStack(alignment: .leading, spacing: 12) {
                        personButton
                        trailing()
                    }
                } else {
                    HStack(spacing: 14) {
                        personButton
                        trailing().fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            CutHairline()
        }
    }

    private var personButton: some View {
        Button { open(row.profileId) } label: {
            HStack(spacing: 14) {
                CutSocialAvatar(initials: row.initials, url: row.avatarURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).cutFont(.title).foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let line = row.line {
                        Text(line).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let bio = row.bio, !bio.isEmpty {
                        Text(bio).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens profile"))
    }
}

/// The trailing chevron on a row that opens something.
private struct CutRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .accessibilityHidden(true)
    }
}

/// A search field on the surface: an outlined capsule with a clear button.
private struct CutSearchField: View {
    let prompt: String
    @Binding var text: String
    var submitLabel: SubmitLabel = .done

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(DS.Cut.Colors.textSecondary))
                .cutFont(.body)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .tint(DS.Cut.Colors.lime)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(submitLabel)
            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, text.isEmpty ? 18 : 4)
        .frame(minHeight: 50)
        .overlay(Capsule().strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1.5))
    }
}

/// An error over content that is already showing: the message, Retry and Dismiss.
private struct CutPeopleErrorRow: View {
    let message: String
    var retry: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(message)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let retry {
                    Button("Retry", action: retry)
                        .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                }
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: DS.Cut.Metrics.minTouchTarget))
            }
            .padding(.vertical, 12)
            CutHairline()
        }
    }
}

/// Quiet placeholder for a person row while a list loads.
private struct CutPeopleSkeletonRow: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Circle().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().frame(width: 140, height: 14)
                    Capsule().frame(width: 90, height: 12)
                }
                Spacer()
            }
            .foregroundStyle(DS.Cut.Colors.controlFill)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            CutHairline()
        }
    }
}

extension View {
    /// A List row on the surface: gutter insets, no system separator or background.
    fileprivate func cutListRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Cut.Metrics.gutter, bottom: 0, trailing: DS.Cut.Metrics.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Cut.Colors.background)
    }

    /// A plain List on the black surface, clear of the tab bar.
    fileprivate func cutPeopleList() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .contentMargins(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60), for: .scrollContent)
            .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}
