//
//  OnboardingCarousel.swift
//  WRKT
//
//  Premium onboarding carousel with app value propositions
//

import SwiftUI

// MARK: - Main Onboarding View
struct OnboardingCarouselView: View {
    var onComplete: () -> Void
    @State private var currentPage = 0
    @AppStorage("user_bodyweight_kg") private var userBodyweightKg: Double = 70.0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            title: "Track Your Progress",
            description: "Set personal records, monitor volume trends, and watch your strength grow with detailed analytics.",
            accentColor: DS.Theme.accent
        ),
        OnboardingPage(
            icon: "flame.fill",
            title: "Stay Motivated",
            description: "Build streaks, earn achievements, level up your profile, and unlock rewards as you train consistently.",
            accentColor: DS.Theme.accent
        ),
        OnboardingPage(
            icon: "scale.3d",
            title: "Train Smart",
            description: "Balance your training with muscle recovery insights, push-pull analysis, and movement pattern tracking.",
            accentColor: DS.Theme.accent
        ),
        OnboardingPage(
            icon: "figure.strengthtraining.traditional",
            title: "Your Starting Point",
            description: "Enter your bodyweight to get personalized weight suggestions for exercises.",
            accentColor: DS.Theme.accent,
            isBodyweightInput: true
        )
    ]

    var body: some View {
        ZStack {
            DS.Semantic.surface
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        onComplete()
                    } label: {
                        Text("Skip")
                            .dsFont(.subheadline, weight: .medium)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 16)

                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        if pages[index].isBodyweightInput {
                            BodyweightInputPageView(bodyweight: $userBodyweightKg)
                                .tag(index)
                        } else {
                            OnboardingPageView(page: pages[index])
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(currentPage == index ? DS.Theme.accent : DS.Semantic.surface50)
                            .frame(width: currentPage == index ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 24)

                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        onComplete()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .dsFont(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(DS.Theme.accent, in: ChamferedRectangle(.large))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Onboarding Page Model
struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    let isBodyweightInput: Bool

    init(icon: String, title: String, description: String, accentColor: Color, isBodyweightInput: Bool = false) {
        self.icon = icon
        self.title = title
        self.description = description
        self.accentColor = accentColor
        self.isBodyweightInput = isBodyweightInput
    }
}

// MARK: - Individual Page View
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            OnboardingIcon(systemName: page.icon)
                .padding(.bottom, 16)

            Text(page.title)
                .font(DS.Typography.custom(size: 30, weight: .bold))
                .foregroundStyle(DS.Semantic.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text(page.description)
                .font(DS.Typography.custom(size: 17, weight: .regular))
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Bodyweight Input Page View
private struct BodyweightInputPageView: View {
    @Binding var bodyweight: Double

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            OnboardingIcon(systemName: "figure.strengthtraining.traditional")
                .padding(.bottom, 12)

            Text("Your Starting Point")
                .font(DS.Typography.custom(size: 30, weight: .bold))
                .foregroundStyle(DS.Semantic.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("Your bodyweight is required to calculate 1RM.")
                .font(DS.Typography.custom(size: 17, weight: .regular))
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            VStack(spacing: 16) {
                Text(String(format: "%.1f kg", bodyweight))
                    .font(DS.Typography.custom(size: 54, weight: .bold))
                    .foregroundStyle(DS.Theme.accent)
                    .monospacedDigit()

                HStack(spacing: 16) {
                    Button {
                        if bodyweight > 30 {
                            bodyweight = max(30, bodyweight - 0.1)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        OnboardingStepButton(systemImage: "minus")
                    }
                    .buttonStyle(.plain)

                    Slider(value: $bodyweight, in: 30...200, step: 0.1)
                        .tint(DS.Theme.accent)
                        .frame(maxWidth: 200)

                    Button {
                        if bodyweight < 200 {
                            bodyweight = min(200, bodyweight + 0.1)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        OnboardingStepButton(systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
            }
            .padding(18)
            .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
            .overlay(ChamferedRectangle(.xl).stroke(DS.Semantic.border, lineWidth: 1))
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()
        }
    }
}

private struct OnboardingIcon: View {
    let systemName: String

    var body: some View {
        ZStack {
            ChamferedRectangle(.xl)
                .fill(DS.Theme.accent.opacity(0.12))
                .frame(width: 132, height: 132)
                .overlay(ChamferedRectangle(.xl).stroke(DS.Theme.accent.opacity(0.35), lineWidth: 1.5))

            Image(systemName: systemName)
                .font(.system(size: 58, weight: .bold))
                .foregroundStyle(DS.Theme.accent)
        }
    }
}

private struct OnboardingStepButton: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(DS.Semantic.textPrimary)
            .frame(width: 50, height: 50)
            .background(DS.Semantic.surface50.opacity(0.85), in: ChamferedRectangle(.medium))
            .overlay(ChamferedRectangle(.medium).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Preview
#Preview {
    OnboardingCarouselView(onComplete: {})
}
