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

    @State private var targetMinutes: Int = 150
    @State private var targetStrengthDays: Int = 2
    @State private var weekStartDay: Int = 2 // Monday

    var body: some View {
        ZStack {
            // Premium background gradient
            LinearGradient(
                colors: [Color(hex: "#0D0D0D"), Color(hex: "#1A1A1A")],
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
                            .foregroundStyle(Color(hex: "#F4E409"))

                        Text("Set Your Weekly Goal")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Track your fitness with custom weekly targets")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // Active Minutes Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.run")
                                .font(.title3)
                                .foregroundStyle(Color(hex: "#F4E409"))
                            Text("Active Minutes (MVPA)")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        Text("\(targetMinutes) min")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#F4E409"))
                            .monospacedDigit()

                        Slider(value: Binding(
                            get: { Double(targetMinutes) },
                            set: { targetMinutes = Int($0) }
                        ), in: 30...600, step: 15)
                        .tint(Color(hex: "#F4E409"))

                        Text("WHO recommends 150 minutes per week")
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

                    // Strength Days Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "dumbbell.fill")
                                .font(.title3)
                                .foregroundStyle(Color(hex: "#F4E409"))
                            Text("Strength Training Days")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        HStack(spacing: 20) {
                            Button {
                                if targetStrengthDays > 0 {
                                    targetStrengthDays -= 1
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            Text("\(targetStrengthDays)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#F4E409"))
                                .monospacedDigit()
                                .frame(minWidth: 60)

                            Button {
                                if targetStrengthDays < 7 {
                                    targetStrengthDays += 1
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
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
                                .foregroundStyle(Color(hex: "#F4E409"))
                            Text("Week Start Day")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        Text(weekdayName(for: weekStartDay))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#F4E409"))
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
                                                .fill(weekStartDay == day ? Color(hex: "#F4E409") : .white.opacity(0.2))
                                                .frame(width: 8, height: 8)
                                        }
                                        .frame(width: 60, height: 60)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(weekStartDay == day ? Color(hex: "#F4E409") : .white.opacity(0.06))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(weekStartDay == day ? Color(hex: "#F4E409") : .white.opacity(0.1), lineWidth: 1.5)
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
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if let g = goal {
                targetMinutes = g.targetActiveMinutes
                targetStrengthDays = g.targetStrengthDays
                weekStartDay = g.anchorWeekday
            }
        }
    }

    private func saveGoal() {
        let g = goal ?? WeeklyGoal()
        g.isSet = true
        g.targetActiveMinutes = targetMinutes
        g.targetStrengthDays = targetStrengthDays
        g.anchorWeekday = weekStartDay
        g.updatedAt = .now

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

private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255.0,
                     green: Double((v >> 8) & 0xFF) / 255.0,
                     blue: Double(v & 0xFF) / 255.0,
                     opacity: 1.0)
    }
}
