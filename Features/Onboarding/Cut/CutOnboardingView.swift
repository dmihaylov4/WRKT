//
//  CutOnboardingView.swift
//  WRKT
//
//  Three intro pages, each a lime cut-corner field with the mark, Skip, one big line and one
//  sentence, a four-segment progress bar and a white Next button; then the bodyweight page with a
//  back button, a stepper panel, a Kilograms / Pounds switch and a lime Get started. Pages swipe
//  with a swipe as in the legacy carousel. Every page scrolls when its text is too large for the screen.
//

import SwiftUI

struct CutOnboardingActions {
    var skip: () -> Void = {}
    var next: () -> Void = {}
    var back: () -> Void = {}
    /// One step of the bodyweight in the display unit; the Int is tenths per step.
    var step: (_ up: Bool, _ tenthsPerStep: Int) -> Void = { _, _ in }
    var setUnit: (WeightUnit) -> Void = { _ in }
    var getStarted: () -> Void = {}
}

struct CutOnboardingView: View {
    @Binding var page: Int
    let bodyweight: CutOnboardingBodyweightModel
    var actions = CutOnboardingActions()

    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let width = proxy.size.width + insets.leading + insets.trailing
            // The pages sit side by side and slide; a horizontal swipe moves one page, as the
            // legacy paged carousel did. (A paged TabView would put its own scroll edge tint over
            // the lime field.)
            HStack(spacing: 0) {
                ForEach(CutOnboardingLogic.pages) { intro in
                    CutOnboardingIntroPage(page: intro, progress: CutOnboardingLogic.progress(at: intro.id),
                                           insets: insets, skip: actions.skip, next: actions.next)
                        .frame(width: width)
                        .accessibilityHidden(intro.id != page)
                }
                CutOnboardingBodyweightPage(model: bodyweight, progress: CutOnboardingLogic.progress(at: CutOnboardingLogic.bodyweightIndex),
                                            insets: insets, actions: actions)
                    .frame(width: width)
                    .accessibilityHidden(page != CutOnboardingLogic.bodyweightIndex)
            }
            .frame(width: width, alignment: .leading)
            .offset(x: -CGFloat(page) * width + drag)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        drag = CutOnboardingLogic.dragOffset(value.translation.width, at: page)
                    }
                    .onEnded { value in
                        let target = CutOnboardingLogic.page(afterSwipe: value.translation.width,
                                                             vertical: value.translation.height, from: page, width: width)
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) {
                            page = target
                            drag = 0
                        }
                    }
            )
            .ignoresSafeArea()
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .modifier(CutOnboardingStatusBar(overLime: page < CutOnboardingLogic.bodyweightIndex))
    }
}

// MARK: - Intro page

private struct CutOnboardingIntroPage: View {
    let page: CutOnboardingPage
    let progress: CutOnboardingProgress
    let insets: EdgeInsets
    let skip: () -> Void
    let next: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    CutField(padding: EdgeInsets(top: insets.top + 4, leading: DS.Cut.Metrics.gutter,
                                                 bottom: 90, trailing: DS.Cut.Metrics.gutter)) {
                        HStack {
                            VMarkShape()
                                .fill(DS.Cut.Colors.ink)
                                .frame(width: 44, height: 26)
                                .accessibilityLabel(Text("VOLIA"))
                            Spacer(minLength: 12)
                            Button(action: skip) {
                                Text("Skip")
                                    .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .body))
                                    .foregroundStyle(DS.Cut.Colors.ink)
                                    .padding(.horizontal, 6)
                                    .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 48)
                        CutOnboardingHero(text: page.title, size: 76)
                        Text(page.line)
                            .font(DS.Typography.custom(size: 19, weight: .semibold, relativeTo: .body))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        CutOnboardingProgressBar(progress: progress)
                        Button("Next", action: next)
                            .buttonStyle(CutPillButtonStyle(.white, size: .regular, fillsWidth: true))
                    }
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 22)
                    .padding(.bottom, insets.bottom + 8)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .modifier(CutOnboardingNoEdgeEffect())
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Bodyweight page

