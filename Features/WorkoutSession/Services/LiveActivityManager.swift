import Foundation
import ActivityKit

@MainActor
struct RestTimerActivityClient {
    struct Reference {
        let id: String
        let timerID: UUID?
    }

    var activities: () -> [Reference]
    var areEnabled: () -> Bool
    var request: (RestTimerAttributes, RestTimerAttributes.ContentState) throws -> Void
    var update: (String, RestTimerAttributes.ContentState) async -> Void
    var end: (String) async -> Void

    static let live = RestTimerActivityClient(
        activities: {
            Activity<RestTimerAttributes>.activities.map { Reference(id: $0.id, timerID: $0.attributes.timerID) }
        },
        areEnabled: { ActivityAuthorizationInfo().areActivitiesEnabled },
        request: { attributes, state in
            _ = try Activity<RestTimerAttributes>.request(attributes: attributes,
                content: .init(state: state, staleDate: nil), pushType: nil)
        },
        update: { id, state in
            await Activity<RestTimerAttributes>.activities.first(where: { $0.id == id })?
                .update(.init(state: state, staleDate: nil))
        },
        end: { id in
            await Activity<RestTimerAttributes>.activities.first(where: { $0.id == id })?
                .end(nil, dismissalPolicy: .immediate)
        }
    )
}

/// Projects committed timer records into ActivityKit in order. No timer or delayed
/// task here changes workout state or assumes the process will run at countdown zero.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private let client: RestTimerActivityClient
    private var pendingUpdate: Task<Void, Never>?
    private var latestRevision: UInt64?
    private var latestRequest = UUID()

    init(client: RestTimerActivityClient = .live) {
        self.client = client
    }

    func reconcile(_ record: RestTimerRecord, errorMessage: String? = nil) {
        if let latestRevision, record.revision < latestRevision { return }
        latestRevision = record.revision
        let request = UUID()
        latestRequest = request
        let previous = pendingUpdate
        pendingUpdate = Task {
            await previous?.value
            guard latestRequest == request else { return }
            await present(record, request: request, errorMessage: errorMessage)
        }
    }

    func waitForUpdates() async {
        await pendingUpdate?.value
    }

    private func present(_ record: RestTimerRecord, request: UUID, errorMessage: String?) async {
        let activities = client.activities()
        let isIdle = record.state == .idle
        let current = activities.first { !isIdle && $0.timerID == record.id }
        for activity in activities where activity.id != current?.id {
            await client.end(activity.id)
            guard latestRequest == request else { return }
        }
        guard !isIdle, latestRequest == request else { return }
        let now = Date()
        let exerciseID: String
        let exerciseName: String
        let endDate: Date
        let remaining: TimeInterval
        let duration: TimeInterval
        let paused: Bool
        let adjusted: Bool
        switch record.state {
        case .running(let end, let id, let name, let original, let wasAdjusted):
            (exerciseID, exerciseName, endDate) = (id, name, end)
            (remaining, duration, paused, adjusted) = (max(0, end.timeIntervalSince(now)), original, false, wasAdjusted)
        case .paused(let seconds, let id, let name, let original, let wasAdjusted):
            (exerciseID, exerciseName, endDate) = (id, name, now.addingTimeInterval(seconds))
            (remaining, duration, paused, adjusted) = (seconds, original, true, wasAdjusted)
        case .completed(let id, let name):
            (exerciseID, exerciseName, endDate) = (id, name, now)
            (remaining, duration, paused, adjusted) = (0, record.nextRestDuration, false, false)
        case .idle:
            return
        }
        let state = RestTimerAttributes.ContentState(
            remainingSeconds: Int(ceil(remaining)), endDate: endDate, isPaused: paused,
            progress: duration > 0 ? min(1, max(0, remaining / duration)) : 0,
            wasAdjusted: adjusted, lastUpdate: now, errorMessage: errorMessage
        )
        if let current {
            await client.update(current.id, state)
        } else if client.areEnabled(), case .running = record.state {
            // Do not recreate a dismissed activity just to display a past completion.
            guard remaining > 0 else { return }
            let attributes = RestTimerAttributes(exerciseName: exerciseName, originalDuration: Int(duration),
                exerciseID: exerciseID, workoutName: nil, startTime: record.startedAt ?? now, timerID: record.id)
            do {
                try client.request(attributes, state)
            } catch {
                AppLogger.error("Could not present rest timer activity: \(error)", category: AppLogger.app)
            }
        }
    }
}
