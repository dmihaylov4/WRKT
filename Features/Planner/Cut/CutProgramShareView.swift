//
//  CutProgramShareView.swift
//  WRKT
//
//  The share sheet ("form" kind) and its stacked all-friends sheet.
//

import SwiftUI

struct CutProgramShareView: View {
    let model: CutProgramShareModel
    @Binding var note: String
    var toggle: (UUID) -> Void = { _ in }
    var openAll: () -> Void = {}
    var retry: () -> Void = {}
    var send: () -> Void = {}
    var close: () -> Void = {}

    var body: some View {
        CutSheet(model.title, subtitle: model.subtitle, close: close) {
            VStack(alignment: .leading, spacing: 0) {
                CutPlannerLabel("Send to")
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 12)
                friendsRow.padding(.top, 10)
                if case .failed(let message) = model.friendsState {
                    HStack(spacing: 12) {
                        CutPlannerLine(message).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Try again", action: retry).buttonStyle(CutPillButtonStyle(.outline)).fixedSize()
                    }
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 10)
                } else if model.friendsState == .empty {
                    CutPlannerLine("No friends yet. Add friends to share programs.")
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 10)
                }
                VStack(alignment: .leading, spacing: 8) {
                    CutPlannerLabel("Note, optional")
                    CutPlannerField(prompt: "Add a note", text: $note, fill: DS.Cut.SheetLevel.base.control, axis: .vertical)
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 22)
            }
            .padding(.bottom, 26)
        } footer: {
            VStack(spacing: 10) {
                if let error = model.error {
                    CutPlannerLine(error, color: DS.Cut.Colors.destructive)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                Button(action: send) {
                    ZStack {
                        Text(model.sendTitle).opacity(model.sending ? 0 : 1)
                        if model.sending { ProgressView().tint(DS.Cut.Colors.ink) }
                    }
                }
                .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                // Grey until a friend is chosen; while sending it stays lime with a spinner.
                .disabled(!model.canSend && !model.sending)
                .allowsHitTesting(!model.sending)
                .accessibilityLabel(Text(model.sending ? "Sending" : model.sendTitle))
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var friendsRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                if model.friendsState == .loading {
                    ProgressView().tint(DS.Cut.Colors.textSecondary).frame(width: 60, height: 60).accessibilityLabel(Text("Loading friends"))
                }
                ForEach(model.picks) { pick in
                    Button { toggle(pick.id) } label: {
                        CutProgramSharePick(title: pick.friend.shortName, selected: pick.isSelected) {
                            CutCompeteAvatar(initials: pick.friend.initials, url: pick.friend.avatarURL, size: 60)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(pick.friend.name))
                    .accessibilityAddTraits(pick.isSelected ? .isSelected : [])
                }
                Button(action: openAll) {
                    CutProgramSharePick(title: "All", selected: false) {
                        Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .semibold))
                            .frame(width: 60, height: 60)
                            .overlay(Circle().strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1.5))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("All friends"))
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
        }
        .scrollIndicators(.hidden)
    }
}

/// One circle in the friends row with its first name beneath; chosen ones carry a lime ring.
private struct CutProgramSharePick<Circle_: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder var circle: () -> Circle_
    var body: some View {
        VStack(spacing: 6) {
            circle()
                .overlay { if selected { Circle().strokeBorder(DS.Cut.Colors.lime, lineWidth: 3) } }
            Text(title)
                .font(DS.Typography.custom(size: 15, weight: selected ? .bold : .medium, relativeTo: .subheadline))
                .foregroundStyle(selected ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: 64)
        .contentShape(Rectangle())
    }
}

/// Every friend, one step lighter than the share sheet beneath it. Taps add or remove a friend.
struct CutProgramFriendsView: View {
    let model: CutProgramFriendsModel
    @Binding var query: String
    var toggle: (UUID) -> Void = { _ in }
    var retry: () -> Void = {}
    var close: () -> Void = {}

    var body: some View {
        CutSheet("Send to", subtitle: model.selectedCount == 0 ? nil : "\(model.selectedCount) chosen", level: .stacked, close: close) {
            VStack(alignment: .leading, spacing: 0) {
                switch model.state {
                case .loading:
                    ProgressView().tint(DS.Cut.Colors.textSecondary).frame(maxWidth: .infinity, minHeight: 120).accessibilityLabel(Text("Loading friends"))
                case .failed(let error):
                    CutPlannerLine(error).padding(.top, 8)
                    Button("Try again", action: retry).buttonStyle(CutPillButtonStyle(.outline)).padding(.top, 14)
                case .empty:
                    CutPlannerLine("No friends yet. Add friends to share programs.").padding(.top, 8)
                case .noResults, .loaded:
                    CutSheetSearchField(prompt: "Search friends", query: $query).padding(.top, 6)
                    if model.state == .noResults {
                        CutPlannerLine("No friends match \u{201C}\(query)\u{201D}").padding(.top, 16)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { CutHairline() }
                            friendRow(row)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.bottom, 24)
        }
    }

    private func friendRow(_ row: CutProgramFriendsModel.Row) -> some View {
        Button { toggle(row.id) } label: {
            HStack(spacing: 14) {
                CutCompeteAvatar(initials: row.friend.initials, url: row.friend.avatarURL, size: 44)
                    .overlay { if row.isSelected { Circle().strokeBorder(DS.Cut.Colors.lime, lineWidth: 3) } }
                Text(row.friend.name)
                    .font(DS.Typography.custom(size: 18, weight: row.isSelected ? .bold : .semibold, relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.isSelected {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(DS.Cut.Colors.lime).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(row.friend.name))
        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
    }
}
