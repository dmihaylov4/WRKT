import SwiftUI

struct WhatsNewView: View {
    let release: WhatsNewRelease
    let currentVersion: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("VERSION \(currentVersion)")
                    .font(DS.Typography.font(.caption, weight: .bold))
                    .foregroundStyle(DS.Semantic.brand)
                    .tracking(1.1)

                Text("What's New")
                    .font(DS.Typography.font(.title2, weight: .bold))
                    .foregroundStyle(DS.Semantic.textPrimary)
            }
            .padding(.bottom, 24)

            Text(release.title)
                .font(DS.Typography.font(.headline, weight: .semibold))
                .foregroundStyle(DS.Semantic.textPrimary)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(release.bullets.enumerated()), id: \.offset) { _, bullet in
                    Rectangle()
                        .fill(DS.Semantic.border)
                        .frame(height: 1)

                    Text(bullet)
                        .font(DS.Typography.font(.body, weight: .regular))
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .padding(.vertical, 12)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Text("Got it")
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .font(DS.ButtonSize.large.font)
                    .foregroundStyle(.black)
            }
            .background(DS.Semantic.brand, in: ChamferedRectangle(.large))
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(DS.Semantic.surface.ignoresSafeArea())
    }
}

