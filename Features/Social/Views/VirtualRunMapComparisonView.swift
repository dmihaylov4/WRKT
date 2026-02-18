//
//  VirtualRunMapComparisonView.swift
//  WRKT
//
//  Dual-map comparison view showing side-by-side route maps with HR color
//  gradients and stat overlays for both virtual run participants.
//

import SwiftUI
import UIKit
import HealthKit

struct VirtualRunMapComparisonView: View {
    let data: VirtualRunCompletionData
    let onDismiss: () -> Void

    @State private var myMapImage: UIImage?
    @State private var partnerMapImage: UIImage?
    @State private var myRouteError = false
    @State private var partnerRouteError = false
    @State private var isLoadingMyRoute = true
    @State private var isLoadingPartnerRoute = true
    @State private var isRetryingMyRoute = false
    @State private var isRetryingPartnerRoute = false

    // Staggered reveal
    @State private var showMyLabel = false
    @State private var showMyMap = false
    @State private var showMyStats = false
    @State private var showPartnerLabel = false
    @State private var showPartnerMap = false
    @State private var showPartnerStats = false
    @State private var showButton = false

    private let mapSize = CGSize(width: 400, height: 200)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Spacer().frame(height: 40)

                    // My route card
                    routeCard(
                        label: "YOU",
                        mapImage: myMapImage,
                        isLoading: isLoadingMyRoute,
                        hasError: myRouteError,
                        isRetrying: isRetryingMyRoute,
                        distance: data.myDistanceM,
                        pace: data.myPaceSecPerKm,
                        hr: data.myAvgHR,
                        showLabel: showMyLabel,
                        showMap: showMyMap,
                        showStats: showMyStats,
                        onRetry: retryMyRoute
                    )

                    // Partner route card
                    routeCard(
                        label: shortenedName(data.partnerName).uppercased(),
                        mapImage: partnerMapImage,
                        isLoading: isLoadingPartnerRoute,
                        hasError: partnerRouteError,
                        isRetrying: isRetryingPartnerRoute,
                        distance: data.partnerDistanceM,
                        pace: data.partnerPaceSecPerKm,
                        hr: data.partnerAvgHR,
                        showLabel: showPartnerLabel,
                        showMap: showPartnerMap,
                        showStats: showPartnerStats,
                        onRetry: retryPartnerRoute
                    )

