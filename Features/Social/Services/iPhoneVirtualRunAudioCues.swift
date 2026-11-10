import AVFoundation

/// Persistent AVAudioSession for iPhone during an active virtual run.
///
/// Keeps the session open for the entire run so iOS does not suspend the app when the
/// screen locks (WebSocket and WCSession relay both die without an active session).
/// Delivers spoken audio cues (kilometer milestones, lead changes, partner finish) via
/// AVSpeechSynthesizer; haptic cues are handled separately on the Watch.
@MainActor
final class iPhoneVirtualRunAudioCues {
    static let shared = iPhoneVirtualRunAudioCues()

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "iPhoneVRAudioEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "iPhoneVRAudioEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "iPhoneVRAudioEnabled") }
    }

    private var isSessionActive = false
    private let synthesizer = AVSpeechSynthesizer()

    /// Continuous silent loop that keeps the app alive in the background for the whole run.
    /// The `audio` background mode only grants execution while audio is actively playing, and
    /// the spoken cues are sparse (kilometer marks, lead changes, finish). Without a continuous
    /// track, iOS suspends the app between cues when the screen is locked, dropping the Supabase
    /// WebSocket and WCSession relay. The spoken cues mix on top of this silent track.
    private var keepAlivePlayer: AVAudioPlayer?

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
            startKeepAliveLoop()
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
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSessionActive = false
    }

    // MARK: - Background Keep-Alive

    private func startKeepAliveLoop() {
        guard keepAlivePlayer == nil else { return }
        do {
            let player = try AVAudioPlayer(data: Self.silentLoopData, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1   // loop for the entire run
            player.volume = 0           // inaudible; spoken cues mix on top
            player.prepareToPlay()
            player.play()
            keepAlivePlayer = player
        } catch {
            AppLogger.error("[iPhoneVRAudio] Failed to start keep-alive loop: \(error)", category: AppLogger.virtualRun)
        }
    }

    /// In-memory silent WAV (16-bit PCM, mono, 44.1 kHz) generated once and looped.
    private static let silentLoopData: Data = makeSilentWAV(seconds: 1.0)

    private static func makeSilentWAV(seconds: Double) -> Data {
        let sampleRate = 44_100
        let channels = 1
        let bitsPerSample = 16
        let frameCount = Int(Double(sampleRate) * seconds)
        let dataSize = frameCount * channels * (bitsPerSample / 8)
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var data = Data()
        func appendString(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func appendUInt32LE(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        func appendUInt16LE(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }

        appendString("RIFF")
        appendUInt32LE(UInt32(36 + dataSize))
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32LE(16)                       // PCM header size
        appendUInt16LE(1)                        // PCM format
        appendUInt16LE(UInt16(channels))
        appendUInt32LE(UInt32(sampleRate))
        appendUInt32LE(UInt32(byteRate))
        appendUInt16LE(UInt16(blockAlign))
        appendUInt16LE(UInt16(bitsPerSample))
        appendString("data")
        appendUInt32LE(UInt32(dataSize))
        data.append(Data(count: dataSize))       // silence (zero samples)
        return data
    }

    // MARK: - Cues

    func announceKilometer(_ km: Int) {
        speak("Kilometer \(km)")
    }

    func announceLeadChange(isLeading: Bool) {
        speak(isLeading ? "You're in the lead" : "Partner is ahead")
    }

    func announcePartnerFinished() {
        speak("Your partner has finished")
    }

    // MARK: - Private

    private func speak(_ text: String) {
        guard isSessionActive, isEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue),
              type == .ended, isSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        // The interruption paused the keep-alive loop — restart it so background execution holds.
        keepAlivePlayer?.play()
    }
}
