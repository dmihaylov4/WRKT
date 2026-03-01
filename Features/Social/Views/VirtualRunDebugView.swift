//
//  VirtualRunDebugView.swift
//  WRKT
//
//  Debug view for testing the virtual run invite → accept → live sync → end flow
//  using a single device. Simulates partner snapshots locally.
//

#if DEBUG

import SwiftUI
import Supabase


struct VirtualRunDebugView: View {
    @EnvironmentObject var authService: SupabaseAuthService
    @Environment(\.dependencies) private var dependencies

    private var repo: VirtualRunRepository { dependencies.virtualRunRepository }

    // MARK: - State

    @State private var currentRun: VirtualRun?
    @State private var runStatus: VirtualRunStatus?
    @State private var latestSnapshot: VirtualRunSnapshot?
    @State private var simTimer: Timer?
    @State private var simSeq: Int = 0
    @State private var simDistance: Double = 0
    @State private var logEntries: [LogEntry] = []
    @State private var watchLogFiles: [URL] = []
    @State private var selectedLogItem: LogContentItem?
    @State private var showingShareSheet = false
    @State private var shareURL: URL?

    private struct LogContentItem: Identifiable {
        let id = UUID()
        let content: String
    }

    private let testUserId = UUID(uuidString: "4d610949-c039-4441-a8c3-58e4806f45d1")!

    private var currentUserId: UUID? { authService.currentUser?.id }

    // MARK: - Body