                    // Continue button
                    if showButton {
                        Button {
                            Haptics.light()
                            onDismiss()
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                        .background(DS.Theme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer().frame(height: 16)
                }
            }
        }
        .task { await loadRoutes() }
        .onAppear { startStaggeredReveal() }
    }

    // MARK: - Route Card

    @ViewBuilder
    private func routeCard(
        label: String,
        mapImage: UIImage?,
        isLoading: Bool,
        hasError: Bool,
        isRetrying: Bool,
        distance: Double,
        pace: Int?,
        hr: Int?,
        showLabel: Bool,
        showMap: Bool,
        showStats: Bool,
        onRetry: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            if showLabel {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }

            // Map
            if showMap {
                ZStack {
                    if let image = mapImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(2, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if hasError {
                        noRouteCard(isRetrying: isRetrying, onRetry: onRetry)
                    } else if isLoading {
                        loadingCard()
                    } else {
                        noRouteCard(isRetrying: isRetrying, onRetry: onRetry)
                    }
                }
                .padding(.horizontal, 20)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            // Stats pills
            if showStats {
                HStack(spacing: 8) {
                    statPill(formatDistance(distance))
                    statPill(formatPace(pace))
                    if let hr = hr, hr > 0 {
                        statPill("\(hr) \u{2665}")
                    }
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private func loadingCard() -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.06))
            .aspectRatio(2, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading route...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
    }

    private func noRouteCard(isRetrying: Bool, onRetry: @escaping () -> Void) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.06))
            .aspectRatio(2, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No route recorded")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))

                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 4)
                    } else {
                        Button {
                            onRetry()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DS.Theme.accent)
                        }
                        .padding(.top, 4)
                    }
                }
            }
    }

    private func statPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Staggered Reveal

    private func startStaggeredReveal() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showMyLabel = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showMyMap = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showMyStats = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPartnerLabel = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPartnerMap = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPartnerStats = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showButton = true
            }
        }
    }

    // MARK: - Route Loading

    private func loadRoutes() async {
        let repo = getRepository()

        let userId = await getCurrentUserId()
        guard let myId = userId else {
            AppLogger.warning("Map comparison: no current user ID", category: AppLogger.virtualRun)
            isLoadingMyRoute = false
            isLoadingPartnerRoute = false
            return
        }

        let run = try? await repo.fetchRun(byId: data.runId)
        let partnerId = run.flatMap { $0.inviterId == myId ? $0.inviteeId : $0.inviterId }
        AppLogger.info("Map comparison: loading routes. myId=\(myId), partnerId=\(partnerId?.uuidString ?? "nil")", category: AppLogger.virtualRun)

        async let myRoute = loadMyRoute(repo: repo, myId: myId)
        async let partnerRoute = loadPartnerRoute(repo: repo, partnerId: partnerId)

        _ = await (myRoute, partnerRoute)
    }

    /// Load my route using HKAnchoredObjectQuery observer that fires when route data syncs
    private func loadMyRoute(repo: VirtualRunRepository, myId: UUID) async {
        // Step 1: Find the workout (syncs much faster than route data)
        var workout: HKWorkout?
        for attempt in 1...18 {
            workout = try? await findRecentRunningWorkout()
            if workout != nil {
                AppLogger.info("Map: found my workout on attempt \(attempt)", category: AppLogger.virtualRun)
                break
            }
            if attempt < 18 {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }

        guard let workout else {
            AppLogger.warning("Map: no recent workout found after 3 min, trying Supabase", category: AppLogger.virtualRun)
            if let image = await tryDownloadFromSupabase(repo: repo, userId: myId) {
                myMapImage = image
                isLoadingMyRoute = false
                return
            }
            AppLogger.error("Map: my route unavailable from both HK and Supabase", category: AppLogger.virtualRun)
            myRouteError = true
            isLoadingMyRoute = false
            return
        }

        // Step 2: Wait for route data using observer query
        if let image = await waitForRouteData(workout: workout, repo: repo, userId: myId) {
            myMapImage = image
            isLoadingMyRoute = false
            return
        }

        AppLogger.warning("Map: HK observer timed out, trying Supabase fallback", category: AppLogger.virtualRun)
        if let image = await tryDownloadFromSupabase(repo: repo, userId: myId) {
            myMapImage = image
            isLoadingMyRoute = false
            return
        }

        AppLogger.error("Map: my route unavailable after all attempts", category: AppLogger.virtualRun)
        myRouteError = true
        isLoadingMyRoute = false
    }

    /// Wait for route data to sync using HKAnchoredObjectQuery with update handler.
    private func waitForRouteData(workout: HKWorkout, repo: VirtualRunRepository, userId: UUID) async -> UIImage? {
        let store = HealthKitManager.shared.store

        // First check if route data is already available
        if let image = await tryRenderRoute(for: workout, repo: repo, userId: userId) {
            AppLogger.success("Map: route already available in HK", category: AppLogger.virtualRun)
            return image
        }

        AppLogger.info("Map: waiting for HK route data via observer query...", category: AppLogger.virtualRun)

        // Use HKAnchoredObjectQuery to get notified when route samples arrive
        let lock = NSLock()
        return await withCheckedContinuation { continuation in
            var didResume = false
            let routeType = HKSeriesType.workoutRoute()

            let query = HKAnchoredObjectQuery(
                type: routeType,
                predicate: HKQuery.predicateForObjects(from: workout),
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, _, _, _, _ in }

            query.updateHandler = { [weak store] _, addedObjects, _, _, _ in
                guard let routes = addedObjects as? [HKWorkoutRoute], !routes.isEmpty else { return }

                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()

                store?.stop(query)
                AppLogger.success("Map: HK observer fired — route data synced", category: AppLogger.virtualRun)

                Task { @MainActor in
                    let image = await self.tryRenderRoute(for: workout, repo: repo, userId: userId)
                    continuation.resume(returning: image)
                }
            }

            store.execute(query)

            // Timeout after 5 minutes
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()

                store.stop(query)
                AppLogger.warning("Map: HK observer timed out after 5 min", category: AppLogger.virtualRun)
                continuation.resume(returning: nil)
            }
        }
    }

    /// Try to fetch and render route from HealthKit. Uploads to Supabase on success.
    private func tryRenderRoute(for workout: HKWorkout, repo: VirtualRunRepository, userId: UUID) async -> UIImage? {
        do {
            let routePoints = try await HealthKitManager.shared.fetchRouteWithHeartRate(for: workout)
            guard !routePoints.isEmpty else {
                AppLogger.info("Map: HK returned empty route for workout \(workout.uuid)", category: AppLogger.virtualRun)
                return nil
            }

            let image = try await MapSnapshotService.shared.generateRouteSnapshot(
                coordinates: routePoints.coordinates,
                hrValues: routePoints.heartRates,
                size: mapSize
            )

            // Upload to Supabase so partner can see it
            let runId = data.runId
            Task.detached {
                do {
                    let routeData = VirtualRunRouteData.from(
                        routePoints: routePoints,
                        userId: userId,
                        runId: runId,
                        runStartDate: workout.startDate
                    )
                    try await repo.uploadRoute(runId: runId, userId: userId, routeData: routeData)
                    AppLogger.success("Map: uploaded my route to Supabase (\(routeData.points.count) pts)", category: AppLogger.virtualRun)
                } catch {
                    AppLogger.error("Map: failed to upload route: \(error.localizedDescription)", category: AppLogger.virtualRun)
                }
            }

            return image
        } catch {
            AppLogger.error("Map: failed to render route: \(error.localizedDescription)", category: AppLogger.virtualRun)
            return nil
        }
    }

    private func tryDownloadFromSupabase(repo: VirtualRunRepository, userId: UUID) async -> UIImage? {
        do {
            guard let routeData = try await repo.downloadRoute(runId: data.runId, userId: userId) else {
                AppLogger.info("Map: no route in Supabase for user \(userId)", category: AppLogger.virtualRun)
                return nil
            }
            let image = try await generateSnapshot(from: routeData)
            AppLogger.success("Map: rendered route from Supabase (\(routeData.points.count) pts)", category: AppLogger.virtualRun)
            return image
        } catch {
            AppLogger.error("Map: Supabase download/render failed: \(error.localizedDescription)", category: AppLogger.virtualRun)
            return nil
        }
    }

    /// Find most recent running workout from local HealthKit (within last 15 minutes)
    private func findRecentRunningWorkout() async throws -> HKWorkout? {
        let store = HealthKitManager.shared.store
        let lookback = Date().addingTimeInterval(-900)

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForSamples(withStart: lookback, end: Date(), options: []),
                HKQuery.predicateForWorkouts(with: .running)
            ])
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: results?.first as? HKWorkout)
            }

            store.execute(query)
        }
    }

    /// Load partner route from Supabase (polls until uploaded or timeout)
    private func loadPartnerRoute(repo: VirtualRunRepository, partnerId: UUID?) async {
        guard let partnerId else {
            AppLogger.warning("Map: no partner ID for route download", category: AppLogger.virtualRun)
            isLoadingPartnerRoute = false
            partnerRouteError = true
            return
        }

        AppLogger.info("Map: polling for partner route (partner=\(partnerId))...", category: AppLogger.virtualRun)

        let maxPolls = 36
        let pollInterval: UInt64 = 10_000_000_000

        for attempt in 1...maxPolls {
            do {
                if let routeData = try await repo.downloadRoute(runId: data.runId, userId: partnerId) {
                    let image = try await generateSnapshot(from: routeData)
                    AppLogger.success("Map: partner route loaded on attempt \(attempt) (\(routeData.points.count) pts)", category: AppLogger.virtualRun)
                    partnerMapImage = image
                    isLoadingPartnerRoute = false
                    return
                }
            } catch {
                if attempt == 1 || attempt % 6 == 0 {
                    AppLogger.info("Map: partner route poll \(attempt)/\(maxPolls) — not yet available", category: AppLogger.virtualRun)
                }
            }

            if attempt < maxPolls {
                try? await Task.sleep(nanoseconds: pollInterval)
            }
        }

        AppLogger.warning("Map: partner route not available after \(maxPolls) polls", category: AppLogger.virtualRun)
        partnerRouteError = true
        isLoadingPartnerRoute = false
    }

    private func generateSnapshot(from routeData: VirtualRunRouteData) async throws -> UIImage {
        let coordinates = routeData.coordinates
        let hrValues = routeData.heartRates

        return try await MapSnapshotService.shared.generateRouteSnapshot(
            coordinates: coordinates,
            hrValues: hrValues,
            size: mapSize
        )
    }

    // MARK: - Retry

    private func retryMyRoute() {
        guard !isRetryingMyRoute else { return }
        isRetryingMyRoute = true
        myRouteError = false

        Task {
            let repo = getRepository()
            guard let myId = await getCurrentUserId() else {
                myRouteError = true
                isRetryingMyRoute = false
                return
            }

            // Try local HealthKit — by retry time, route has likely synced
            if let workout = try? await findRecentRunningWorkout(),
               let image = await tryRenderRoute(for: workout, repo: repo, userId: myId) {
                myMapImage = image
                myRouteError = false
                isRetryingMyRoute = false
                return
            }

            // Fallback: Supabase download
            if let image = await tryDownloadFromSupabase(repo: repo, userId: myId) {
                myMapImage = image
                myRouteError = false
            } else {
                myRouteError = true
            }
            isRetryingMyRoute = false
        }
    }

    private func retryPartnerRoute() {
        guard !isRetryingPartnerRoute else { return }
        isRetryingPartnerRoute = true
        partnerRouteError = false

        Task {
            let repo = getRepository()
            guard let myId = await getCurrentUserId() else {
                partnerRouteError = true
                isRetryingPartnerRoute = false
                return
            }

            let run = try? await repo.fetchRun(byId: data.runId)
            let partnerId = run.flatMap { $0.inviterId == myId ? $0.inviteeId : $0.inviterId }

            guard let partnerId else {
                partnerRouteError = true
                isRetryingPartnerRoute = false
                return
            }

            if let routeData = try? await repo.downloadRoute(runId: data.runId, userId: partnerId),
               let image = try? await generateSnapshot(from: routeData) {
                partnerMapImage = image
                partnerRouteError = false
            } else {
                partnerRouteError = true
            }
            isRetryingPartnerRoute = false
        }
    }

    // MARK: - Helpers

    private func getRepository() -> VirtualRunRepository {
        WatchConnectivityManager.shared.virtualRunRepository ?? VirtualRunRepository()
    }

    private func getCurrentUserId() async -> UUID? {
        SupabaseAuthService.shared.currentUser?.id
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters <= 0 { return "--" }
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters))m"
    }

    private func formatPace(_ secPerKm: Int?) -> String {
        guard let pace = secPerKm, pace > 0 else { return "--" }
        let m = pace / 60
        let s = pace % 60
        return String(format: "%d:%02d/km", m, s)
    }

    private func shortenedName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if let first = parts.first { return String(first) }
        return name
    }
}
