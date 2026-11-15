//
//  AgeSetting.swift
//  WRKT
//
//  The age behind heart rate zones, shared by the legacy and the Cut Preferences screens.
//  The zone calculator holds it (as a birth year, so it ages by itself) for every user: signed
//  in, signed out or in local mode. Signed in users also save it to their profile, which seeds
//  the calculator again at launch. The wheel edits a draft; one commit happens when its sheet
//  closes, never per tick.
//

import Foundation

/// The age wheel's draft: what it starts on, what it shows, and what to save when it closes.
struct AgeDraft: Equatable {
    static let range = 10...100
    /// The wheel's starting value when no age is saved yet.
    static let suggestedAge = 30

    /// The age saved before the sheet opened; nil when none is.
    let saved: Int?
    /// The wheel's value.
    var age: Int

    init(saved: Int?) {
        self.saved = saved
        self.age = Self.startAge(saved)
    }

    /// Where the wheel starts: the saved age kept inside the wheel's range, or the suggestion.
    static func startAge(_ saved: Int?) -> Int {
        saved.map { min(max($0, range.lowerBound), range.upperBound) } ?? suggestedAge
    }

    /// The age to commit when the sheet closes, or nil for no save. Done saves whenever the
    /// value differs from the saved one (so confirming the suggested 30 sets it); swiping the
    /// sheet away saves only when the wheel was turned.
    func ageToCommit(confirmed: Bool) -> Int? {
        guard age != saved else { return nil }
        if confirmed { return age }
        return age != Self.startAge(saved) ? age : nil
    }
}

enum AgeSetting {
    /// The row value: "34 years", or "Not set".
    static func line(_ age: Int?) -> String {
        age.map { "\($0) years" } ?? "Not set"
    }

    static func birthYear(age: Int, currentYear: Int) -> Int {
        currentYear - age
    }

    /// Commits one age: stores it locally (one zone update) and, for a signed in user, saves the
    /// birth year to the profile. The local value stays even if the profile save fails, so the
    /// row and the zones always show what the user picked; the error is rethrown for the caller.
    @MainActor
    static func commit(
        _ age: Int,
        currentYear: Int,
        setLocal: (Int) -> Void,
        saveBirthYear: ((Int) async throws -> Void)?
    ) async throws {
        setLocal(age)
        guard let saveBirthYear else { return }
        try await saveBirthYear(birthYear(age: age, currentYear: currentYear))
    }

    /// The app's wiring: the shared zone calculator and, when signed in, the auth service.
    @MainActor
    static func commit(_ age: Int, auth: SupabaseAuthService, calculator: HRZoneCalculator = .shared) {
        let save: ((Int) async throws -> Void)? = auth.currentUser == nil
            ? nil
            : { try await auth.updateProfile(birthYear: $0) }
        Task {
            do {
                try await commit(age, currentYear: Calendar.current.component(.year, from: Date()),
                                 setLocal: { calculator.userAge = $0 }, saveBirthYear: save)
            } catch {
                AppLogger.error("Saving the age to the profile failed; kept on this device", error: error, category: AppLogger.app)
            }
        }
    }
}
