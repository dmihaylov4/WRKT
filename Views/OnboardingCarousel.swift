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
            accentColor: Color(hex: "#F4E409")
        ),
        OnboardingPage(
            icon: "flame.fill",
            title: "Stay Motivated",
            description: "Build streaks, earn achievements, level up your profile, and unlock rewards as you train consistently.",
            accentColor: Color(hex: "#F4E409")
        ),
        OnboardingPage(
            icon: "scale.3d",
            title: "Train Smart",
            description: "Balance your training with muscle recovery insights, push-pull analysis, and movement pattern tracking.",
            accentColor: Color(hex: "#F4E409")
        ),
        OnboardingPage(
            icon: "figure.strengthtraining.traditional",
            title: "Your Starting Point",
            description: "Enter your bodyweight to get personalized weight suggestions for exercises.",
            accentColor: Color(hex: "#F4E409"),
            isBodyweightInput: true
        )
    ]

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#0D0D0D"), Color(hex: "#1A1A1A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button {
                        onComplete()
                    } label: {
                        Text("Skip")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 16)

                // Page content
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

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color(hex: "#F4E409") : .white.opacity(0.3))
                            .frame(width: currentPage == index ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 24)

                // Action button
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
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#F4E409"), Color(hex: "#FFE869")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color(hex: "#F4E409").opacity(0.3), radius: 12, x: 0, y: 6)
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
        VStack(spacing: 32) {
            Spacer()

            // Icon - clean and professional with border
            Image(systemName: page.icon)
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(page.accentColor)
                .padding(32)
                .background(
                    Circle()
                        .stroke(page.accentColor.opacity(0.3), lineWidth: 2)
                )
                .padding(.bottom, 40)

            // Title
            Text(page.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Description
            Text(page.description)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Bodyweight Input Page View
private struct BodyweightInputPageView: View {
    @Binding var bodyweight: Double

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon - clean and professional with border
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(Color(hex: "#F4E409"))
                .padding(32)
                .background(
                    Circle()
                        .stroke(Color(hex: "#F4E409").opacity(0.3), lineWidth: 2)
                )
                .padding(.bottom, 40)

            // Title
            Text("Your Starting Point")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Description
            Text("Enter your bodyweight to get personalized weight suggestions for exercises.")
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            // Bodyweight input
            VStack(spacing: 12) {
                Text(String(format: "%.1f kg", bodyweight))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#F4E409"))
                    .monospacedDigit()

                HStack(spacing: 16) {
                    Button {
                        if bodyweight > 30 {
                            bodyweight = max(30, bodyweight - 0.5)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Slider(value: $bodyweight, in: 30...200, step: 0.5)
                        .tint(Color(hex: "#F4E409"))
                        .frame(maxWidth: 200)

                    Button {
                        if bodyweight < 200 {
                            bodyweight = min(200, bodyweight + 0.5)
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 32)
            }
            .padding(.top, 16)

            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    OnboardingCarouselView(onComplete: {})
}
