//
//  CutOnboardingHost.swift
//  WRKT
//
//  Wires the Cut onboarding to what OnboardingCarouselView used: the same onComplete for Skip and
//  Get started, bodyweight written to "user_bodyweight_kg" on every step (kilograms, as before),
//  and the light haptic per step. The unit switch writes the app's "weight_unit" preference.
//

import SwiftUI

struct CutOnboardingHost: View {
    let onComplete: () -> Void

    @State private var page = 0
    @AppStorage("user_bodyweight_kg") private var userBodyweightKg: Double = CutOnboardingLogic.defaultBodyweightKg
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        CutOnboardingView(
            page: $page,
            bodyweight: CutOnboardingLogic.bodyweight(kg: userBodyweightKg, unit: unit),
            actions: CutOnboardingActions(
                skip: onComplete,
                next: {
                    if let next = CutOnboardingLogic.next(after: page) {
                        withAnimation(reduceMotion ? nil : .easeInOut) { page = next }
                    } else {
                        onComplete()
                    }
                },
                back: {
                    if let previous = CutOnboardingLogic.back(from: page) {
                        withAnimation(reduceMotion ? nil : .easeInOut) { page = previous }
                    }
                },
                step: { up, tenths in
                    guard let kg = CutOnboardingLogic.step(kg: userBodyweightKg, unit: unit, up: up, tenthsPerStep: tenths) else { return }
                    userBodyweightKg = kg
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                },
                setUnit: { newUnit in
                    guard newUnit != unit else { return }
                    Haptics.light()
                    weightUnitRaw = newUnit.rawValue
                },
                getStarted: onComplete
            )
        )
    }
}
