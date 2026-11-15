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
        VStack(spacing: 0) {
            CutExerciseSearchField(text: searchText, change: actions.search, cancel: {
                actions.search("")
                searchFocused = false
            }, isFocused: $searchFocused)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            CutExerciseTabs(items: CutExercisePickerModel.Region.allCases, selection: model.region,
                             title: \.rawValue, select: actions.region)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
            ScrollView {
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
                        ProgressView("Loading more exercises")
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .onAppear(perform: actions.loadMore)
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .navigationTitle("Add Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ADD EXERCISE").font(DS.Cut.Typography.condensed(size: 22, relativeTo: .headline))
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: actions.cancel).cutFont(.title).tint(DS.Cut.Colors.textPrimary)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }.cutFont(.title)
            }
        }
        .shellNavigationBarBackground(DS.Cut.Colors.background)
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
                TextField("Search exercises", text: Binding(get: { text }, set: change))
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
