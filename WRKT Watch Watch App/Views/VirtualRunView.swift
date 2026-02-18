//
//  VirtualRunView.swift
//  WRKT Watch
//
//  Split-screen view with HR zone visualization, confirmation, countdown,
//  and swipeable End Run screen
//

import SwiftUI
import WatchKit

struct VirtualRunView: View {
    var isLuminanceReduced: Bool = false

    @Environment(VirtualRunManager.self) var manager

    private var healthManager: WatchHealthKitManager {
        WatchHealthKitManager.shared
    }

    var body: some View {
        if isLuminanceReduced {
            alwaysOnView
        } else {
            switch manager.phase {
            case .idle:
                EmptyView()
            case .pendingConfirmation:
                confirmationView
            case .countdown(let seconds):
                countdownView(seconds: seconds)
            case .active, .paused:
                activeView
            }
        }
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "figure.run")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Virtual Run")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(manager.pendingRunInfo?.partner.displayName ?? "Partner")
                .font(.system(size: 20, weight: .bold))

            Spacer()

            Button {
                manager.confirmRun()
            } label: {
                Text("Go!")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.green)
                    )
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Button {
                manager.declineRun()
            } label: {
                Text("Decline")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Countdown View

    private func countdownView(seconds: Int) -> some View {
        VStack(spacing: 8) {
            Spacer()

            Text("Run with")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text(manager.partnerStats?.displayName ?? "Partner")
                .font(.system(size: 16, weight: .semibold))

            Text("\(seconds)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .contentTransition(.numericText())
                .animation(.default, value: seconds)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Active View

    private var activeView: some View {
        ZStack {
            TabView {
                runPage
                timerPage
                controlsPage
            }
            .tabViewStyle(.verticalPage)

            // Pause overlay
            if manager.phase == .paused {
                pausedOverlay
            }

            // Extended disconnect prompt
            if manager.showDisconnectPrompt {
                disconnectPromptOverlay
            }

            // Partner finished overlay
            if manager.showPartnerFinished {
                partnerFinishedOverlay
            }
        }
    }

    // MARK: - Page 1: Run (split-screen: My Stats top / Partner bottom)

    private var runPage: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let _ = manager.partnerStats?.interpolate()
            VStack(spacing: 0) {
                MySection(
                    stats: manager.myStats,
                    maxHR: manager.myMaxHR
                )
                ZoneBar()
                    .frame(height: 14)
                PartnerSection(partner: manager.partnerStats)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Page 2: Timer

    private var timerPage: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            VStack(spacing: 8) {
                Spacer()

                Text("DURATION")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1.5)

                if let start = manager.runStartTime {
                    let elapsed = context.date.timeIntervalSince(start) - manager.pausedElapsedBeforePause
                    let duration = max(0, Int(elapsed))
                    let h = duration / 3600
                    let m = (duration % 3600) / 60
                    let s = duration % 60

                    if h > 0 {
                        Text(String(format: "%d:%02d:%02d", h, m, s))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text(String(format: "%02d:%02d", m, s))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                } else {
                    Text("00:00")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                }

                // Distance summary underneath
                let distance = healthManager.distance > 0
                    ? healthManager.distance
                    : (manager.myStats?.distanceM ?? 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(formatDistanceValue(distance))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(formatDistanceUnit(distance))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white.opacity(0.7))

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    // MARK: - Page 3: Controls

    private var controlsPage: some View {
        VStack(spacing: 10) {
            Spacer()

            // Pause / Resume button
            Button {
                if manager.phase == .paused {
                    manager.resumeRun()
                } else {
                    manager.pauseRun()
                }
            } label: {
                let isPaused = manager.phase == .paused
                Label(isPaused ? "Resume" : "Pause",
                      systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(manager.phase == .paused ? Color.green : Color.orange)
                    )
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Button {
                manager.requestEndRun()
            } label: {
                Text("End Run")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Text("Partner will be notified")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    WatchConnectivityManager.shared.transferLogFile()
                } label: {
                    Label("Logs", systemImage: "arrow.up.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Button {
                    VirtualRunAudioCues.shared.isEnabled.toggle()
                } label: {
                    Label(
                        VirtualRunAudioCues.shared.isEnabled ? "Audio" : "Muted",
                        systemImage: VirtualRunAudioCues.shared.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VirtualRunAudioCues.shared.isEnabled ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Paused Overlay

    private var pausedOverlay: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("PAUSED")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.orange)
            Text("Tap Resume to continue")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                manager.resumeRun()
            } label: {
                Text("Resume")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.green)
                    )
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
    }

    // MARK: - Disconnect Prompt

    private var disconnectPromptOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("Partner Lost")
                .font(.system(size: 18, weight: .bold))
            Text("Disconnected 3+ min")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                manager.requestEndRun()
            } label: {
                Text("End Run")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Button {
                manager.dismissDisconnectPrompt()
            } label: {
                Text("Keep Waiting")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
    }

    // MARK: - Partner Finished Overlay

    private var partnerFinishedOverlay: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "flag.checkered")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("Partner Finished!")
                .font(.system(size: 16, weight: .bold))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatDistanceValue(manager.partnerFinalDistance))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text(formatDistanceUnit(manager.partnerFinalDistance))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let pace = manager.partnerFinalPace {
                Text("\(formatPace(pace)) /km")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                manager.requestEndRun()
            } label: {
                Text("End My Run")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.green)
                    )
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Button {
                manager.dismissPartnerFinished()
            } label: {
                Text("Keep Going")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
    }

    // MARK: - Always-On Display

    private var alwaysOnView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch manager.phase {
            case .active:
                activeAlwaysOnContent
            case .paused:
                VStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange.opacity(0.5))
                    Text("PAUSED")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.orange.opacity(0.4))
                }
            case .countdown(let s):
                Text("\(s)")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(.green.opacity(0.5))
            case .pendingConfirmation:
                VStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 24))
                        .foregroundStyle(.green.opacity(0.4))
                    Text("Incoming Run")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            case .idle:
                EmptyView()
            }
        }
    }

    private var activeAlwaysOnContent: some View {
        VStack(spacing: 4) {
            Spacer()

            // My distance
            let distance = healthManager.distance > 0
                ? healthManager.distance
                : (manager.myStats?.distanceM ?? 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatDistanceValue(distance))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.green.opacity(0.5))
                Text(formatDistanceUnit(distance))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.green.opacity(0.3))
            }

            // Duration
            if let start = manager.runStartTime {
                TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                    Text(formatDuration(Int(ctx.date.timeIntervalSince(start))))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            // HR
            if healthManager.heartRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.4))
                    Text("\(Int(healthManager.heartRate))")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Separator
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 60, height: 1)
                .padding(.vertical, 2)

            // Partner info
            if let partner = manager.partnerStats {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.3))
                    Text(partner.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(formatDistanceValue(partner.displayDistanceM))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(formatDistanceUnit(partner.displayDistanceM))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - My Section (top half of split screen)

private struct MySection: View {
    let stats: VirtualRunSnapshot?
    let maxHR: Int

    private var healthManager: WatchHealthKitManager { WatchHealthKitManager.shared }

    private var heartRate: Int {
        let hk = Int(healthManager.heartRate)
        return hk > 0 ? hk : (stats?.heartRate ?? 0)
    }

    private var distance: Double {
        let hk = healthManager.distance
        return hk > 0 ? hk : (stats?.distanceM ?? 0)
    }

    private var pace: Int? {
        if let p = stats?.currentPaceSecPerKm, p > 0, p <= 1800 { return p }
        let dur = stats?.durationS ?? Int(healthManager.elapsedTime)
        guard dur > 10, distance > 50 else { return nil }
        let raw = Int((Double(dur) / distance) * 1000)
        return raw > 1800 ? nil : raw
    }

    private var zone: HRZone { HRZoneHelper.zone(for: heartRate, maxHR: maxHR) }

    var body: some View {
        VStack(spacing: 2) {
            // HR pinned left
            HStack(spacing: 3) {
                Text(heartRate > 0 ? "\(heartRate)" : "--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Spacer(minLength: 0)

            // Distance
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatDistanceValue(distance))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(formatDistanceUnit(distance))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Pace
            Text(pace.map { "\(formatPace($0)) /km" } ?? "--:-- /km")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(zone.number > 0 ? zone.color : Color.black)
        .animation(.easeInOut(duration: 0.8), value: zone.number)
    }
}

// MARK: - Partner Section (bottom half of split screen)

private struct PartnerSection: View {
    let partner: PartnerStats?

    private var zone: HRZone {
        guard let p = partner, let hr = p.heartRate, hr > 0 else {
            return HRZone(number: 0, name: "", color: .clear)
        }
        return HRZoneHelper.zone(for: hr, maxHR: p.maxHR)
    }

    var body: some View {
        VStack(spacing: 2) {
            // Partner name + connection status + HR
            HStack(spacing: 4) {
                // HR pinned left
                if let p = partner, let hr = p.heartRate, hr > 0 {
                    Text("\(hr)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                } else {
                    Text("--")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red.opacity(0.4))
                }

                Spacer()

                Image(systemName: "figure.run")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                Text(partner?.displayName ?? "Partner")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                if let p = partner {
                    connectionStatus(p)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            Spacer(minLength: 0)

            // Distance
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatDistanceValue(partner?.displayDistanceM ?? 0))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(formatDistanceUnit(partner?.displayDistanceM ?? 0))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Pace
            if let pace = partner?.currentPaceSecPerKm {
                Text("\(formatPace(pace)) /km")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                Text("--:-- /km")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(zone.number > 0 ? zone.color : Color.black)
        .animation(.easeInOut(duration: 0.8), value: zone.number)
    }

    @ViewBuilder
    private func connectionStatus(_ p: PartnerStats) -> some View {
        let (text, color): (String, Color) = {
            switch p.connectionStatus {
            case .connected: return ("Live", .green)
            case .stale: return ("\(Int(p.dataAge))s", .orange)
            case .disconnected: return ("Lost", .red)
            case .paused: return ("Paused", .orange)
            }
        }()
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
    }
}

// MARK: - Zone Bar (5 HR zone blocks between sections)

private struct ZoneBar: View {
    private static let colors: [Color] = [.blue, .green, .yellow, .orange, .red]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle()
                    .fill(Self.colors[i])
            }
        }
    }
}

// MARK: - Formatting

private func formatPace(_ s: Int) -> String {
    String(format: "%d:%02d", s / 60, s % 60)
}

private func formatDuration(_ s: Int) -> String {
    String(format: "%02d:%02d", s / 60, s % 60)
}

private func formatDistanceValue(_ m: Double) -> String {
    m < 1000 ? String(format: "%.0f", m) : String(format: "%.2f", m / 1000)
}

private func formatDistanceUnit(_ m: Double) -> String {
    m < 1000 ? "m" : "km"
}
