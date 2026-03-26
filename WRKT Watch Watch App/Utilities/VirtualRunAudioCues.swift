import WatchKit

@MainActor
final class VirtualRunAudioCues {
    static let shared = VirtualRunAudioCues()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "virtualRunAudioCuesEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "virtualRunAudioCuesEnabled") }
    }

    private init() {
        if UserDefaults.standard.object(forKey: "virtualRunAudioCuesEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "virtualRunAudioCuesEnabled")
        }
    }

    // 1 buzz — you took the lead
    // 2 buzzes — partner took the lead
    func announceLeadChange(isLeading: Bool) {
        guard isEnabled else { return }
        if isLeading {
            buzz(count: 1)
        } else {
            buzz(count: 2, gap: 0.12)
        }
    }

    // 3 rapid buzzes — kilometer milestone
    func announceKilometer(_ km: Int) {
        guard isEnabled else { return }
        buzz(count: 3, gap: 0.10)
    }

    // 2 slower buzzes — partner finished
    func announcePartnerFinished() {
        guard isEnabled else { return }
        buzz(count: 2, gap: 0.25)
    }

    // MARK: - Private

    private func buzz(count: Int, gap: Double = 0) {
        guard count > 0 else { return }
        Task {
            for i in 0..<count {
                WKInterfaceDevice.current().play(.notification)
                if i < count - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
                }
            }
        }
    }
}
