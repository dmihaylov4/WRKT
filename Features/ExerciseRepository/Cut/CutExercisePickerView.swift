import SwiftUI

struct CutExercisePickerActions {
    var search: (String) -> Void = { _ in }
    var region: (CutExercisePickerModel.Region) -> Void = { _ in }
    var select: (String) -> Void = { _ in }
    var loadMore: () -> Void = {}
    var cancel: () -> Void = {}
}

struct CutExercisePickerView: View {
    let model: CutExercisePickerModel
    var searchText = ""
    var actions = CutExercisePickerActions()
    @FocusState private var searchFocused: Bool

    var body: some View {
        CutSheet("Add exercise", kind: .browser, close: actions.cancel) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Search exercises", text: Binding(get: { searchText }, set: actions.search))
                        .autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.search).focused($searchFocused)
                    if !searchText.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { actions.search(""); searchFocused = false }
                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    }
                }
                .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                .padding(.horizontal, 16).frame(minHeight: 48)
                .background(Capsule().fill(level.control)).padding(.vertical, 12)
                ViewThatFits(in: .horizontal) {
                    regions(vertical: false)
                    regions(vertical: true)
                }
                .padding(.bottom, 12)
                LazyVStack(spacing: 0) {
                    if model.rows.isEmpty {
                        CutExerciseEmptyView(title: "No exercises found",
                            message: model.isLibraryEmpty ? "No exercises are available yet." : "Try another search or region.")
                    }
                    ForEach(model.rows) { row in
                        CutExerciseRowView(row: row, open: { actions.select(row.id) }, showsAdd: true)
                            .onAppear { if row.id == model.rows.last?.id && model.hasMore { actions.loadMore() } }
                    }
                    if model.hasMore {
                        ProgressView("Loading more exercises").cutFont(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 56).onAppear(perform: actions.loadMore)
                    }
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.bottom, 24)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }.cutFont(.title)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @Environment(\.cutSheetDepth) private var sheetDepth
    private var level: DS.Cut.SheetLevel { .resolve(parentDepth: sheetDepth) }
    private func regions(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(CutExercisePickerModel.Region.allCases, id: \.self) { region in
                Button { actions.region(region); Haptics.light() } label: {
                    Text(region.rawValue).font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .foregroundStyle(region == model.region ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
                        .background(Capsule().fill(region == model.region ? DS.Cut.Colors.textPrimary : level.control))
                }.buttonStyle(.plain).accessibilityAddTraits(region == model.region ? .isSelected : [])
            }
        }
    }

}

struct CutExerciseSearchField: View {
    let text: String
    let change: (String) -> Void
    let cancel: () -> Void
    let isFocused: FocusState<Bool>.Binding
    var cancelTitle: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 17))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                TextField("Search exercises", text: Binding(get: { text }, set: change),
                          prompt: Text("Search exercises").foregroundStyle(DS.Cut.Colors.textSecondary))
                    .cutFont(.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused(isFocused)
                if let cancelTitle {
                    Button(cancelTitle, action: cancel).cutFont(.secondary)
                        .frame(minHeight: 44)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                } else {
                    Button("Clear search", systemImage: "xmark", action: cancel)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 15))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .opacity(text.isEmpty ? 0 : 1)
                        .disabled(text.isEmpty)
                }
            }
            .frame(minHeight: 52)
            CutHairline()
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
    }
}

/// Batch-local tabs keep full labels at large text sizes instead of shrinking or
/// truncating them. The same underline treatment scrolls only when it cannot fit.
struct CutExerciseTabs<Item: Hashable>: View {
    let items: [Item]
    let selection: Item
    let title: (Item) -> String
    let select: (Item) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                row(stretch: true)
                ScrollView(.horizontal) { row(stretch: false) }
                    .scrollIndicators(.hidden)
            }
            CutHairline()
        }
    }

    private func row(stretch: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    guard item != selection else { return }
                    Haptics.light()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { select(item) }
                } label: {
                    VStack(spacing: 10) {
                        Text(title(item)).cutFont(.title)
                            .foregroundStyle(item == selection ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: true, vertical: true)
                        SlantedSegmentShape().fill(item == selection ? DS.Cut.Colors.lime : .clear).frame(height: 6)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: stretch ? .infinity : nil, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == selection ? .isSelected : [])
            }
        }
    }
}
