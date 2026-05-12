import SwiftUI

struct WorkoutPostHeroSummaryCard: View {
    let summary: WorkoutPostSummaryPresentation
    let context: WorkoutPostHeroSummaryContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHARED WORKOUT")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(DS.Semantic.textSecondary)
                    Text(summary.title)
                        .dsFont(.title3, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 8)

                if let badge = summary.badge {
                    Text(badge.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(DS.Semantic.brand, in: Capsule())
                        .accessibilityLabel(badge)
                }
            }

            Spacer(minLength: 22)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(summary.stats.prefix(4)) { stat in
                    WorkoutPostHeroStatColumn(stat: stat)
                    if stat.id != summary.stats.prefix(4).last?.id {
                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(width: 1, height: 42)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 22)

            VStack(alignment: .leading, spacing: 10) {
                if !summary.biometrics.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(summary.biometrics, id: \.self) { metric in
                            Label(metric, systemImage: metric.contains("BPM") ? "heart.fill" : "flame.fill")
                                .dsFont(.caption, weight: .bold)
                                .foregroundStyle(metric.contains("BPM") ? DS.Status.error : DS.Semantic.textPrimary)
                                .lineLimit(1)
                        }
                    }
                }

                if let previewLine = summary.previewLine {
                    HStack(spacing: 8) {
                        Text(previewLine)
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer(minLength: 8)
                        Text("View")
                            .dsFont(.caption2, weight: .bold)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    .padding(.top, 10)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: context.minHeight, alignment: .topLeading)
        .background(context == .carousel ? Color.clear : DS.Semantic.card, in: ChamferedRectangle(.medium))
        .overlay(
            ChamferedRectangle(.medium)
                .stroke(DS.Semantic.border, lineWidth: context == .carousel ? 0 : 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct WorkoutPostHeroStatColumn: View {
    let stat: WorkoutPostSummaryStat

    var body: some View {
        VStack(spacing: 3) {
            Text(stat.label.uppercased())
                .font(.system(size: 8, weight: .black))
                .tracking(1.2)
                .foregroundStyle(DS.Semantic.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.value)
                .font(DS.Typography.custom(size: 28, weight: .heavy))
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .monospacedDigit()
            Text(stat.unit.uppercased())
                .font(.system(size: 8, weight: .black))
                .tracking(1.2)
                .foregroundStyle(DS.Semantic.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(stat.label), \(stat.value) \(stat.unit)")
    }
}
