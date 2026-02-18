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

    @AppStorage("user_age") private var userAge: Int = 0

    @State private var targetMinutes: Int = 150
    @State private var targetDailySteps: Int = 10000
    @State private var targetStrengthDays: Int = 2
    @State private var weekStartDay: Int = 2 // Monday
    @State private var trackingMode: ActivityTrackingMode = .exerciseMinutes
    @State private var isDetectingDevice: Bool = false
    @State private var inputAge: Int = 30

    var body: some View {
        ZStack {
            // Premium background gradient
            LinearGradient(
                colors: [DS.Theme.cardBottom, DS.Theme.cardTop],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "target")
                            .font(.system(size: 60, weight: .semibold))
                            .foregroundStyle(DS.Theme.accent)

                        Text("Set Your Weekly Goal")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Track your fitness with custom weekly targets")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // Age Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.title3)
                                .foregroundStyle(DS.Theme.accent)
                            Text("Your Age")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        HStack(spacing: 20) {
                            Button {
                                if inputAge > 10 {
                                    inputAge -= 1
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "minus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)

                            Text("\(inputAge)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Theme.accent)
                                .monospacedDigit()
                                .frame(minWidth: 60)

                            Button {
                                if inputAge < 100 {
                                    inputAge += 1
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)

                        Text("Used to calculate your heart rate zones")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    // Active Minutes or Steps Card (device-dependent)
                    if trackingMode == .exerciseMinutes {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "applewatch")
                                    .font(.title3)
                                    .foregroundStyle(DS.Theme.accent)
                                Text("Active Minutes (MVPA)")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }

                            Text("\(targetMinutes) min")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Theme.accent)
                                .monospacedDigit()

                            Slider(value: Binding(
                                get: { Double(targetMinutes) },
                                set: { targetMinutes = Int($0) }
                            ), in: 30...600, step: 15)
                            .tint(DS.Theme.accent)

                            Text("Apple Watch tracks exercise time automatically")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.walk")
                                    .font(.title3)
                                    .foregroundStyle(DS.Theme.accent)
                                Text("Daily Steps")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }

                            Text("\(targetDailySteps.formatted())")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Theme.accent)
                                .monospacedDigit()

                            Slider(value: Binding(
                                get: { Double(targetDailySteps) },
                                set: { targetDailySteps = Int($0) }
                            ), in: 1000...30000, step: 500)
                            .tint(DS.Theme.accent)

                            Text("Aim for 10,000 steps per day for good health")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 24)
                    }

                    // Strength Days Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "dumbbell.fill")
                                .font(.title3)
                                .foregroundStyle(DS.Theme.accent)
                            Text("Strength Training Days")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        HStack(spacing: 20) {
                            Button {
                                if targetStrengthDays > 0 {
                                    targetStrengthDays -= 1
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "minus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)

                            Text("\(targetStrengthDays)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Theme.accent)
                                .monospacedDigit()
                                .frame(minWidth: 60)

                            Button {
                                if targetStrengthDays < 7 {
                                    targetStrengthDays += 1
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)

                        Text("Aim for 2-3 strength sessions per week")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    // Week Start Day Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.title3)
                                .foregroundStyle(DS.Theme.accent)
                            Text("Week Start Day")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        Text(weekdayName(for: weekStartDay))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Custom day selector
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(1...7, id: \.self) { day in
                                    Button {
                                        weekStartDay = day
                                    } label: {
                                        VStack(spacing: 6) {
                                            Text(weekdayShortName(for: day))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(weekStartDay == day ? .black : .white)

                                            Circle()
                                                .fill(weekStartDay == day ? DS.Theme.accent : .white.opacity(0.2))
                                                .frame(width: 8, height: 8)
                                        }
                                        .frame(width: 60, height: 60)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(weekStartDay == day ? DS.Theme.accent : .white.opacity(0.06))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(weekStartDay == day ? DS.Theme.accent : .white.opacity(0.1), lineWidth: 1.5)
                                        )
                                    }
                                }
                            }
                        }

                        Text("Your week will start on \(weekdayName(for: weekStartDay))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    // Save Button
                    Button {
                        saveGoal()
                    } label: {
                        Text("Save Goal")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(DS.Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Load existing age if set
            if userAge > 0 {
                inputAge = userAge
            }

            if let g = goal {
                // Existing goal - load values
                targetMinutes = g.targetActiveMinutes
                targetDailySteps = g.targetDailySteps
                targetStrengthDays = g.targetStrengthDays
                weekStartDay = g.anchorWeekday
                trackingMode = g.mode
            } else {
                // New goal - detect device capability
                Task {
                    isDetectingDevice = true
                    trackingMode = await DeviceCapability.recommendedTrackingMode()
                    isDetectingDevice = false
                }
            }
        }
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

        // Save age and update HR zone calculator
        userAge = inputAge
        HRZoneCalculator.shared.userAge = inputAge

        // Sync birth year to Supabase for partner HR zone calculation
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

// Color(hex:) is now available from DS.swift, no need to redefine
