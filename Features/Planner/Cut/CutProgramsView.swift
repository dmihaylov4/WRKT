//
//  CutProgramsView.swift
//  WRKT
//
//  Programs: the title on the back button row with New, the active program as one lime card,
//  then From friends and Saved as open rows on the background, framed by hairlines at the gutter.
//

import SwiftUI

struct CutProgramsActions {
    var back: () -> Void = {}
    var new: () -> Void = {}
    var edit: () -> Void = {}
    var share: (UUID) -> Void = { _ in }
    var sentInvites: (UUID) -> Void = { _ in }
    var clearPlan: () -> Void = {}
    var use: (UUID) -> Void = { _ in }
    var openInvite: (UUID) -> Void = { _ in }
}

struct CutProgramsView: View {
    let model: CutProgramsModel
    var actions = CutProgramsActions()
    @Binding var confirmingClear: Bool

    init(model: CutProgramsModel, actions: CutProgramsActions = .init(), confirmingClear: Binding<Bool> = .constant(false)) {
        self.model = model
        self.actions = actions
        _confirmingClear = confirmingClear
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if model.loading {
                    ProgressView()
                        .tint(DS.Cut.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .accessibilityLabel(Text("Loading programs"))
                } else {
                    Group {
                        if let active = model.active {
                            CutActiveProgramCard(program: active, edit: actions.edit, share: { actions.share(active.id) },
                                                 sentInvites: { actions.sentInvites(active.id) }, clear: { confirmingClear = true })
                        } else if let prompt = model.prompt {
                            CutProgramsRowGroup { CutProgramsPromptRow(title: prompt.title, line: prompt.line, action: actions.new) }
                        }
                    }
                    .padding(.top, 20)
                    if !model.invites.isEmpty {
                        CutPanelHeader("From friends").padding(.top, 26)
                        CutProgramsRowGroup {
                            ForEach(Array(model.invites.enumerated()), id: \.element.id) { index, invite in
                                if index > 0 { CutHairline() }
                                CutProgramInviteRow(invite: invite) { actions.openInvite(invite.id) }
                            }
                        }
                        .padding(.top, 10)
                    }
                    if !model.saved.isEmpty {
                        CutPanelHeader("Saved").padding(.top, 26)
                        CutProgramsRowGroup {
                            ForEach(Array(model.saved.enumerated()), id: \.element.id) { index, program in
                                if index > 0 { CutHairline() }
                                CutSavedProgramRow(program: program, use: { actions.use(program.id) },
                                                   share: { actions.share(program.id) }, sentInvites: { actions.sentInvites(program.id) })
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 96, system: 76))
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .confirmationDialog(CutProgramsLogic.clearTitle, isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(CutProgramsLogic.clearButton, role: .destructive, action: actions.clearPlan)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CutProgramsLogic.clearMessage)
        }
    }

    private var header: some View {
        CutPlannerTopBar(leading: .back, action: actions.back) {
            Text("Programs")
                .font(DS.Cut.Typography.condensed(size: 34, relativeTo: .largeTitle))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button("New", action: actions.new)
                .buttonStyle(CutPillButtonStyle(.lime))
                .fixedSize()
                .accessibilityLabel(Text("New program"))
        }
    }
}

/// The active program: one lime cut-corner card with Edit, Share and a more menu holding Clear plan.
private struct CutActiveProgramCard: View {
    let program: CutProgramsModel.Program
    let edit: () -> Void
    let share: () -> Void
    let sentInvites: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your program")
                .font(DS.Typography.custom(size: 16, weight: .bold, relativeTo: .subheadline))
            CutPlannerTitle(program.name)
            Text(program.line)
                .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }
            .padding(.top, 14)
        }
        .foregroundStyle(DS.Cut.Colors.ink)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutCornerShape(corner: .bottomTrailing, cut: .points(DS.Cut.Metrics.cardCut)).fill(DS.Cut.Colors.lime))
        .environment(\.cutSurface, .lime)
        .padding(.horizontal, DS.Cut.Metrics.panelInset)
    }

    @ViewBuilder private var buttons: some View {
        Button("Edit", action: edit)
            .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
            .fixedSize()
            .accessibilityLabel(Text("Edit \(program.name)"))
        Button("Share", action: share)
            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            .fixedSize()
            .accessibilityLabel(Text("Share \(program.name)"))
        Menu {
            if program.showsSentInvites {
                Button("Sent invites", systemImage: "paperplane", action: sentInvites)
            }
            Button("Clear plan", systemImage: "calendar.badge.minus", role: .destructive, action: clear)
        } label: {
            CutPlannerMoreLabel(tone: .ink)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More for \(program.name)"))
    }
}

/// One group of rows on the background: a hairline above the first row and one below the last,
/// with rows and hairlines on the same gutter as the section headers. Rows add their own
/// hairlines between them.
private struct CutProgramsRowGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutHairline()
            content
            CutHairline()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
    }
}

/// No program running: a calm prompt that leads to New.
private struct CutProgramsPromptRow: View {
    let title: String
    let line: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    CutPlannerRowTitle(title)
                    CutPlannerLine(line)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A program a friend sent: avatar, program name, sender, and a white View pill.
private struct CutProgramInviteRow: View {
    let invite: CutProgramsModel.Invite
    let view: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 12) {
                CutCompeteAvatar(initials: invite.initials, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    CutPlannerRowTitle(invite.programName)
                    CutPlannerLine(invite.line)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(invite.spoken))
            Button("View", action: view)
                .buttonStyle(CutPillButtonStyle(.white))
                .fixedSize()
                .accessibilityLabel(Text("View \(invite.programName)"))
        }
        .padding(.vertical, 14)
    }
}

/// A saved program: name, one line, a lime outline Use pill and a more menu.
private struct CutSavedProgramRow: View {
    let program: CutProgramsModel.Program
    let use: () -> Void
    let share: () -> Void
    let sentInvites: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                CutPlannerRowTitle(program.name)
                CutPlannerLine(program.line)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // No spacing: the open dots sit at the trailing edge of their 44 pt target, so its empty
            // leading part keeps the same visible gap to Use as the round button had.
            HStack(spacing: 0) {
                Button("Use", action: use)
                    .buttonStyle(CutPillButtonStyle(.outlineLime))
                    .fixedSize()
                    .accessibilityLabel(Text("Use \(program.name)"))
                Menu {
                    Button("Share", systemImage: "square.and.arrow.up", action: share)
                    if program.showsSentInvites {
                        Button("Sent invites", systemImage: "paperplane", action: sentInvites)
                    }
                } label: {
                    CutPlannerMoreLabel(tone: .open)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel(Text("More for \(program.name)"))
            }
        }
        .padding(.vertical, 14)
    }
}
