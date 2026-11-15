import SwiftUI

struct CutCompeteActions {
    var open: (CutCompeteItem.Target) -> Void = { _ in }
    var accept: (UUID) -> Void = { _ in }
    var decline: (UUID) -> Void = { _ in }
    var startBattle: () -> Void = {}
    var browse: () -> Void = {}
    var allPending: () -> Void = {}
    var retry: () -> Void = {}
}
struct CutCompeteView: View {
    let model: CutCompeteModel
    var processing: Set<UUID> = []
    var actions = CutCompeteActions()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.loading { ProgressView().accessibilityLabel("Loading competitions").padding(.vertical, 20) }
                if let error = model.error {
                    Text(error).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).padding(.vertical, 12)
                    Button("Try Again", action: actions.retry).buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
                }
                if !model.pending.isEmpty {
                    CutCompeteSectionTitle("Invitations")
                    items(model.pending)
                    if model.pendingCount > 3 {
                        Button("All invitations (\(model.pendingCount))", action: actions.allPending)
                            .font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).frame(minHeight: 50).buttonStyle(.plain)
                    }
                }
                if !model.active.isEmpty { CutCompeteSectionTitle("Active"); items(model.active) }
                CutCompeteSectionTitle("Start competing")
                Button(action: actions.startBattle) { CutCompeteNavigationRow("Start Battle") }.buttonStyle(.plain).disabled(model.loading)
                Button(action: actions.browse) { CutCompeteNavigationRow("Join Challenge") }.buttonStyle(.plain)
                if !model.recommended.isEmpty { CutCompeteSectionTitle("Recommended"); items(model.recommended)
                    Button("All challenges", action: actions.browse).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).frame(minHeight: 50).buttonStyle(.plain)
                }
                if !model.completed.isEmpty { CutCompeteSectionTitle("Recent completions"); items(model.completed) }
                if !model.summary.isEmpty {
                    DisclosureGroup { ForEach(model.summary) { CutCompeteValueRow(label: $0.label, value: $0.value) } }
                    label: { CutCompeteDisclosureLabel("Summary") }.tint(DS.Cut.Colors.textSecondary).padding(.top, 20)
                }
            }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.bottom, DS.Redesign.tabBarClearance(legacy: 60, system: 40))
        }.foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
    }
    private func items(_ items: [CutCompeteItem]) -> some View {
        ForEach(items) { item in
            CutCompeteItemRow(item: item, processing: item.battleID.map { processing.contains($0) } ?? false,
                              open: { actions.open(item.id) }, accept: { if let id = item.battleID { actions.accept(id) } },
                              decline: { if let id = item.battleID { actions.decline(id) } })
        }
    }
}
extension CutCompeteItem {
    var battleID: UUID? { if case .battle(let id) = id { id } else { nil } }
}

struct CutCompeteItemRow: View {
    let item: CutCompeteItem
    var processing = false
    var open: () -> Void = {}
    var accept: () -> Void = {}
    var decline: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                            Text(item.subtitle).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if !dynamicTypeSize.isAccessibilitySize { rewardPreview }
                        Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(DS.Cut.Colors.textSecondary).accessibilityHidden(true)
                    }
                    if let value = item.value { Text(value).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).monospacedDigit() }
                    if let trailing = item.trailing { Text(trailing).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary) }
                    if let note = item.note { Text(note).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2) }
                    if let fraction = item.fraction {
                        CutSplitBar(fraction: fraction).accessibilityLabel(item.battleID == nil ? "Challenge progress" : "Score comparison")
                            .accessibilityValue(item.progressLabel ?? "")
                    }
                    if let reward = item.reward { Text(reward).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary) }
                }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if item.incoming {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { acceptButton; declineButton }
                    VStack(alignment: .leading, spacing: 12) { acceptButton; declineButton }
                }
            }
            CutHairline()
        }.padding(.vertical, 12)
    }
    @ViewBuilder private var rewardPreview: some View {
        if let tier = item.plateTier {
            PlateFaceView(tierID: tier, progressionTier: .iron, liftTypeID: nil, weightKg: item.battleID == nil ? 20 : 35)
                .frame(width: 32, height: 32).clipped().accessibilityHidden(true)
        } else if let id = item.barSkinID, let skin = BarSkin.all.first(where: { $0.id == id }) {
            BarSkinPreviewTile(skin: skin).frame(width: 48, height: 20).accessibilityHidden(true)
        }
    }
    private var acceptButton: some View {
        Button(action: accept) { ZStack { Text("Accept").opacity(processing ? 0 : 1); if processing { ProgressView().tint(DS.Cut.Colors.ink) } } }
            .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false)).disabled(processing).accessibilityLabel("Accept")
    }
    private var declineButton: some View { Button("Decline", role: .destructive, action: decline).buttonStyle(CutCompeteDestructiveStyle()).disabled(processing) }
}

struct CutCompeteSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased()).font(DS.Cut.Typography.condensed(size: 23, relativeTo: .title3))
            .foregroundStyle(DS.Cut.Colors.textPrimary).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader).padding(.top, 20).padding(.bottom, 10)
    }
}
struct CutCompeteValueRow: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { labelText; valueText }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) { labelText; Spacer(minLength: 12); valueText.multilineTextAlignment(.trailing) }.frame(minHeight: 50)
            }
            CutHairline()
        }
    }
    private var labelText: some View { Text(label).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).foregroundStyle(DS.Cut.Colors.textSecondary) }
    private var valueText: some View { Text(value).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).monospacedDigit().fixedSize(horizontal: false, vertical: true) }
}
struct CutCompeteNavigationRow: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) { Text(title).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 15)) }
                .frame(minHeight: 50).contentShape(Rectangle())
            CutHairline()
        }
    }
}
struct CutCompeteDestructiveStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).padding(.horizontal, 20).padding(.vertical, 10).frame(minHeight: 44)
            .foregroundStyle(DS.Status.error).overlay(Capsule().stroke(DS.Status.error.opacity(0.6)))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
    }
}

struct CutCompeteDisclosureLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
            .foregroundStyle(DS.Cut.Colors.textPrimary).frame(minHeight: 50, alignment: .leading)
    }
}
