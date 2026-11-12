//
//  CutGalleryView.swift
//  WRKT
//
//  DEBUG only: every Cut piece with Train content from the approved mock.
//  Reachable from Settings > Debug > Cut gallery.
//

#if DEBUG
import SwiftUI

struct CutGalleryView: View {
    var body: some View {
        ScrollView {
            CutGalleryContent()
        }
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CutActionBar("Log set", subtitle: "Rest 2:00 starts after") {}
        }
        .toolbar(.hidden, for: .navigationBar)
        .modifier(HideTopScrollEdgeEffect())
        .preferredColorScheme(.dark)
    }
}

/// The gallery body without scrolling, so it can also be rendered to an image.
struct CutGalleryContent: View {
    var topInset: CGFloat = 62

    @State private var strengthDays = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trainField
            weeklyGoal
            trainRows

            section("Tab header") {
                VStack(spacing: 24) {
                    CutTabHeader("Social") {
                        Button("Activity", systemImage: "heart") {}
                        Button("New", systemImage: "plus") {}
                            .buttonStyle(CutIconButtonStyle(tone: .lime))
                    }
                    CutTabHeader("Level 14") {
                        Button("Settings", systemImage: "gearshape") {}
                    }
                }
            }

            section("Type") {
                VStack(alignment: .leading, spacing: 14) {
                    CutHeroText("Bench\nPress", hero: .l)
                    Text("Done.").cutHero(.xxl)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("85").cutNumeral(.hero)
                        Text("kg").cutFont(.title).foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                    Text("Battle with Alex").cutFont(.title)
                    Text("Legs done. Hamstrings are filing a complaint.").cutFont(.body)
                    Text("Last 85 kg x 6, best 100 kg").cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
            }

            section("Stats") {
                HStack(spacing: 0) {
                    stat("52:08", "Duration")
                    Rectangle().fill(DS.Cut.Colors.hairline).frame(width: 1)
                    stat("8,420", "kg volume").padding(.leading, 14)
                    Rectangle().fill(DS.Cut.Colors.hairline).frame(width: 1)
                    stat("18", "Sets").padding(.leading, 14)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            section("Buttons") {
                VStack(spacing: 10) {
                    Button("Finish workout") {}.buttonStyle(.cutPrimary)
                    Button("Continue") {}.buttonStyle(.cutSecondary)
                    HStack(spacing: 10) {
                        Button("Start timer", systemImage: "play.fill") {}
                            .buttonStyle(CutSecondaryButtonStyle(size: .compact))
                        Button("Log set") {}
                            .buttonStyle(CutPrimaryButtonStyle(size: .compact))
                    }
                    HStack(spacing: 10) {
                        Button("More", systemImage: "ellipsis") {}.buttonStyle(.cutIcon)
                        Button("Add", systemImage: "plus") {}.buttonStyle(CutIconButtonStyle(tone: .lime))
                        Button("Info", systemImage: "info") {}.buttonStyle(CutIconButtonStyle(tone: .outline, diameter: 44))
                        Spacer()
                    }
                }
            }

            section("Sets") {
                VStack(alignment: .leading, spacing: 16) {
                    CutSegmentProgress(total: 4, filled: 2, current: 2, accessibilityLabel: Text("Sets"))
                    CutSegmentProgress(total: 12, filled: 6, thickness: .thin,
                                       accessibilityLabel: Text("Weeks to the next milestone"))
                }
            }

            section("Start a workout") {
                VStack(spacing: 0) {
                    bigRow("Upper Body", subtitle: "6 exercises, about 55 min", tile: true)
                    bigRow("Lower Body", subtitle: nil, tile: false)
                    bigRow("Custom", subtitle: nil, tile: false)
                }
            }

            section("Empty state") {
                HStack(spacing: 18) {
                    VMarkProgress(left: 0, right: 0, tone: .line, accessibilityLabel: "Nothing logged yet")
                        .frame(width: 84)
                    Text("Locked").cutHero(.m)
                }
            }

            Text(DS.Redesign.cutEnabled ? "Cut gate is on" : "Cut gate is off")
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.vertical, 32)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background)
    }

    // MARK: Train

    private var trainField: some View {
        CutField(padding: EdgeInsets(top: topInset, leading: DS.Cut.Metrics.gutter, bottom: 58, trailing: DS.Cut.Metrics.gutter)) {
            VMarkShape()
                .fill(DS.Cut.Colors.ink)
                .frame(width: 40, height: 24)
                .accessibilityLabel("VOLIA")
            CutHeroText("Upper\nBody", hero: .xl)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 40)
            Text("6 exercises, about 55 min")
                .cutFont(.title)
                .padding(.top, 16)
            HStack(spacing: 10) {
                Button("Start workout", systemImage: "arrow.right") {}
                    .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
                Button("More options", systemImage: "ellipsis") {}
                    .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: 56))
            }
            .padding(.top, 22)
        }
        .frame(minHeight: 430, alignment: .top)
    }

    private var weeklyGoal: some View {
        Button {
            strengthDays = strengthDays == 2 ? 3 : 2
        } label: {
            HStack(spacing: 22) {
                VMarkProgress(
                    left: Double(strengthDays) / 4,
                    right: 95.0 / 150.0,
                    accessibilityLabel: "Weekly goal: strength \(strengthDays) of 4, cardio 95 of 150 minutes"
                )
                .frame(width: 150)
                VStack(alignment: .leading, spacing: 10) {
                    goalLine("\(strengthDays)/4", "strength")
                    goalLine("95/150", "cardio min")
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.vertical, 30)
    }

    private var trainRows: some View {
        CutHairlineList {
            CutHairlineRow("Battle with Alex", value: "Leading by 1,240 kg", valueTone: .lime)
            CutHairlineRow("Streak", value: "6 weeks")
            CutHairlineRow("Last workout", value: "Lower Body, Fri")
            CutHairlineRow("Weekly goal", subtitle: "3 days left", showsChevron: true)
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
    }

    // MARK: Pieces

    private func goalLine(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).cutNumeral(.medium)
            Text(unit).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).cutNumeral(.medium)
            Text(label).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func bigRow(_ title: String, subtitle: String?, tile: Bool) -> some View {
        Button {} label: {
            VStack(spacing: 0) {
                CutHairline()
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).cutHero(.s)
                        if let subtitle {
                            Text(subtitle).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if tile {
                        CutTile()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .buttonStyle(.plain)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CutSectionTitle(title)
            content()
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 34)
    }
}

/// The system scroll edge effect would tint the top of the lime field.
private struct HideTopScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

#Preview("Cut gallery") {
    NavigationStack {
        CutGalleryView()
    }
}

#Preview("Cut gallery, accessibility XL") {
    CutGalleryView()
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
