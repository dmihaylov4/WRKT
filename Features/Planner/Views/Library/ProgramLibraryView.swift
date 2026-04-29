//
//  ProgramLibraryView.swift
//  WRKT
//
//  Planner library with share, receive, activation, and sent-invite flows.
//

import SwiftUI
import Kingfisher
import UniformTypeIdentifiers

struct ProgramLibraryView: View {
    @Environment(\.dependencies) private var deps
    @Binding var pendingNotification: AppNotification?

    @State private var viewModel: ProgramLibraryViewModel?
    @State private var selectedShareSplitID: UUID?
    @State private var selectedSentSplitID: UUID?
    @State private var previewInviteID: UUID?

    init(pendingNotification: Binding<AppNotification?> = .constant(nil)) {
        self._pendingNotification = pendingNotification
    }

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                ProgressView("Loading programs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await configureViewModelIfNeeded()
                    }
            }
        }
        .navigationTitle("Programs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await configureViewModelIfNeeded()
            await viewModel?.startRealtime()
            await viewModel?.refreshPendingInvites()
            viewModel?.refreshLibrary()
            consumePendingNotification()
        }
        .onChange(of: pendingNotification) { _, _ in
            consumePendingNotification()
        }
    }

    @ViewBuilder
    private func content(for viewModel: ProgramLibraryViewModel) -> some View {
        let library = viewModel.library

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ProgramLibraryIntroCard()

                if let activeSplit = viewModel.activeSplit {
                    ProgramSection(title: "Active Program") {
                        ProgramRowView(
                            split: activeSplit,
                            isActive: true,
                            onShare: { selectedShareSplitID = activeSplit.id },
                            onActivate: {},
                            onManageInvites: { selectedSentSplitID = activeSplit.id }
                        )
                    }
                }

                if !viewModel.pendingInvites.isEmpty {
                    ProgramSection(title: "Pending Invites") {
                        SharedWithMeSection(
                            invites: viewModel.pendingInvites,
                            onOpenInvite: { previewInviteID = $0.id }
                        )
                    }
                }

                ProgramSection(title: "Library") {
                    if library.isEmpty {
                        ProgramEmptyStateCard(
                            title: "No Programs Yet",
                            message: "Accepted programs appear here."
                        )
                    } else {
                        ForEach(library.filter { $0.id != viewModel.activeSplit?.id }, id: \.id) { split in
                            ProgramRowView(
                                split: split,
                                isActive: false,
                                onShare: { selectedShareSplitID = split.id },
                                onActivate: { viewModel.activate(split) },
                                onManageInvites: {
                                    guard split.lastSharedProgramID != nil else { return }
                                    selectedSentSplitID = split.id
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(DS.Semantic.surface)
        .refreshable {
            viewModel.refreshLibrary()
            await viewModel.refreshPendingInvites()
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 96)
        }
        .sheet(item: shareSheetBinding(from: library)) { item in
            ProgramShareSheet(
                split: item.split,
                currentUserID: item.currentUserID,
                currentUsername: item.currentUsername,
                currentDisplayName: item.currentDisplayName,
                onComplete: {
                    viewModel.refreshLibrary()
                    selectedSentSplitID = item.split.id
                }
            )
            .environment(\.dependencies, deps)
        }
        .sheet(item: sentInvitesBinding(from: library)) { item in
            SentInvitesSheet(split: item.split)
                .environment(\.dependencies, deps)
        }
        .sheet(item: previewBinding) { item in
            NavigationStack {
                ProgramPreviewView(
                    inviteID: item.id,
                    onChanged: {
                        viewModel.refreshLibrary()
                        await viewModel.refreshPendingInvites()
                    }
                )
                .environment(\.dependencies, deps)
            }
        }
        .alert("Program Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
    }

    private func configureViewModelIfNeeded() async {
        guard viewModel == nil, let currentUserID = deps.authService.currentUser?.id else { return }
        viewModel = ProgramLibraryViewModel(
            repo: deps.programSharingRepository,
            plannerStore: deps.plannerStore,
            currentUserID: currentUserID,
            realtime: deps.realtimeService,
            profileRepo: deps.profileRepository
        )
        viewModel?.refreshLibrary()
        await viewModel?.refreshPendingInvites()
    }

    private func consumePendingNotification() {
        guard pendingNotification?.type == .programInvite else { return }
        previewInviteID = pendingNotification?.targetId
        pendingNotification = nil
    }

    private var previewBinding: Binding<InviteSheetItem?> {
        Binding(
            get: {
                guard let previewInviteID else { return nil }
                return InviteSheetItem(id: previewInviteID)
            },
            set: { item in
                previewInviteID = item?.id
            }
        )
    }

    private func shareSheetBinding(from library: [WorkoutSplit]) -> Binding<ShareSheetItem?> {
        Binding(
            get: {
                guard
                    let selectedShareSplitID,
                    let currentUser = deps.authService.currentUser,
                    let split = (library.first { $0.id == selectedShareSplitID })
                        ?? (viewModel?.activeSplit?.id == selectedShareSplitID ? viewModel?.activeSplit : nil)
                else {
                    return nil
                }

                return ShareSheetItem(
                    split: split,
                    currentUserID: currentUser.id,
                    currentUsername: currentUser.profile?.username,
                    currentDisplayName: currentUser.profile?.displayName
                )
            },
            set: { item in
                selectedShareSplitID = item?.split.id
            }
        )
    }

    private func sentInvitesBinding(from library: [WorkoutSplit]) -> Binding<SplitSheetItem?> {
        Binding(
            get: {
                guard let selectedSentSplitID else { return nil }
                guard let split = library.first(where: { $0.id == selectedSentSplitID }) else { return nil }
                return SplitSheetItem(split: split)
            },
            set: { item in
                selectedSentSplitID = item?.split.id
            }
        )
    }
}

private struct ShareSheetItem: Identifiable {
    let split: WorkoutSplit
    let currentUserID: UUID
    let currentUsername: String?
    let currentDisplayName: String?

    var id: UUID { split.id }
}

private struct SplitSheetItem: Identifiable {
    let split: WorkoutSplit
    var id: UUID { split.id }
}

private struct InviteSheetItem: Identifiable {
    let id: UUID
}

private struct ProgramRowView: View {
    let split: WorkoutSplit
    let isActive: Bool
    let onShare: () -> Void
    let onActivate: () -> Void
    let onManageInvites: () -> Void

    private var attributionText: String? {
        if let creatorDisplayName = split.creatorDisplayName {
            return "By \(creatorDisplayName)"
        }
        if let creatorUsername = split.creatorUsername {
            return "By @\(creatorUsername)"
        }
        return nil
    }

    private var metadataText: String {
        let dayCount = split.planBlocks.count
        let exerciseCount = split.planBlocks.flatMap(\.exercises).count
        return "\(dayCount) days • \(exerciseCount) exercises"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DS.Theme.accent.opacity(0.14))

                    Image(systemName: isActive ? "figure.strengthtraining.traditional" : "square.stack.3d.up.fill")
                        .dsFont(.headline, weight: .semibold)
                        .foregroundStyle(DS.Theme.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(split.name)
                            .dsFont(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        if isActive {
                            Text("ACTIVE")
                                .dsFont(.caption2, weight: .bold)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(DS.Theme.accent, in: Capsule())
                        } else if split.originProgramID != nil {
                            Text("SHARED")
                                .dsFont(.caption2, weight: .bold)
                                .foregroundStyle(DS.Semantic.brand)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(DS.Semantic.brandSoft, in: Capsule())
                        }
                    }

                    Text(metadataText)
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    if let attributionText {
                        Text(attributionText)
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    if let description = split.programDescription, !description.isEmpty {
                        Text(description)
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            HStack(spacing: 10) {
                ProgramActionButton("Share", kind: .primary) {
                    onShare()
                }

                if !isActive {
                    ProgramActionButton("Activate", kind: .secondary) {
                        onActivate()
                    }
                }

                if split.lastSharedProgramID != nil {
                    ProgramActionButton("Sent", kind: .secondary) {
                        onManageInvites()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SharedWithMeSection: View {
    let invites: [ProgramLibraryViewModel.PendingInviteDisplay]
    let onOpenInvite: (ProgramLibraryViewModel.PendingInviteDisplay) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(invites) { invite in
                Button {
                    onOpenInvite(invite)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(DS.Theme.accent.opacity(0.14))

                            Image(systemName: "tray.and.arrow.down.fill")
                                .foregroundStyle(DS.Theme.accent)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(invite.programName)
                                .dsFont(.subheadline, weight: .semibold)
                                .foregroundStyle(DS.Semantic.textPrimary)

                            Text(senderText(for: invite))
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
                    .overlay(
                        ChamferedRectangle(.xl)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func senderText(for invite: ProgramLibraryViewModel.PendingInviteDisplay) -> String {
        if let displayName = invite.senderDisplayName {
            return "\(displayName) shared this with you"
        }
        if let username = invite.senderUsername {
            return "@\(username) shared this with you"
        }
        return "Shared with you"
    }
}

private struct ProgramSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .dsFont(.caption, weight: .bold)
                    .tracking(1.2)
                    .foregroundStyle(DS.Theme.accent)

                if let subtitle {
                    Text(subtitle)
                        .dsFont(.footnote)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            content
        }
    }
}

private struct ProgramLibraryIntroCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .dsFont(.headline, weight: .semibold)
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(DS.Theme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Programs")
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Plans, shared routines, and library.")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(DS.Theme.accent.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ProgramEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .dsFont(.headline)
                .foregroundStyle(DS.Theme.accent)
                .frame(width: 42, height: 42)
                .background(DS.Theme.accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(message)
                    .dsFont(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ProgramActionButton: View {
    enum Kind {
        case primary
        case secondary
    }

    let title: String
    let kind: Kind
    let action: () -> Void

    init(_ title: String, kind: Kind, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(kind == .primary ? Color.black : DS.Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(background, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch kind {
        case .primary:
            return DS.Theme.accent
        case .secondary:
            return DS.Theme.accent.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return DS.Theme.accent.opacity(0.35)
        case .secondary:
            return DS.Theme.accent.opacity(0.22)
        }
    }
}

private struct ProgramShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    let split: WorkoutSplit
    let currentUserID: UUID
    let currentUsername: String?
    let currentDisplayName: String?
    let onComplete: () -> Void

    @State private var viewModel: ProgramShareViewModel?
    @State private var showFriendPicker = false
    @State private var showResultAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    VStack(spacing: 0) {
                        ProgramSheetHeader(
                            title: "Share Program",
                            cancelTitle: "Cancel",
                            confirmTitle: "Send",
                            isConfirmDisabled: viewModel.selectedFriends.isEmpty || viewModel.isSending,
                            onCancel: { dismiss() },
                            onConfirm: {
                                Task {
                                    let didSend = await sendProgram(using: viewModel)
                                    showResultAlert = didSend
                                }
                            }
                        )

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                ProgramShareHeroCard(split: split)

                                ProgramSection(title: "Program", subtitle: "What you are sending.") {
                                    ProgramShareSummaryCard(split: split)
                                }

                                ProgramSection(title: "Recipients", subtitle: "Choose who gets this program.") {
                                    VStack(spacing: 12) {
                                        Button {
                                            showFriendPicker = true
                                        } label: {
                                            HStack(spacing: 12) {
                                                ZStack {
                                                    Circle()
                                                        .fill(DS.Theme.accent.opacity(0.14))

                                                    Image(systemName: "person.2.fill")
                                                        .foregroundStyle(DS.Theme.accent)
                                                }
                                                .frame(width: 40, height: 40)

                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text("Choose Friends")
                                                        .dsFont(.subheadline, weight: .semibold)
                                                        .foregroundStyle(DS.Semantic.textPrimary)
                                                    Text(recipientSummary(for: viewModel))
                                                        .dsFont(.caption)
                                                        .foregroundStyle(DS.Semantic.textSecondary)
                                                }

                                                Spacer()

                                                Text("\(viewModel.selectedFriends.count)")
                                                    .dsFont(.subheadline, weight: .bold)
                                                    .foregroundStyle(DS.Theme.accent)

                                                Image(systemName: "chevron.right")
                                                    .dsFont(.caption, weight: .semibold)
                                                    .foregroundStyle(DS.Semantic.textSecondary)
                                            }
                                            .padding(16)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
                                            .overlay(
                                                ChamferedRectangle(.xl)
                                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        if !viewModel.selectedFriends.isEmpty {
                                            VStack(spacing: 10) {
                                                ForEach(viewModel.selectedFriends, id: \.id) { friend in
                                                    HStack(spacing: 12) {
                                                        AvatarChip(profile: friend)

                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(friend.displayName ?? friend.username)
                                                                .dsFont(.subheadline, weight: .semibold)
                                                                .foregroundStyle(DS.Semantic.textPrimary)
                                                            Text("@\(friend.username)")
                                                                .dsFont(.caption)
                                                                .foregroundStyle(DS.Semantic.textSecondary)
                                                        }

                                                        Spacer()

                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(DS.Theme.accent)
                                                    }
                                                    .padding(14)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .background(DS.Semantic.card, in: ChamferedRectangle(.large))
                                                    .overlay(
                                                        ChamferedRectangle(.large)
                                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }

                                ProgramSection(title: "Message", subtitle: "Optional context for the share.") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Description")
                                            .dsFont(.caption, weight: .bold)
                                            .foregroundStyle(DS.Theme.accent)
                                            .tracking(1.0)

                                        TextField("Optional description", text: Binding(
                                            get: { viewModel.descriptionText },
                                            set: { viewModel.descriptionText = $0 }
                                        ), axis: .vertical)
                                        .lineLimit(3...6)
                                        .dsFont(.subheadline)
                                        .foregroundStyle(DS.Semantic.textPrimary)
                                        .padding(14)
                                        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
                                        .overlay(
                                            ChamferedRectangle(.large)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 32)
                        }
                        .background(DS.Semantic.surface)
                    }
                    .sheet(isPresented: $showFriendPicker) {
                        FriendMultiPicker(selectedFriends: Binding(
                            get: { viewModel.selectedFriends },
                            set: { viewModel.selectedFriends = $0 }
                        ), onSend: {
                            let didSend = await sendProgram(using: viewModel)
                            showResultAlert = didSend
                            return didSend
                        })
                        .environment(\.dependencies, deps)
                    }
                    .alert("Share Result", isPresented: $showResultAlert) {
                        Button("Done") {
                            dismiss()
                            onComplete()
                        }
                    } message: {
                        if let result = viewModel.lastResult {
                            Text(resultMessage(for: result))
                        } else {
                            Text(viewModel.errorMessage ?? "Unable to share this program.")
                        }
                    }
                    .alert("Share Error", isPresented: Binding(
                        get: { viewModel.errorMessage != nil && !showResultAlert },
                        set: { if !$0 { viewModel.errorMessage = nil } }
                    )) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(viewModel.errorMessage ?? "Unable to share this program.")
                    }
                } else {
                    ProgressView("Preparing share...")
                        .task {
                            if viewModel == nil {
                                viewModel = ProgramShareViewModel(
                                    repo: deps.programSharingRepository,
                                    plannerStore: deps.plannerStore
                                )
                            }
                        }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func sendProgram(using viewModel: ProgramShareViewModel) async -> Bool {
        await viewModel.send(
            split: split,
            currentUserID: currentUserID,
            currentUsername: currentUsername,
            currentDisplayName: currentDisplayName
        )
    }

    private func resultMessage(for result: ProgramSharingRepository.SendResult) -> String {
        let sentCount = result.succeeded.count
        let failedCount = result.failed.count
        if failedCount == 0 {
            return "Shared with \(sentCount) \(sentCount == 1 ? "friend" : "friends")."
        }
        return "Shared with \(sentCount) \(sentCount == 1 ? "friend" : "friends"). \(failedCount) failed."
    }

    private func recipientSummary(for viewModel: ProgramShareViewModel) -> String {
        let count = viewModel.selectedFriends.count
        switch count {
        case 0:
            return "No friends selected yet"
        case 1:
            return "1 friend selected"
        default:
            return "\(count) friends selected"
        }
    }
}

private struct ProgramSheetHeader: View {
    let title: String
    let cancelTitle: String
    let confirmTitle: String
    let isConfirmDisabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(cancelTitle, action: onCancel)
                .buttonStyle(ProgramSheetHeaderButtonStyle(kind: .secondary, isDisabled: false))

            Spacer()

            Text(title)
                .dsFont(.title3, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)

            Spacer()

            Button(confirmTitle, action: onConfirm)
                .buttonStyle(ProgramSheetHeaderButtonStyle(kind: .primary, isDisabled: isConfirmDisabled))
                .disabled(isConfirmDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(DS.Semantic.surface)
    }
}

private struct ProgramSheetHeaderButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsFont(.subheadline, weight: .semibold)
            .foregroundStyle(foreground)
            .frame(width: 92, height: 46)
            .background(background(configuration: configuration), in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(border, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.42 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return isDisabled ? DS.Semantic.textSecondary : .black
        case .secondary:
            return DS.Theme.accent
        }
    }

    private func background(configuration: Configuration) -> Color {
        let base: Color
        switch kind {
        case .primary:
            base = isDisabled ? DS.Semantic.surface50 : DS.Theme.accent
        case .secondary:
            base = DS.Semantic.fillSubtle
        }
        return configuration.isPressed ? base.opacity(0.72) : base
    }

    private var border: Color {
        switch kind {
        case .primary:
            return isDisabled ? Color.white.opacity(0.10) : DS.Theme.accent.opacity(0.35)
        case .secondary:
            return Color.white.opacity(0.12)
        }
    }
}

private struct ProgramShareHeroCard: View {
    let split: WorkoutSplit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .dsFont(.headline, weight: .semibold)
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(DS.Theme.accent, in: Circle())

                Text("Share Program")
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            Text("Send \(split.name) to friends without changing your own setup. They can preview it, save it, and activate it on their own schedule.")
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: ChamferedRectangle(.xl)
        )
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(DS.Theme.accent.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ProgramShareSummaryCard: View {
    let split: WorkoutSplit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(split.name)
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("\(split.planBlocks.count) days • \(split.planBlocks.flatMap(\.exercises).count) exercises")
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)

            if let description = split.programDescription, !description.isEmpty {
                Text(description)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FriendMultiPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    @Binding var selectedFriends: [UserProfile]
    let onSend: () async -> Bool

    @State private var friends: [Friend] = []
    @State private var isLoading = true
    @State private var isSending = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgramSheetHeader(
                    title: "Choose Friends",
                    cancelTitle: "Cancel",
                    confirmTitle: "Send",
                    isConfirmDisabled: selectedFriends.isEmpty || isSending,
                    onCancel: { dismiss() },
                    onConfirm: {
                        Task {
                            guard !selectedFriends.isEmpty, !isSending else { return }
                            isSending = true
                            let didSend = await onSend()
                            isSending = false
                            if didSend {
                                dismiss()
                            }
                        }
                    }
                )

                Group {
                    if isLoading {
                        ProgressView("Loading friends...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if friends.isEmpty {
                        ContentUnavailableView(
                            "No Friends Yet",
                            systemImage: "person.2.slash",
                            description: Text("Add friends before sharing a program.")
                        )
                    } else {
                        List(filteredFriends, id: \.id) { friend in
                            Button {
                                toggle(friend.profile)
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarChip(profile: friend.profile)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.profile.displayName ?? friend.profile.username)
                                            .foregroundStyle(DS.Semantic.textPrimary)
                                        Text("@\(friend.profile.username)")
                                            .dsFont(.caption)
                                            .foregroundStyle(DS.Semantic.textSecondary)
                                    }
                                    Spacer()
                                    if selectedFriends.contains(where: { $0.id == friend.profile.id }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(DS.Semantic.brand)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .background(DS.Semantic.surface)
                .searchable(text: $searchText, prompt: "Search friends")
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadFriends()
            }
        }
    }

    private var filteredFriends: [Friend] {
        guard !searchText.isEmpty else { return friends }
        return friends.filter {
            $0.profile.username.localizedCaseInsensitiveContains(searchText)
            || $0.profile.displayName?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    private func loadFriends() async {
        guard let currentUserId = deps.authService.currentUser?.id else {
            isLoading = false
            return
        }

        do {
            friends = try await deps.friendshipRepository.fetchFriends(userId: currentUserId)
        } catch {
            friends = []
        }
        isLoading = false
    }

    private func toggle(_ profile: UserProfile) {
        if let index = selectedFriends.firstIndex(where: { $0.id == profile.id }) {
            selectedFriends.remove(at: index)
        } else {
            selectedFriends.append(profile)
        }
    }
}

struct ProgramPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    let inviteID: UUID
    let onChanged: (() async -> Void)?
    let bottomActionPadding: CGFloat

    @State private var viewModel: ProgramInviteViewModel?
    @State private var editingExercise: ProgramExerciseEditItem?
    @State private var draggedBlockID: UUID?

    init(inviteID: UUID, bottomActionPadding: CGFloat = 0, onChanged: (() async -> Void)? = nil) {
        self.inviteID = inviteID
        self.bottomActionPadding = bottomActionPadding
        self.onChanged = onChanged
    }

    var body: some View {
        Group {
            if let viewModel {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        header(for: viewModel)
                        blockList(for: viewModel)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .background(DS.Semantic.surface)
                .safeAreaInset(edge: .bottom) {
                    footer(for: viewModel)
                }
                .alert("Program", isPresented: Binding(
                    get: { viewModel.errorMessage != nil || viewModel.successMessage != nil },
                    set: { presented in
                        if !presented {
                            viewModel.errorMessage = nil
                            viewModel.successMessage = nil
                        }
                    }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(viewModel.errorMessage ?? viewModel.successMessage ?? "")
                }
            } else {
                ProgressView("Loading program...")
                    .task {
                        let model = ProgramInviteViewModel(
                            repo: deps.programSharingRepository,
                            plannerStore: deps.plannerStore,
                            profileRepo: deps.profileRepository
                        )
                        await model.load(inviteID: inviteID)
                        guard !Task.isCancelled else { return }
                        viewModel = model
                    }
            }
        }
        .navigationTitle("Program Invite")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: exerciseEditBinding(for: viewModel)) { item in
            ProgramExerciseEditSheet(exercise: item.exercise)
        }
    }

    @ViewBuilder
    private func header(for viewModel: ProgramInviteViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DS.Theme.accent)

                    Image(systemName: viewModel.program == nil ? "exclamationmark.triangle.fill" : "square.stack.3d.up.fill")
                        .dsFont(.headline, weight: .bold)
                        .foregroundStyle(.black)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.program?.name ?? "Program Invite")
                        .dsFont(.title3, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    if let senderProfile = viewModel.senderProfile {
                        Text(senderLine(for: senderProfile))
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }

            if let description = viewModel.program?.description, !description.isEmpty {
                Text(description)
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let senderProfile = viewModel.senderProfile {
                HStack(spacing: 12) {
                    AvatarChip(profile: senderProfile)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(senderProfile.displayName ?? senderProfile.username)
                            .dsFont(.subheadline, weight: .semibold)
                        Text("@\(senderProfile.username)")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: ChamferedRectangle(.xl)
        )
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(DS.Theme.accent.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func blockList(for viewModel: ProgramInviteViewModel) -> some View {
        if let blocks = viewModel.previewSplit?.planBlocks {
            ProgramSection(title: "Schedule", subtitle: "\(blocks.count) days in this program.") {
                VStack(spacing: 12) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        ProgramInviteDayCard(
                            block: block,
                            dayIndex: index,
                            dayCount: blocks.count,
                            onEditExercise: { exercise in
                                editingExercise = ProgramExerciseEditItem(blockID: block.id, exerciseID: exercise.id)
                            },
                            onDropOnBlock: { sourceID, targetID in
                                viewModel.dropBlock(id: sourceID, on: targetID)
                            },
                            draggedBlockID: $draggedBlockID
                        )
                    }
                }
            }
        } else {
            ProgramInviteUnavailableCard(
                message: viewModel.availabilityMessage ?? "This program invite is no longer available."
            )
        }
    }

    private func exerciseEditBinding(for viewModel: ProgramInviteViewModel?) -> Binding<ProgramExerciseEditSheet.Item?> {
        Binding(
            get: {
                guard
                    let editingExercise,
                    let exercise = viewModel?.previewSplit?.planBlocks
                        .first(where: { $0.id == editingExercise.blockID })?
                        .exercises
                        .first(where: { $0.id == editingExercise.exerciseID })
                else { return nil }

                return ProgramExerciseEditSheet.Item(exercise: exercise)
            },
            set: { item in
                editingExercise = item == nil ? nil : editingExercise
            }
        )
    }

    @ViewBuilder
    private func footer(for viewModel: ProgramInviteViewModel) -> some View {
        VStack(spacing: 10) {
            Divider()

            if viewModel.importedSplit != nil {
                HStack(spacing: 12) {
                    ProgramFooterButton("Close", kind: .secondary) {
                        dismiss()
                    }

                    ProgramFooterButton("Activate Now", kind: .primary, isDisabled: viewModel.isActing) {
                        if viewModel.activateImportedProgram() {
                            dismiss()
                            Task {
                                if let onChanged {
                                    await onChanged()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8 + bottomActionPadding)
            } else {
                HStack(spacing: 12) {
                    ProgramFooterButton("Decline", kind: .secondary, isDisabled: viewModel.isActing || viewModel.invite?.status != .pending) {
                        Task {
                            let didDecline = await viewModel.declineInvite()
                            if didDecline {
                                if let onChanged {
                                    await onChanged()
                                }
                                dismiss()
                            }
                        }
                    }

                    ProgramFooterButton("Add to Library", kind: .primary, isDisabled: viewModel.isActing || !viewModel.isActionable) {
                        Task {
                            let didAccept = await viewModel.acceptInvite()
                            if didAccept {
                                if let onChanged {
                                    await onChanged()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8 + bottomActionPadding)
            }
        }
        .background(.ultraThinMaterial)
    }

    private func senderLine(for profile: UserProfile) -> String {
        let name = profile.displayName ?? profile.username
        return "\(name) shared this with you"
    }

}

private struct ProgramExerciseEditItem: Identifiable {
    let blockID: UUID
    let exerciseID: UUID

    var id: String { "\(blockID.uuidString)-\(exerciseID.uuidString)" }
}

private struct ProgramInviteDayCard: View {
    let block: PlanBlock
    let dayIndex: Int
    let dayCount: Int
    let onEditExercise: (PlanBlockExercise) -> Void
    let onDropOnBlock: (UUID, UUID) -> Void
    @Binding var draggedBlockID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("DAY \(dayIndex + 1)")
                    .dsFont(.caption2, weight: .bold)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Theme.accent, in: Capsule())

                Text(block.dayName)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            if block.isRestDay {
                Text("Rest day")
                    .dsFont(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
            } else {
                ForEach(Array(block.exercises.enumerated()), id: \.offset) { _, exercise in
                    Button {
                        onEditExercise(exercise)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.exerciseName)
                                    .dsFont(.subheadline, weight: .medium)
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                Text(detailText(for: exercise))
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                            Spacer()

                            Image(systemName: "slider.horizontal.3")
                                .dsFont(.caption, weight: .semibold)
                                .foregroundStyle(DS.Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .background(DS.Semantic.fillSubtle, in: ChamferedRectangle(.medium))
                    .overlay(
                        ChamferedRectangle(.medium)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onDrag {
            draggedBlockID = block.id
            return NSItemProvider(object: block.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: ProgramInviteDayDropDelegate(
                blockID: block.id,
                draggedBlockID: $draggedBlockID,
                onDropOnBlock: onDropOnBlock
            )
        )
        .onDisappear {
            if draggedBlockID == block.id {
                draggedBlockID = nil
            }
        }
    }

    private func detailText(for exercise: PlanBlockExercise) -> String {
        var parts = ["\(exercise.sets) sets", "\(exercise.reps) reps"]
        if let startingWeight = exercise.startingWeight, startingWeight > 0 {
            parts.append("\(startingWeight.formatted(.number.precision(.fractionLength(0...1)))) kg")
        }
        return parts.joined(separator: " • ")
    }
}

private struct ProgramInviteDayDropDelegate: DropDelegate {
    let blockID: UUID
    @Binding var draggedBlockID: UUID?
    let onDropOnBlock: (UUID, UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedBlockID = nil }

        if let draggedBlockID, draggedBlockID != blockID {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                onDropOnBlock(draggedBlockID, blockID)
            }
        }
        return true
    }

    func dropExited(info: DropInfo) {}

    func validateDrop(info: DropInfo) -> Bool {
        draggedBlockID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct ProgramExerciseEditSheet: View {
    struct Item: Identifiable {
        let exercise: PlanBlockExercise
        var id: UUID { exercise.id }
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_step_kg") private var weightStepKg: Double = 2.5
    @FocusState private var isWeightFocused: Bool

    let exercise: PlanBlockExercise

    @State private var sets: Int
    @State private var reps: Int
    @State private var startingWeight: Double

    init(exercise: PlanBlockExercise) {
        self.exercise = exercise
        self._sets = State(initialValue: exercise.sets)
        self._reps = State(initialValue: exercise.reps)
        self._startingWeight = State(initialValue: exercise.startingWeight ?? 0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.exerciseName)
                        .dsFont(.title3, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("Adjust the copy you will add to your library.")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    ProgramExerciseStepperRow(title: "Sets", value: $sets, range: 1...20)
                    ProgramExerciseStepperRow(title: "Reps", value: $reps, range: 1...100)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Starting Weight")
                            .dsFont(.caption, weight: .bold)
                            .tracking(0.8)
                            .foregroundStyle(DS.Theme.accent)

                        HStack(spacing: 10) {
                            Button {
                                startingWeight = max(0, startingWeight - weightStepKg)
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 42, height: 42)
                            }

                            TextField(
                                "0",
                                value: $startingWeight,
                                format: .number.precision(.fractionLength(0...1))
                            )
                            .focused($isWeightFocused)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .dsFont(.headline, weight: .semibold)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .padding(.vertical, 10)
                            .background(DS.Semantic.surface50.opacity(0.9), in: ChamferedRectangle(.medium))
                            .overlay(
                                ChamferedRectangle(.medium)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .overlay(alignment: .trailing) {
                                Text("kg")
                                    .dsFont(.caption, weight: .semibold)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                                    .padding(.trailing, 12)
                            }
                                .frame(maxWidth: .infinity)

                            Button {
                                startingWeight += weightStepKg
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 42, height: 42)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.Theme.accent)
                    }
                    .padding(14)
                    .background(DS.Semantic.surface50.opacity(0.65), in: ChamferedRectangle(.large))
                    .overlay(
                        ChamferedRectangle(.large)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }

                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isWeightFocused = false
                    }
            }
            .padding(16)
            .background(DS.Semantic.surface)
            .contentShape(Rectangle())
            .onTapGesture {
                isWeightFocused = false
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        exercise.sets = sets
                        exercise.reps = reps
                        exercise.startingWeight = startingWeight > 0 ? startingWeight : nil
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProgramExerciseStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(title)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Spacer()

            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .dsFont(.headline, weight: .semibold)
                    .foregroundStyle(DS.Theme.accent)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .fixedSize()
        }
        .padding(14)
        .background(DS.Semantic.surface50.opacity(0.65), in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ProgramInviteUnavailableCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DS.Semantic.warning.opacity(0.18))

                    Image(systemName: "exclamationmark.triangle.fill")
                        .dsFont(.headline, weight: .bold)
                        .foregroundStyle(DS.Semantic.warning)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite Unavailable")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(message)
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(DS.Semantic.warning.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct ProgramFooterButton: View {
    enum Kind {
        case primary
        case secondary
    }

    let title: String
    let kind: Kind
    let isDisabled: Bool
    let action: () -> Void

    init(_ title: String, kind: Kind, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(kind == .primary ? Color.black : DS.Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background, in: ChamferedRectangle(.large))
                .overlay(
                    ChamferedRectangle(.large)
                        .stroke(borderColor, lineWidth: 1)
                )
                .opacity(isDisabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var background: Color {
        switch kind {
        case .primary:
            return DS.Theme.accent
        case .secondary:
            return DS.Theme.accent.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return DS.Theme.accent.opacity(0.35)
        case .secondary:
            return DS.Theme.accent.opacity(0.22)
        }
    }
}

private struct ProgramActivationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    let split: WorkoutSplit
    let onActivated: () -> Void

    @State private var viewModel: ProgramActivationViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    Form {
                        Section("Schedule") {
                            DatePicker(
                                "Start Date",
                                selection: Binding(
                                    get: { viewModel.startDate },
                                    set: { viewModel.startDate = $0 }
                                ),
                                displayedComponents: .date
                            )
                        }

                        Section {
                            ForEach(split.planBlocks, id: \.id) { block in
                                Toggle(block.dayName, isOn: restDayBinding(for: block, viewModel: viewModel))
                            }
                        } header: {
                            Text("Days")
                        } footer: {
                            Text("Turn a day on if you want it to be a rest day before activation.")
                        }

                        Section("Starting Weights") {
                            ForEach(split.planBlocks.flatMap(\.exercises), id: \.id) { exercise in
                                HStack {
                                    Text(exercise.exerciseName)
                                    Spacer()
                                    TextField(
                                        "kg",
                                        value: startingWeightBinding(for: exercise, viewModel: viewModel),
                                        format: .number.precision(.fractionLength(0...1))
                                    )
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 72)
                                }
                            }
                        }
                    }
                    .alert("Activation Error", isPresented: activationErrorBinding(for: viewModel)) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(activationErrorMessage(for: viewModel))
                    }
                } else {
                    ProgressView("Preparing activation...")
                        .task {
                            if viewModel == nil {
                                viewModel = ProgramActivationViewModel(
                                    split: split,
                                    plannerStore: deps.plannerStore
                                )
                            }
                        }
                }
            }
            .navigationTitle("Activate Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Activate") {
                        guard let viewModel else { return }
                        if viewModel.activate(split: split) {
                            onActivated()
                            dismiss()
                        }
                    }
                    .disabled(viewModel?.isSaving == true)
                }
            }
        }
    }

    private func restDayBinding(
        for block: PlanBlock,
        viewModel: ProgramActivationViewModel
    ) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.restDayOverrides[block.id] ?? block.isRestDay
            },
            set: { isRestDay in
                viewModel.restDayOverrides[block.id] = isRestDay
            }
        )
    }

    private func startingWeightBinding(
        for exercise: PlanBlockExercise,
        viewModel: ProgramActivationViewModel
    ) -> Binding<Double> {
        Binding(
            get: {
                viewModel.startingWeights[exercise.id] ?? exercise.startingWeight ?? 0
            },
            set: { weight in
                viewModel.startingWeights[exercise.id] = weight
            }
        )
    }

    private func activationErrorBinding(
        for viewModel: ProgramActivationViewModel
    ) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.errorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func activationErrorMessage(
        for viewModel: ProgramActivationViewModel
    ) -> String {
        viewModel.errorMessage ?? "Unable to activate this program."
    }
}

private struct SentInvitesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    let split: WorkoutSplit

    @State private var invites: [ProgramInviteRow] = []
    @State private var profilesByID: [UUID: UserProfile] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading invites...")
                } else if invites.isEmpty {
                    ContentUnavailableView(
                        "No Sent Invites",
                        systemImage: "paperplane",
                        description: Text("Share this program to send a new invite batch.")
                    )
                } else {
                    List(invites, id: \.id) { invite in
                        HStack(spacing: 12) {
                            AvatarChip(profile: profilesByID[invite.recipientUserId])

                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayName(for: invite.recipientUserId))
                                    .dsFont(.subheadline, weight: .semibold)
                                Text(invite.status.rawValue.capitalized)
                                    .dsFont(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if invite.status == .pending {
                                Button("Revoke") {
                                    Task {
                                        await revoke(invite)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Sent Invites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await load()
            }
            .alert("Invite Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unable to load sent invites.")
            }
        }
    }

    private func load() async {
        guard
            let programID = split.lastSharedProgramID,
            let currentUserID = deps.authService.currentUser?.id
        else {
            invites = []
            isLoading = false
            return
        }

        do {
            invites = try await deps.programSharingRepository.fetchSentInvites(
                for: currentUserID,
                programId: programID
            )
            let recipientIds = invites.map(\.recipientUserId)
            let profiles = try await deps.profileRepository.fetchProfilesBatched(recipientIds)
            profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func revoke(_ invite: ProgramInviteRow) async {
        do {
            _ = try await deps.programSharingRepository.revoke(inviteId: invite.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func displayName(for userID: UUID) -> String {
        guard let profile = profilesByID[userID] else {
            return userID.uuidString
        }
        return profile.displayName ?? "@\(profile.username)"
    }
}

private struct AvatarChip: View {
    let profile: UserProfile?

    var body: some View {
        KFImage(profile?.avatarUrl.flatMap { URL(string: $0) })
            .placeholder {
                Circle()
                    .fill(DS.Semantic.brandSoft)
                    .overlay(
                        Text(initial)
                            .dsFont(.headline, weight: .bold)
                            .foregroundStyle(DS.Semantic.brand)
                    )
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFill()
            .frame(width: 40, height: 40)
            .clipShape(Circle())
    }

    private var initial: String {
        guard let profile else { return "?" }
        return String((profile.displayName ?? profile.username).prefix(1)).uppercased()
    }
}