    var body: some View {
        Form {
            statusSection
            actionsSection
            liveDataSection
            watchLogsSection
            logSection
        }
        .navigationTitle("Virtual Run Debug")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshWatchLogs() }
        .onDisappear { stopSimulation() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WatchVRLogReceived"))) { _ in
            refreshWatchLogs()
        }
        .sheet(item: $selectedLogItem) { item in
            NavigationStack {
                WatchLogContentView(content: item.content)
                    .navigationTitle("Watch Log")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { selectedLogItem = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Run ID") {
                Text(currentRun?.id.uuidString.prefix(8).description ?? "none")
                    .monospaced()
            }
            LabeledContent("Status") {
                Text(runStatus?.rawValue ?? "none")
                    .foregroundStyle(statusColor)
            }
            LabeledContent("Current User") {
                Text(currentUserId?.uuidString.prefix(8).description ?? "not logged in")
                    .monospaced()
            }
            LabeledContent("Test Partner") {
                Text(testUserId.uuidString.prefix(8).description)
                    .monospaced()
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section("Actions") {
            Button("Create Invite") { Task { await createInvite() } }
                .disabled(currentUserId == nil || currentRun != nil)

            Button("Accept Invite") { Task { await acceptInvite() } }
                .disabled(runStatus != .pending)

            Button("Start Partner Sim") { startSimulation() }
                .disabled(runStatus != .active || simTimer != nil)

            Button("Stop Simulation") { stopSimulation() }
                .disabled(simTimer == nil)

            Button("End Run") { Task { await endRun() } }
                .disabled(runStatus != .active)

            Button("Cleanup", role: .destructive) { Task { await cleanup() } }
                .disabled(currentRun == nil)
        }
    }

    // MARK: - Live Data Section

    private var liveDataSection: some View {
        Section("Live Partner Data") {
            if let snap = latestSnapshot {
                LabeledContent("Distance") {
                    Text(String(format: "%.1f m", snap.distanceM))
                        .monospaced()
                }
                LabeledContent("Duration") {
                    Text("\(snap.durationS)s")
                        .monospaced()
                }
                if let pace = snap.currentPaceSecPerKm {
                    LabeledContent("Pace") {
                        let mins = pace / 60
                        let secs = pace % 60
                        Text(String(format: "%d:%02d /km", mins, secs))
                            .monospaced()
                    }
                }
                if let hr = snap.heartRate {
                    LabeledContent("Heart Rate") {
                        Text("\(hr) bpm")
                            .monospaced()
                    }
                }
                LabeledContent("Seq") {
                    Text("#\(snap.seq)")
                        .monospaced()
                }
                LabeledContent("Age") {
                    let age = Date().timeIntervalSince(snap.clientRecordedAt)
                    Text(String(format: "%.1fs", age))
                        .monospaced()
                }
            } else {
                Text("No snapshots received")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Watch Logs Section

    private var watchLogsSection: some View {
        Section("Watch Logs") {
            if watchLogFiles.isEmpty {
                Text("No watch logs received")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(watchLogFiles, id: \.lastPathComponent) { file in
                    Button {
                        if let data = FileManager.default.contents(atPath: file.path),
                           let content = String(data: data, encoding: .utf8) {
                            selectedLogItem = LogContentItem(content: content)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.lastPathComponent)
                                    .font(.caption)
                                    .monospaced()
                                    .lineLimit(1)
                                if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int {
                                    Text("\(size / 1024) KB")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button {
                                shareURL = file
                                showingShareSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indices in
                    for index in indices {
                        try? FileManager.default.removeItem(at: watchLogFiles[index])
                    }
                    refreshWatchLogs()
                }
            }
        }
    }

    private func refreshWatchLogs() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WatchVRLogs", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else {
            watchLogFiles = []
            return
        }
        watchLogFiles = files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
    }

    // MARK: - Log Section

    private var logSection: some View {
        Section("Log") {
            if logEntries.isEmpty {
                Text("No events yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logEntries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospaced()
                        Text(entry.message)
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func createInvite() async {
        guard let userId = currentUserId else {
            log("No current user — log in first")
            return
        }
        do {
            let run = try await repo.sendInvite(to: testUserId, from: userId)
            currentRun = run
            runStatus = .pending
            log("Created invite: \(run.id.uuidString.prefix(8))")
        } catch {
            log("Create invite failed: \(error.localizedDescription)")
        }
    }

    private func acceptInvite() async {
        guard let runId = currentRun?.id else {
            log("No run to accept")
            return
        }
        do {
            let run = try await repo.acceptInvite(runId)
            currentRun = run
            runStatus = .active
            log("Accepted invite — status active")

            // Subscribe to Realtime snapshots — only forward partner's, not our own
            let myId = currentUserId
            let channelId = await repo.subscribeToSnapshots(runId: runId) { snapshot in
                if let myId, snapshot.userId == myId { return }
                Task { @MainActor in
                    latestSnapshot = snapshot
                    log("Snapshot received: seq=\(snapshot.seq) dist=\(String(format: "%.1f", snapshot.distanceM))m")

                    // Forward partner snapshots to Watch
                    WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                }
            }
            log("Subscribed to channel: \(channelId)")

            // Fetch partner's profile for maxHR, then notify Watch
            if let myUserId = currentUserId {
                var partnerMaxHR = 190
                if let partnerProfile = try? await authService.fetchProfile(userId: testUserId) {
                    partnerMaxHR = partnerProfile.maxHR
                    log("Partner maxHR: \(partnerMaxHR) (birth year: \(partnerProfile.birthYear.map { String($0) } ?? "nil"))")
                }
                WatchConnectivityManager.shared.sendVirtualRunStarted(
                    runId: runId,
                    partnerId: testUserId,
                    partnerName: "Test Partner",
                    myUserId: myUserId,
                    partnerMaxHR: partnerMaxHR
                )
            }
            log("Sent virtual run start to Watch")
        } catch {
            log("Accept invite failed: \(error.localizedDescription)")
        }
    }

    private func startSimulation() {
        guard let runId = currentRun?.id, let userId = currentUserId else {
            log("Cannot start sim — no active run or user")
            return
        }

        simSeq = 0
        simDistance = 0
        // Note: RLS requires user_id = auth.uid(), so we publish as ourselves.
        // This tests the publish flow but won't show as "partner" data.
        // For true partner simulation, use two devices.
        log("Starting simulation (publishing as current user due to RLS)")

        // Publish snapshot every 3s simulating ~5:00/km pace (3.33 m/s)
        // Note: server_received_at MUST be explicitly set — the DB trigger
        // enforce_snapshot_rate_limit fires on both INSERT and UPDATE.
        // On UPSERT conflict→UPDATE, if server_received_at is omitted from
        // the JSON, PostgREST won't include it in the SET clause, so
        // NEW.server_received_at == OLD.server_received_at → diff = 0 → rate limit hit.
        let currentUser = userId
        let repository = repo
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            simSeq += 1
            simDistance += 10.0 // ~3.33 m/s * 3s
            let hr = Int.random(in: 145...165)

            let snapshot = VirtualRunSnapshot(
                virtualRunId: runId,
                userId: currentUser,  // Must be current user due to RLS policy
                distanceM: simDistance,
                durationS: simSeq * 3,
                currentPaceSecPerKm: 300, // 5:00/km
                heartRate: hr,
                calories: simSeq * 3,
                latitude: nil,
                longitude: nil,
                seq: simSeq,
                clientRecordedAt: Date(),
                serverReceivedAt: Date()
            )

            Task { @MainActor in
                do {
                    try await repository.publishSnapshot(snapshot)

                    // For single-device testing: directly update UI and forward to Watch
                    // (Supabase Realtime may not echo back your own changes)
                    latestSnapshot = snapshot
                    WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                } catch {
                    print("Publish failed: \(error.localizedDescription)")
                }
            }
        }

        simTimer = timer
        log("Simulation started — publishing every 3s")
    }

    private func stopSimulation() {
        simTimer?.invalidate()
        simTimer = nil
        log("Simulation stopped at seq=\(simSeq), dist=\(String(format: "%.1f", simDistance))m")
    }

    private func endRun() async {
        guard let runId = currentRun?.id else {
            log("No run to end")
            return
        }

        stopSimulation()
        await repo.unsubscribeFromSnapshots()

        let summary = RunSummary(
            inviterDistanceM: simDistance,
            inviterDurationS: simSeq * 2,
            inviterAvgPaceSecPerKm: 300,
            inviterAvgHeartRate: 155,
            inviteeDistanceM: 0,
            inviteeDurationS: 0,
            inviteeAvgPaceSecPerKm: nil,
            inviteeAvgHeartRate: nil,
            winnerId: currentUserId
        )

        do {
            try await repo.endRun(runId, summary: summary)
            runStatus = .completed
            log("Run ended — status completed")

            // Notify Watch to end virtual run
            WatchConnectivityManager.shared.sendVirtualRunEnded()
            log("Sent virtual run end to Watch")
        } catch {
            log("End run failed: \(error.localizedDescription)")
        }
    }

    private func cleanup() async {
        guard let runId = currentRun?.id else {
            log("No run to clean up")
            return
        }

        stopSimulation()
        await repo.unsubscribeFromSnapshots()

        do {
            // Delete snapshots first
            try await SupabaseClientWrapper.shared.client
                .from("virtual_run_snapshots")
                .delete()
                .eq("virtual_run_id", value: runId.uuidString)
                .execute()

            // Delete the run
            try await SupabaseClientWrapper.shared.client
                .from("virtual_runs")
                .delete()
                .eq("id", value: runId.uuidString)
                .execute()

            currentRun = nil
            runStatus = nil
            latestSnapshot = nil
            simSeq = 0
            simDistance = 0
            log("Cleaned up run \(runId.uuidString.prefix(8)) and snapshots")
        } catch {
            log("Cleanup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch runStatus {
        case .pending: return .orange
        case .active: return .green
        case .completed: return .blue
        case .cancelled: return .red
        case nil: return .secondary
        }
    }

    private func log(_ message: String) {
        logEntries.insert(LogEntry(message: message), at: 0)
    }
}

// MARK: - Log Entry

private struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
}

// MARK: - Watch Log Content View

/// Handles large JSONL log files by showing only the last N lines in a LazyVStack.
private struct WatchLogContentView: View {
    let content: String

    private let maxLines = 500

    private var lines: [String] {
        let allLines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if allLines.count > maxLines {
            return ["--- Showing last \(maxLines) of \(allLines.count) lines ---"] + Array(allLines.suffix(maxLines))
        }
        return allLines
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(formatLogLine(line))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func formatLogLine(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw
        }
        let ts = (json["ts"] as? String)?.suffix(12).description ?? ""  // HH:mm:ss.SSS
        let cat = (json["cat"] as? String) ?? ""
        let msg = (json["msg"] as? String) ?? ""
        var result = "\(ts) [\(cat)] \(msg)"
        if let extra = json["data"] as? [String: Any],
           let extraData = try? JSONSerialization.data(withJSONObject: extra),
           let extraStr = String(data: extraData, encoding: .utf8) {
            result += " \(extraStr)"
        }
        return result
    }
}

#endif
