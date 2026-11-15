//
//  CutProgramPreviewView.swift
//  WRKT
//
//  A program a friend sent. The back row carries the sender; the days sit in one panel; the
//  actions sit at the bottom with room between them.
//

import SwiftUI
import UniformTypeIdentifiers

struct CutProgramPreviewActions {
    var back: () -> Void = {}
    var openDay: (UUID) -> Void = { _ in }
    var moveDay: (_ source: UUID, _ target: UUID) -> Void = { _, _ in }
    var start: () -> Void = {}
    var save: () -> Void = {}
    var decline: () -> Void = {}
    var done: () -> Void = {}
}

enum CutProgramPreviewOperation: Equatable { case start, save, decline }

struct CutProgramPreviewView: View {
    let model: CutProgramPreviewModel
    var operation: CutProgramPreviewOperation? = nil
    var bottomPadding: CGFloat = 0
    var actions = CutProgramPreviewActions()
    @State private var dragged: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                switch model.phase {
                case .loading:
                    ProgressView().tint(DS.Cut.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .accessibilityLabel(Text("Loading program"))
                case .unavailable(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        CutPlannerTitle(model.title)
                        CutPlannerLine(message, size: 17)
                    }
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 20)
                case .invite, .saved:
                    content
                    // At accessibility sizes the actions scroll with the days instead of covering them.
                    if dynamicTypeSize.isAccessibilitySize { footer.padding(.top, 24) }
                }
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            switch model.phase {
            case .invite, .saved: if !dynamicTypeSize.isAccessibilitySize { footer }
            case .loading, .unavailable: EmptyView()
            }
        }
    }

    private var topBar: some View {
        CutPlannerTopBar(leading: .back, action: actions.back) {
            if let sender = model.sender {
                HStack(spacing: 12) {
                    CutCompeteAvatar(initials: sender.initials, url: sender.avatarURL, size: 40)
                    (Text("Sent by ").foregroundStyle(DS.Cut.Colors.textSecondary)
                     + Text(sender.name).foregroundStyle(DS.Cut.Colors.textPrimary).fontWeight(.bold))
                        .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                CutPlannerTitle(model.title)
                if let line = model.line {
                    CutPlannerLine(line, color: DS.Cut.Colors.lime, size: 18)
                }
                if let note = model.note {
                    Text(note)
                        .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 20)
            CutPanel {
                ForEach(Array(model.days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 { CutHairline() }
                    dayRow(day)
                }
            }
            .padding(.top, 20)
            if let hint = model.hint {
                CutPlannerLine(hint)
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 12)
            }
        }
    }

    private func dayRow(_ day: CutProgramPreviewModel.Day) -> some View {
        Button { actions.openDay(day.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                layout {
                    CutPlannerRowTitle(day.title, color: day.isRest ? DS.Cut.Colors.textSecondary : DS.Cut.Colors.textPrimary)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
                    if let count = day.count { CutPlannerLine(count) }
                }
                if let line = day.line { CutPlannerLine(line) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(day.isRest ? Text("") : Text("Opens its exercises"))
        .onDrag {
            dragged = day.id
            return NSItemProvider(object: day.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: CutProgramDayDrop(target: day.id, dragged: $dragged, move: actions.moveDay))
    }

    private var footer: some View {
        VStack(spacing: 18) {
            if let error = model.error {
                CutPlannerLine(error, color: DS.Cut.Colors.destructive)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Button(action: actions.start) { busyLabel("Start this program", busy: operation == .start, tint: DS.Cut.Colors.ink) }
                .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                .disabled(model.acting && operation != .start)
                .allowsHitTesting(!model.acting)
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))
            layout {
                if model.phase == .saved {
                    Button("Done", action: actions.done)
                        .buttonStyle(CutPillButtonStyle(.outline, size: .compact, fillsWidth: true))
                        .disabled(model.acting)
                } else {
                    Button(action: actions.save) { busyLabel("Save for later", busy: operation == .save, tint: DS.Cut.Colors.textPrimary) }
                        .buttonStyle(CutPillButtonStyle(.outline, size: .compact, fillsWidth: true))
                        .disabled(model.acting && operation != .save)
                        .allowsHitTesting(!model.acting)
                    Button(action: actions.decline) { busyLabel("Decline", busy: operation == .decline, tint: DS.Cut.Colors.destructive) }
                        .buttonStyle(CutQuietButtonStyle())
                        .disabled(model.acting && operation != .decline)
                        .allowsHitTesting(!model.acting)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12 + bottomPadding)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .overlay(alignment: .top) { CutHairline() }
    }

    private func busyLabel(_ title: String, busy: Bool, tint: Color) -> some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy { ProgressView().tint(tint) }
        }
        .accessibilityLabel(Text(busy ? "Working" : title))
    }
}

private struct CutProgramDayDrop: DropDelegate {
    let target: UUID
    @Binding var dragged: UUID?
    let move: (UUID, UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        defer { dragged = nil }
        if let dragged, dragged != target {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) { move(dragged, target) }
        }
        return true
    }
    func validateDrop(info: DropInfo) -> Bool { dragged != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

/// One day's exercises, opened from the preview. Tapping an exercise opens its edit sheet on top.
struct CutProgramDaySheetView: View {
    let model: CutProgramPreviewLogic.DaySheet
    var edit: (UUID) -> Void = { _ in }
    var close: () -> Void = {}

    var body: some View {
        CutSheet(model.title, subtitle: "Tap an exercise to change it.", close: close) {
            VStack(spacing: 0) {
                if model.rows.isEmpty {
                    CutPlannerLine("No exercises on this day.", size: 17)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { CutHairline() }
                    Button { edit(row.id) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                CutPlannerRowTitle(row.name)
                                CutPlannerLine(row.line)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.bottom, 24)
        }
    }
}
