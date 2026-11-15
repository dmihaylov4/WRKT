import SwiftUI

struct CutExerciseBrowserActions {
    var search: (String) -> Void = { _ in }
    var toggleSearch: () -> Void = {}
    var cancelSearch: () -> Void = {}
    var toggleFilters: () -> Void = {}
    var muscle: (String?) -> Void = { _ in }
    var equipment: (EquipBucket) -> Void = { _ in }
    var movement: (MoveBucket) -> Void = { _ in }
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
    var filtersExpanded = false
    var expandedSuggestions: Set<String> = []
    var tutorial: CutExerciseTutorialModel?
    var actions = CutExerciseBrowserActions()
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if model.filters.isSearching {
                    CutExerciseSearchField(text: searchText, change: actions.search,
                                           cancel: actions.cancelSearch, isFocused: $searchFocused, cancelTitle: "Cancel")
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                } else {
                    filters
                }
                CutHairline()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if model.rows.isEmpty {
                            CutExerciseEmptyView(title: "No exercises found", message: model.emptyMessage, clear: actions.clear)
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
                        .frame(width: 44, height: 44)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { actions.frame(.create, $0) }
                }
            }
        }
        .shellNavigationBarBackground(DS.Cut.Colors.background)
        .onChange(of: model.filters.isSearching) { _, searching in searchFocused = searching }
    }

    private var filters: some View {
        VStack(spacing: 0) {
            if !model.muscles.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        CutExerciseFilterChip(title: "All", selected: model.filters.muscle == nil) { actions.muscle(nil) }
                        ForEach(model.muscles, id: \.self) { muscle in
                            CutExerciseFilterChip(title: muscle, selected: model.filters.muscle == muscle) {
                                actions.muscle(model.filters.muscle == muscle ? nil : muscle)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                }
                .scrollIndicators(.hidden)
                .padding(.top, 8)
            }
            Button(action: actions.toggleFilters) {
                HStack(spacing: 6) {
                    Text(model.activeFilterCount == 0 ? "More Filters" : "More Filters (\(model.activeFilterCount))")
                    Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                }
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if filtersExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    filterRow(title: "Equipment", values: EquipBucket.allCases, selected: model.filters.equipment,
                              target: .equipment, select: actions.equipment)
                    filterRow(title: "Movement", values: MoveBucket.allCases, selected: model.filters.movement,
                              target: .movement, select: actions.movement)
                }
                .padding(.bottom, 14)
            }
        }
    }

    private func filterRow<T: Hashable & RawRepresentable>(title: String, values: [T], selected: T,
                        target: CutExerciseTutorialFrames.Target, select: @escaping (T) -> Void) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        CutExerciseFilterChip(title: value.rawValue, selected: value == selected,
                                              action: { select(value == selected ? values[0] : value) },
                                              clear: { select(values[0]) })
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
            }
            .scrollIndicators(.hidden)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { actions.frame(target, $0) }
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

struct CutExerciseFilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var clear: (() -> Void)?
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
        .simultaneousGesture(TapGesture(count: 2).onEnded { clear?() })
    }
}

struct CutExerciseEmptyView: View {
    let title: String
    let message: String
    var clear: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title2))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
            Text(message).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let clear {
                Button("Clear Filters", action: clear)
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
                        Text("\(model.index + 1) of 4").cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                        HStack(spacing: 12) {
                            Button("Skip", action: skip).buttonStyle(CutSecondaryButtonStyle(size: .compact))
                            Button(model.index == 3 ? "Got it" : "Next", action: next)
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
