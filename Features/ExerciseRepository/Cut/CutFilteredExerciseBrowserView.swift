import SwiftUI

struct CutFilteredExerciseBrowserView: View {
    let model: CutFilteredExerciseBrowserModel
    let select: (String) -> Void
    let done: () -> Void
    var body: some View {
        CutSheet(model.title, kind: .browser, close: done) {
            VStack(spacing: 0) {
                CutHairline()
                ForEach(model.subregions, id: \.self) { subregion in
                    Button { select(subregion) } label: {
                        HStack(spacing: 12) {
                            Text(subregion).font(DS.Typography.custom(size: 18, weight: .semibold, relativeTo: .body))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Cut.Colors.textSecondary).accessibilityHidden(true)
                        }.frame(minHeight: 60).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    CutHairline()
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 12).padding(.bottom, 24)
        }
    }
}
