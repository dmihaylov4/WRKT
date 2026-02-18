import AVFoundation
import WatchKit

@MainActor
final class VirtualRunAudioCues {
    static let shared = VirtualRunAudioCues()

    private let synthesizer = AVSpeechSynthesizer()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "virtualRunAudioCuesEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "virtualRunAudioCuesEnabled") }
    }

    private init() {
        // Default to enabled on first launch
        if UserDefaults.standard.object(forKey: "virtualRunAudioCuesEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "virtualRunAudioCuesEnabled")
        }
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
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.volume = 0.8
        synthesizer.speak(utterance)
    }
}
