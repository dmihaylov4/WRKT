import SwiftUI

struct CutExerciseBrowserActions {
    var search: (String) -> Void = { _ in }
    var toggleSearch: () -> Void = {}
    var cancelSearch: () -> Void = {}
    var select: (CutExerciseFilterMenu.Kind, String?) -> Void = { _, _ in }
    var clear: () -> Void = {}
    var open: (String) -> Void = { _ in }
    var favorite: (String) -> Void = { _ in }
    var create: () -> Void = {}
    var toggleSuggestion: (String) -> Void = { _ in }
    var showAll: (String) -> Void = { _ in }
    var frame: (CutExerciseTutorialFrames.Target, CGRect) -> Void = { _, _ in }
    var nextTip: () -> Void = {}
    var skipTips: () -> Void = {}
}

struct CutExerciseBrowserView: View {
    let model: CutExerciseBrowserModel
    var searchText = ""
    var expandedSuggestions: Set<String> = []
    var tutorial: CutExerciseTutorialModel?
    var actions = CutExerciseBrowserActions()
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if model.filters.isSearching {
                    CutExerciseSearchField(text: searchText, change: actions.search,
                                           cancel: actions.cancelSearch, isFocused: $searchFocused, cancelTitle: "Cancel")
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                } else {
                    // The tutorial spotlights the pills themselves, so measure before padding.
                    CutExerciseFilterBar(menus: model.menus, select: actions.select)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { actions.frame(.filters, $0) }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    if model.showsCount {
                        countLine
                    }
                }
                CutHairline()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if model.rows.isEmpty {
                            // A filtered empty list already has Clear filters in the count line above.
                            CutExerciseEmptyView(title: "No exercises found", message: model.emptyMessage,
                                                 clear: model.emptyState == .search ? actions.clear : nil, clearTitle: "Clear search")
                            ForEach(model.suggestions) { suggestion in
                                suggestionRows(suggestion)
                            }
                        } else {
                            ForEach(model.rows) { row in
                                CutExerciseRowView(row: row, open: { actions.open(row.id) },
                                                   favorite: { actions.favorite(row.id) })
                            }
                        }
                    }
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.bottom, 24)
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.rows.map(\.id))
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { actions.frame(.list, $0) }
                .scrollDismissesKeyboard(.interactively)
            }
            if let tutorial {
                CutExerciseTutorialView(model: tutorial, next: actions.nextTip, skip: actions.skipTips)
            }
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.title.uppercased())
                    .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .headline))
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if !model.filters.isSearching {
                        Button("Search exercises", systemImage: "magnifyingglass", action: actions.toggleSearch)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    Button("Create custom exercise", systemImage: "plus", action: actions.create)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(DS.Cut.Colors.lime)
                        .tint(DS.Cut.Colors.lime)
                        .frame(width: 44, height: 44)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { actions.frame(.create, $0) }
                }
            }
        }
        .shellNavigationBarBackground(DS.Cut.Colors.background)
        .onChange(of: model.filters.isSearching) { _, searching in searchFocused = searching }
    }

    private var countLine: some View {
        // At accessibility sizes the count and the button stack instead of wrapping word by word.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(model.countText).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                .contentTransition(.numericText())
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if model.showsClearFilters {
                Button("Clear filters", action: actions.clear)
                    .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                    .foregroundStyle(DS.Cut.Colors.lime)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 2)
    }

    @ViewBuilder private func suggestionRows(_ suggestion: CutExerciseSuggestionModel) -> some View {
        Button { actions.toggleSuggestion(suggestion.muscle) } label: {
            CutHairlineRow("Found in \(suggestion.muscle)", value: "\(suggestion.totalCount)",
                           subtitle: suggestion.region, showsChevron: true)
        }
        .buttonStyle(.plain)
        if expandedSuggestions.contains(suggestion.muscle) {
            ForEach(suggestion.rows) { row in
                CutExerciseRowView(row: row, open: { actions.open(row.id) })
            }
            if suggestion.totalCount > suggestion.rows.count {
                Button("+ \(suggestion.totalCount - suggestion.rows.count) more") { actions.showAll(suggestion.muscle) }
                    .cutFont(.title)
                    .foregroundStyle(DS.Cut.Colors.lime)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                CutHairline()
            }
        }
    }
}

