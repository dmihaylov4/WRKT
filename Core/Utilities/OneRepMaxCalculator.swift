import Foundation

enum OneRepMaxCalculator {
    /// Epley formula: weight × (1 + reps / 30).
    /// Returns nil when reps < 1 or weight <= 0.
    static func epley(weight: Double, reps: Int) -> Double? {
        guard reps >= 1, weight > 0 else { return nil }
        if reps == 1 { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    enum Confidence {
        case high      // 1-5 reps
        case moderate  // 6-10 reps
        case low       // 11+ reps — not reliable for leaderboard use
    }

    static func confidence(reps: Int) -> Confidence {
        switch reps {
        case 1...5:  return .high
        case 6...10: return .moderate
        default:     return .low
        }
    }
}
