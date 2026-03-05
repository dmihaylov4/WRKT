import AVFoundation

/// Persistent AVAudioSession + spoken cues for iPhone during an active virtual run.
///
/// Unlike the Watch's `VirtualRunAudioCues` (which activates/deactivates per-utterance
/// because `workout-processing` keeps the Watch alive), this class holds the session open
/// for the entire run. That persistent session is what prevents iOS from suspending the
/// app when the screen locks, keeping the Supabase WebSocket and WCSession relay alive.
@MainActor
final class iPhoneVirtualRunAudioCues: NSObject {
    static let shared = iPhoneVirtualRunAudioCues()

    private let synthesizer = AVSpeechSynthesizer()
    private var isSessionActive = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iPhoneVRAudioCuesEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "iPhoneVRAudioCuesEnabled") }
    }

    private override init() {
        super.init()
        if UserDefaults.standard.object(forKey: "iPhoneVRAudioCuesEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "iPhoneVRAudioCuesEnabled")
        }
        synthesizer.delegate = self
    }

    // MARK: - Session Lifecycle

    func startSession() {
        guard !isSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
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
        synthesizer.stopSpeaking(at: .immediate)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSessionActive = false
    }

    // MARK: - Cues

    func announceKilometer(_ km: Int) {
        guard isEnabled, isSessionActive else { return }
        speak(km == 1 ? "1 kilometer" : "\(km) kilometers")
    }

    func announceLeadChange(isLeading: Bool) {
        guard isEnabled, isSessionActive else { return }
        speak(isLeading ? "You took the lead" : "Partner took the lead")
    }

    func announcePartnerFinished() {
        guard isEnabled, isSessionActive else { return }
        speak("Partner finished")
    }

    // MARK: - Private

    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.volume = 0.8
        synthesizer.speak(utterance)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue),
              type == .ended, isSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

extension iPhoneVirtualRunAudioCues: AVSpeechSynthesizerDelegate {
    // Session stays active between cues — do NOT deactivate here.
    // (Watch's VirtualRunAudioCues deactivates here because workout-processing keeps it alive.)
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {}
}