/// Batch-local pieces: shared by the browser and picker, with no stores or navigation.
struct CutExerciseRowView: View {
    let row: CutExerciseRowModel
    let open: () -> Void
    var favorite: (() -> Void)?
    var showsAdd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).cutFont(.title).foregroundStyle(DS.Cut.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !row.detail.isEmpty {
                                Text(row.detail).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        if showsAdd {
                            Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(DS.Cut.Colors.lime)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let favorite {
                    Button(action: favorite) { heart }
                        .buttonStyle(.plain)
                        .accessibilityLabel(row.isFavorite ? "Remove \(row.name) from favorites" : "Favorite \(row.name)")
                        .accessibilityAddTraits(row.isFavorite ? .isSelected : [])
                } else if row.isFavorite {
                    heart.accessibilityLabel("Favorite")
                }
            }
            CutHairline()
        }
    }

    private var heart: some View {
        Image(systemName: row.isFavorite ? "heart.fill" : "heart")
            .font(.system(size: 18))
            .foregroundStyle(row.isFavorite ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
            .frame(width: 44, height: 44)
    }
}

/// One row of equal width pills, each opening a system menu. At accessibility text sizes the
/// pills stack full width instead of truncating their labels to nothing.
struct CutExerciseFilterBar: View {
    let menus: [CutExerciseFilterMenu]
    let select: (CutExerciseFilterMenu.Kind, String?) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            ForEach(menus) { menu in
                CutExerciseFilterPill(menu: menu) { select(menu.kind, $0) }
            }
        }
    }
}

struct CutExerciseFilterPill: View {
    let menu: CutExerciseFilterMenu
    let select: (String?) -> Void

    var body: some View {
        Menu {
            Picker(menu.groupName, selection: Binding(get: { menu.selection }, set: { option in
                guard option != menu.selection else { return }
                Haptics.light()
                select(option)
            })) {
                Text(menu.anyTitle).tag(String?.none)
                ForEach(menu.options, id: \.self) { option in
                    Text(option).tag(Optional(option))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(menu.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(.footnote, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(DS.Cut.Typography.font(.buttonCompact).weight(menu.isActive ? .bold : .semibold))
            .foregroundStyle(menu.isActive ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(menu.isActive ? DS.Cut.Colors.lime : .clear))
            .overlay(Capsule().strokeBorder(menu.isActive ? .clear : DS.Cut.Colors.hairlineStrong, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(menu.groupName)
        .accessibilityValue(menu.selection ?? menu.anyTitle)
        .accessibilityHint("Opens a menu to filter by \(menu.groupName.lowercased())")
    }
}

/// Used by the create exercise form. The browser's filters are menu pills instead.
struct CutExerciseFilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).cutFont(.secondary)
                .foregroundStyle(selected ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(selected ? DS.Cut.Colors.lime : .clear, in: CutCornerShape(cut: .points(8)))
                .overlay(CutCornerShape(cut: .points(8)).stroke(selected ? .clear : DS.Cut.Colors.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CutExerciseEmptyView: View {
    let title: String
    let message: String
    var clear: (() -> Void)?
    var clearTitle = "Clear Filters"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title2))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
            Text(message).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let clear {
                Button(clearTitle, action: clear)
                    .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 32)
    }
}

struct CutExerciseTutorialView: View {
    let model: CutExerciseTutorialModel
    let next: () -> Void
    let skip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let target = model.frame.map { $0.offsetBy(dx: -origin.x, dy: -origin.y).intersection(CGRect(origin: .zero, size: proxy.size)) }
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    if let target, !target.isNull { path.addRect(target) }
                }
                .fill(.black.opacity(0.85), style: FillStyle(eoFill: true))
                if let target, !target.isNull {
                    Rectangle().stroke(DS.Cut.Colors.lime, lineWidth: 2)
                        .frame(width: target.width, height: target.height)
                        .position(x: target.midX, y: target.midY)
                        .allowsHitTesting(false)
                }
                VStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 14) {
                        CutHairline()
                        Text(model.title.uppercased())
                            .font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title2))
                        Text(model.message).cutFont(.body).fixedSize(horizontal: false, vertical: true)
                        Text("\(model.index + 1) of \(model.count)").cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                        HStack(spacing: 12) {
                            Button("Skip", action: skip).buttonStyle(CutSecondaryButtonStyle(size: .compact))
                            Button(model.isLast ? "Got it" : "Next", action: next)
                                .buttonStyle(CutPrimaryButtonStyle(size: .compact))
                        }
                    }
                    .padding(20)
                    .background(DS.Cut.Colors.background)
                }
                .padding(20)
            }
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(.isModal)
    }
}
