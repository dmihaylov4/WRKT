//
//  WeeklyGoalSetupView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 18.10.25.
//


// Features/Goals/WeeklyGoalSetupView.swift
import SwiftUI
import SwiftData

struct WeeklyGoalSetupView: View {
    let goal: WeeklyGoal?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var authService: SupabaseAuthService

    @State private var targetMinutes: Int = 150
    @State private var targetDailySteps: Int = 10000
    @State private var targetStrengthDays: Int = 2
    @State private var weekStartDay: Int = 2 // Monday
    @State private var trackingMode: ActivityTrackingMode = .exerciseMinutes
    @State private var isDetectingDevice: Bool = false
    @State private var inputAge: Int = 30

    var body: some View {
        ZStack {
            DS.Semantic.surface
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headerView
                    ageCard
                    activityCard
                    strengthDaysCard
                    weekStartDayCard

                    // Save Button
                    Button {
                        saveGoal()
                    } label: {
                        Text("Save Goal")
                            .dsFont(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(DS.Theme.accent, in: ChamferedRectangle(.large))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if let birthYear = authService.currentUser?.profile?.birthYear {
                inputAge = Calendar.current.component(.year, from: Date()) - birthYear
            }

            if let g = goal {
                targetMinutes = g.targetActiveMinutes
                targetDailySteps = g.targetDailySteps
                targetStrengthDays = g.targetStrengthDays
                weekStartDay = g.anchorWeekday
                trackingMode = g.mode
            } else {
                Task {
                    isDetectingDevice = true
                    trackingMode = await DeviceCapability.recommendedTrackingMode()
                    isDetectingDevice = false
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 54, height: 54)
                .background(DS.Theme.accent, in: ChamferedRectangle(.medium))

            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Goal")
                    .font(DS.Typography.custom(size: 28, weight: .bold))
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Set targets for steps, minutes, and strength days.")
                    .font(DS.Typography.custom(size: 15, weight: .regular))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
        .overlay(ChamferedRectangle(.xl).stroke(DS.Theme.accent.opacity(0.25), lineWidth: 1))
    }

    private var ageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .dsFont(.title3)
                    .foregroundStyle(DS.Theme.accent)
                Text("Your Age")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            HStack(spacing: 20) {
                Button {
                    if inputAge > 10 {
                        inputAge -= 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    stepperButtonLabel(systemImage: "minus")
                }
                .buttonStyle(.plain)

                Text("\(inputAge)")
                    .font(DS.Typography.custom(size: 42, weight: .bold))
                    .foregroundStyle(DS.Theme.accent)
                    .monospacedDigit()
                    .frame(minWidth: 60)

                Button {
                    if inputAge < 100 {
                        inputAge += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    stepperButtonLabel(systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

                Text("Used to calculate your heart rate zones")
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .goalCardStyle()
    }

    @ViewBuilder
    private var activityCard: some View {
        if trackingMode == .exerciseMinutes {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "applewatch")
                        .dsFont(.title3)
                        .foregroundStyle(DS.Theme.accent)
                    Text("Active Minutes (MVPA)")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                Text("\(targetMinutes) min")
                    .font(DS.Typography.custom(size: 42, weight: .bold))
                    .foregroundStyle(DS.Theme.accent)
                    .monospacedDigit()

                Slider(value: Binding(
                    get: { Double(targetMinutes) },
                    set: { targetMinutes = Int($0) }
                ), in: 30...600, step: 15)
                .tint(DS.Theme.accent)

                Text("Apple Watch tracks exercise time automatically")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .goalCardStyle()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .dsFont(.title3)
                        .foregroundStyle(DS.Theme.accent)
                    Text("Daily Steps")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                Text("\(targetDailySteps.formatted())")
                    .font(DS.Typography.custom(size: 42, weight: .bold))
                    .foregroundStyle(DS.Theme.accent)
                    .monospacedDigit()

                Slider(value: Binding(
                    get: { Double(targetDailySteps) },
                    set: { targetDailySteps = Int($0) }
                ), in: 1000...30000, step: 500)
                .tint(DS.Theme.accent)

                Text("Aim for 10,000 steps per day for good health")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .goalCardStyle()
        }
    }

    private var strengthDaysCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .dsFont(.title3)
                    .foregroundStyle(DS.Theme.accent)
                Text("Strength Training Days")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            HStack(spacing: 20) {
                Button {
                    if targetStrengthDays > 0 {
                        targetStrengthDays -= 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    stepperButtonLabel(systemImage: "minus")
                }
                .buttonStyle(.plain)

                Text("\(targetStrengthDays)")
                    .font(DS.Typography.custom(size: 42, weight: .bold))
                    .foregroundStyle(DS.Theme.accent)
                    .monospacedDigit()
                    .frame(minWidth: 60)

                Button {
                    if targetStrengthDays < 7 {
                        targetStrengthDays += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    stepperButtonLabel(systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            Text("Aim for 2-3 strength sessions per week")
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .goalCardStyle()
    }

    private var weekStartDayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .dsFont(.title3)
                    .foregroundStyle(DS.Theme.accent)
                Text("Week Start Day")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            Text(weekdayName(for: weekStartDay))
                .font(DS.Typography.custom(size: 42, weight: .bold))
                .foregroundStyle(DS.Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            weekStartDay = day
                        } label: {
                            VStack(spacing: 6) {
                                Text(weekdayShortName(for: day))
                                    .dsFont(.caption, weight: .semibold)
                                    .foregroundStyle(weekStartDay == day ? .black : DS.Semantic.textPrimary)

                                Circle()
                                    .fill(weekStartDay == day ? DS.Theme.accent : DS.Semantic.surface50)
                                    .frame(width: 8, height: 8)
                            }
                            .frame(width: 60, height: 60)
                            .background(
                                ChamferedRectangle(.small)
                                    .fill(weekStartDay == day ? DS.Theme.accent : DS.Semantic.fillSubtle)
                            )
                            .overlay(
                                ChamferedRectangle(.small)
                                    .stroke(weekStartDay == day ? DS.Theme.accent : DS.Semantic.border, lineWidth: 1.5)
                            )
                        }
                    }
                }
            }

            Text("Your week will start on \(weekdayName(for: weekStartDay))")
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .goalCardStyle()
    }

    // MARK: - Helpers

    private func stepperButtonLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(DS.Semantic.textPrimary)
            .frame(width: 50, height: 50)
            .background(DS.Semantic.surface50.opacity(0.85), in: ChamferedRectangle(.medium))
            .overlay(ChamferedRectangle(.medium).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func saveGoal() {
        let g = goal ?? WeeklyGoal()
        g.isSet = true
        g.targetActiveMinutes = targetMinutes
        g.targetDailySteps = targetDailySteps
        g.targetStrengthDays = targetStrengthDays
        g.anchorWeekday = weekStartDay
        g.mode = trackingMode
        g.updatedAt = .now

        HRZoneCalculator.shared.userAge = inputAge

        let birthYear = Calendar.current.component(.year, from: Date()) - inputAge
        Task {
            try? await SupabaseAuthService.shared.updateProfile(birthYear: birthYear)
        }

        if goal == nil { context.insert(g) }
        try? context.save()
        dismiss()
    }

    private func weekdayName(for weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(weekday - 1) % 7]
    }

    private func weekdayShortName(for weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols[(weekday - 1) % 7]
    }
}

// MARK: - Card background modifier

private extension View {
    func goalCardStyle() -> some View {
        self
            .padding(18)
            .background(
                ChamferedRectangle(.xl)
                    .fill(DS.Semantic.card)
                    .overlay(ChamferedRectangle(.xl).stroke(DS.Semantic.border, lineWidth: 1))
            )
    }
}

// Color(hex:) is now available from DS.swift, no need to redefine
