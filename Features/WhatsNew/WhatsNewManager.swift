import SwiftUI
import Observation

struct WhatsNewRelease {
    let version: String
    let title: String
    let bullets: [String]
}

@Observable @MainActor
final class WhatsNewManager {
    static let shared = WhatsNewManager()

    @ObservationIgnored
    @AppStorage("whats_new_last_seen_version") var lastSeenVersion: String = ""

    private(set) var currentVersion: String = ""
    var needsWhatsNew: Bool = false

    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "5.1.1",
            title: "Barbell Rewards",
            bullets: [
                "Earn plates based on your workout history",
                "Build and display your barbell rack",
                "Plates backfilled from all past workouts automatically"
            ]
        )
    ]

    private init() {}

    func configure(
        hasCompletedOnboarding: Bool,
        fromOnboardingCompletion: Bool = false,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        releases: [WhatsNewRelease] = WhatsNewManager.releases
    ) {
        self.currentVersion = currentVersion
        AppLogger.info("[WhatsNew] configure: version=\(currentVersion) lastSeen='\(lastSeenVersion)' hasOnboarding=\(hasCompletedOnboarding) fromOnboarding=\(fromOnboardingCompletion)", category: AppLogger.ui)
        guard hasCompletedOnboarding else {
            AppLogger.info("[WhatsNew] skipped: onboarding not complete", category: AppLogger.ui)
            return
        }
        guard lastSeenVersion != currentVersion else {
            AppLogger.info("[WhatsNew] skipped: version already seen", category: AppLogger.ui)
            return
        }

        if fromOnboardingCompletion {
            lastSeenVersion = currentVersion
            return
        }

        if releases.first(where: { $0.version == currentVersion }) != nil {
            AppLogger.info("[WhatsNew] showing sheet for version \(currentVersion)", category: AppLogger.ui)
            needsWhatsNew = true
        } else {
            AppLogger.info("[WhatsNew] no release entry for version \(currentVersion), marking seen", category: AppLogger.ui)
            lastSeenVersion = currentVersion
        }
    }

    func dismiss() {
        lastSeenVersion = currentVersion
        needsWhatsNew = false
    }

    func reset() {
        lastSeenVersion = ""
        needsWhatsNew = false
        currentVersion = ""
    }
}
