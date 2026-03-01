import AVFoundation
import WatchKit

@MainActor
final class VirtualRunAudioCues: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VirtualRunAudioCues()

    private let synthesizer = AVSpeechSynthesizer()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "virtualRunAudioCuesEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "virtualRunAudioCuesEnabled") }
    }

    private override init() {
        super.init()
        // Default to enabled on first launch
        if UserDefaults.standard.object(forKey: "virtualRunAudioCuesEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "virtualRunAudioCuesEnabled")
        }
        synthesizer.delegate = self
    }

    func announceKilometer(_ km: Int) {
        guard isEnabled else { return }
        let text = km == 1 ? "1 kilometer" : "\(km) kilometers"
        speak(text)
    }

    func announcePartnerFinished() {
        guard isEnabled else { return }
        speak("Partner finished")
    }

    func announceLeadChange(isLeading: Bool) {
        guard isEnabled else { return }
        let text = isLeading ? "You took the lead" : "Partner took the lead"
        speak(text)
    }

    private func speak(_ text: String) {
        // Configure audio session to duck music instead of interrupting it
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // If audio session setup fails, skip speech rather than crash
            return
        }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.volume = 0.8
        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    // nonisolated is intentional: AVSpeechSynthesizerDelegate is called on a background thread
    // and AVAudioSession is documented as thread-safe. Do NOT wrap in Task { @MainActor in } —
    // deactivating asynchronously would race with the next utterance starting.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Deactivate audio session after speech ends to restore music volume
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