private struct CutOnboardingBodyweightPage: View {
    let model: CutOnboardingBodyweightModel
    let progress: CutOnboardingProgress
    let insets: EdgeInsets
    let actions: CutOnboardingActions

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CutPlannerTopBar(leading: .back, action: actions.back) {
                        Spacer(minLength: 12)
                        CutOnboardingProgressBar(progress: progress)
                            .padding(.trailing, 8)
                    }
                    .padding(.top, insets.top)
                    CutOnboardingHero(text: CutOnboardingLogic.bodyweightTitle, size: 48)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 30)
                    Text(CutOnboardingLogic.bodyweightLine)
                        .font(DS.Typography.custom(size: 18, weight: .medium, relativeTo: .body))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 12)
                    CutOnboardingStepper(model: model, step: actions.step)
                        .padding(.top, 48)
                    CutPlannerSegmented(items: WeightUnit.allCases, selected: model.unit,
                                        title: CutOnboardingLogic.unitTitle, select: actions.setUnit)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    Spacer(minLength: 32)
                    Button("Get started", action: actions.getStarted)
                        .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.bottom, insets.bottom + 8)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .modifier(CutOnboardingNoEdgeEffect())
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

/// Minus, the number and plus on a raised panel. A held button repeats, a tenth at a time and
/// then a whole unit; VoiceOver adjusts the number a whole unit per swipe.
private struct CutOnboardingStepper: View {
    let model: CutOnboardingBodyweightModel
    let step: (_ up: Bool, _ tenthsPerStep: Int) -> Void

    @State private var repeats = 0
    @State private var lastStep: Date = .distantPast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The number takes the full width; the buttons sit under it.
                VStack(spacing: 20) {
                    number.frame(maxWidth: .infinity)
                    HStack {
                        stepButton(up: false)
                        Spacer(minLength: 12)
                        stepButton(up: true)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    stepButton(up: false)
                    Spacer(minLength: 0)
                    number
                    Spacer(minLength: 0)
                    stepButton(up: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(DS.Cut.Colors.panel)
        .padding(.horizontal, DS.Cut.Metrics.panelInset)
    }

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.number)
                .font(DS.Cut.Typography.condensed(size: 84, relativeTo: .title, monospacedDigits: true))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(model.unitLabel)
                .font(DS.Typography.custom(size: 22, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bodyweight"))
        .accessibilityValue(Text(model.spoken))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(true, 10)
            case .decrement: step(false, 10)
            @unknown default: break
            }
        }
    }

    private func stepButton(up: Bool) -> some View {
        Button {
            // Steps closer together than a third of a second are a held button repeating.
            let now = Date()
            repeats = now.timeIntervalSince(lastStep) < 0.35 ? repeats + 1 : 0
            lastStep = now
            step(up, CutOnboardingLogic.tenthsPerStep(repeats: repeats))
        } label: {
            Image(systemName: up ? "plus" : "minus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .frame(width: 60, height: 60)
                .background(Circle().fill(DS.Cut.Colors.panelControl))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(up ? !model.canIncrease : !model.canDecrease)
        .opacity((up ? model.canIncrease : model.canDecrease) ? 1 : 0.4)
        .accessibilityLabel(Text(up ? "Increase bodyweight" : "Decrease bodyweight"))
    }
}

// MARK: - Pieces

/// A big condensed capital line, balanced over two lines; each line shrinks to fit, never truncates.
private struct CutOnboardingHero: View {
    let text: String
    let size: CGFloat
    @ScaledMetric(relativeTo: .largeTitle) private var scaledHundred: CGFloat = 100

    var body: some View {
        let scaled = size * scaledHundred / 100
        VStack(alignment: .leading, spacing: (0.9 - DS.Cut.Typography.naturalLineHeight) * scaled) {
            ForEach(Array(CutHeroText.lines(of: CutHeroText.balancedLines(text)).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(DS.Cut.Typography.condensed(size: size, relativeTo: .largeTitle))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Four short bars: done and current in lime, the current one wide; read as "Step n of 4".
private struct CutOnboardingProgressBar: View {
    let progress: CutOnboardingProgress

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(progress.segments.enumerated()), id: \.offset) { _, segment in
                Rectangle()
                    .fill(segment == .upcoming ? DS.Cut.Colors.segmentTrack : DS.Cut.Colors.lime)
                    .frame(width: segment == .current ? 34 : 14, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(progress.spoken))
    }
}

/// Dark status bar content while an intro page's lime field sits behind it (iOS 27 and later).
private struct CutOnboardingStatusBar: ViewModifier {
    let overLime: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.toolbarColorScheme(overLime ? .light : nil, for: .statusBar)
        } else {
            content
        }
    }
}

/// No system scroll edge effect (iOS 26 and later): it would tint the lime field and the pinned
/// buttons. The pages are short and draw their own background edge to edge.
private struct CutOnboardingNoEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}
