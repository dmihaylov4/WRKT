import AVFoundation

/// Persistent AVAudioSession for iPhone during an active virtual run.
///
/// The session is held open for the entire run — not for audio playback, but to prevent
/// iOS from suspending the app when the screen locks. Without an active session the
/// Supabase WebSocket and WCSession relay both die. No audio is played on the iPhone;
/// haptic cues are handled on the Watch via VirtualRunAudioCues.
@MainActor
final class iPhoneVirtualRunAudioCues {
    static let shared = iPhoneVirtualRunAudioCues()

    private var isSessionActive = false

    private init() {}

    // MARK: - Session Lifecycle

    func startSession() {
        guard !isSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.mixWithOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            isSessionActive = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
        } catch {
            AppLogger.error("[iPhoneVRAudio] Failed to activate session: \(error)", category: AppLogger.virtualRun)
        }
    }

    func endSession() {
        guard isSessionActive else { return }
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSessionActive = false
    }

    // MARK: - Cues (no-ops — haptics handled on Watch)

    func announceKilometer(_ km: Int) {}
    func announceLeadChange(isLeading: Bool) {}
    func announcePartnerFinished() {}

    // MARK: - Private

    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue),
              type == .ended, isSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
