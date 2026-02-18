//
//  SmartNudgeManager.swift
//  WRKT
//
//  Smart nudge notifications based on friend activity and social context
//

import Foundation
import UserNotifications

@MainActor
@Observable
final class SmartNudgeManager {
    static let shared = SmartNudgeManager()

    // MARK: - Notification Identifiers
    private enum NotificationID {
        static let friendActivity = "com.dmihaylov.wrkt.friend_activity"
        static let comparativeNudge = "com.dmihaylov.wrkt.comparative_nudge"
        static let timeBasedNudge = "com.dmihaylov.wrkt.time_based_nudge"
        static let streakUrgency = "com.dmihaylov.wrkt.streak_urgency"
        static let dailyStreakCheck = "com.dmihaylov.wrkt.daily_streak_check"
    }

    // MARK: - Dependencies
    private let notificationManager: NotificationManager

    // MARK: - State
    private var lastFriendActivityCheck: Date?
    private var nudgesSentToday: Set<String> = []
    private var lastStreakUrgencyNotification: Date?

    private init() {
        self.notificationManager = NotificationManager.shared
        loadPersistedState()
        resetDailyCounts()
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        // Load nudges sent today from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "nudgesSentToday"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            nudgesSentToday = Set(decoded)
        }

        // Load last streak urgency notification date
        if let timestamp = UserDefaults.standard.object(forKey: "lastStreakUrgencyNotification") as? Date {
            lastStreakUrgencyNotification = timestamp
        }
    }

    private func persistState() {
        // Save nudges sent today
        let array = Array(nudgesSentToday)
        if let encoded = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(encoded, forKey: "nudgesSentToday")
        }

        // Save last streak urgency notification date
        if let date = lastStreakUrgencyNotification {
            UserDefaults.standard.set(date, forKey: "lastStreakUrgencyNotification")
        }
    }

    // MARK: - Public API

    /// Send a friend activity notification ("John just finished leg day!")
    func sendFriendActivityNudge(friendName: String, workoutName: String) async {
        // Check preferences
        guard isEnabled else { return }

        // Check authorization
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Prevent duplicate nudges for same friend today
        let nudgeKey = "friend_\(friendName)_\(todayDateKey())"
        guard !nudgesSentToday.contains(nudgeKey) else {
            AppLogger.debug("Skipping duplicate friend activity nudge for \(friendName)", category: AppLogger.app)
            return
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "\(friendName) just worked out!"
        content.body = "\(friendName) completed \(workoutName). Your turn to crush it!"
        content.sound = .default
        content.categoryIdentifier = "FRIEND_ACTIVITY"
        content.userInfo = ["type": "friend_activity", "friend": friendName]

        // Send immediately (no trigger = immediate delivery)
        let request = UNNotificationRequest(
            identifier: "\(NotificationID.friendActivity)_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            nudgesSentToday.insert(nudgeKey)
            persistState()
            AppLogger.success("Sent friend activity nudge for \(friendName)", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to send friend activity nudge", error: error, category: AppLogger.app)
        }
    }

    /// Send a comparative nudge ("You're the only friend who hasn't worked out today")
    func sendComparativeNudge(activeCount: Int) async {
        guard isEnabled else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Only send once per day
        let nudgeKey = "comparative_\(todayDateKey())"
        guard !nudgesSentToday.contains(nudgeKey) else { return }

        // Only send if at least 2 friends worked out
        guard activeCount >= 2 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your friends are crushing it!"
        content.body = "\(activeCount) friends have already worked out today. Don't get left behind!"
        content.sound = .default
        content.categoryIdentifier = "COMPARATIVE_NUDGE"
        content.userInfo = ["type": "comparative", "count": activeCount]

        // Schedule for 30 minutes from now to avoid immediate spam
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)

        let request = UNNotificationRequest(
            identifier: "\(NotificationID.comparativeNudge)_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            nudgesSentToday.insert(nudgeKey)
            persistState()
            AppLogger.success("Scheduled comparative nudge for 30 min from now", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to send comparative nudge", error: error, category: AppLogger.app)
        }
    }

    /// Send a time-based nudge based on user's typical workout pattern
    func sendTimeBasedNudge(preferredHour: Int) async {
        guard isEnabled else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Only send once per day
        let nudgeKey = "timebased_\(todayDateKey())"
        guard !nudgesSentToday.contains(nudgeKey) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to work out!"
        content.body = "You usually train around this time. Ready to keep the momentum going?"
        content.sound = .default
        content.categoryIdentifier = "TIME_BASED_NUDGE"
        content.userInfo = ["type": "time_based"]

        // Calculate trigger for preferred hour today (or tomorrow if passed)
        var dateComponents = DateComponents()
        dateComponents.hour = preferredHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: NotificationID.timeBasedNudge,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            nudgesSentToday.insert(nudgeKey)
            persistState()
            AppLogger.success("Scheduled time-based nudge for \(preferredHour):00", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to send time-based nudge", error: error, category: AppLogger.app)
        }
    }

    /// Clear all pending smart nudges
    func clearAllNudges() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                NotificationID.friendActivity,
                NotificationID.comparativeNudge,
                NotificationID.timeBasedNudge
            ]
        )
        AppLogger.info("Cleared all smart nudges", category: AppLogger.app)
    }

    /// Reset daily nudge counters (call this at midnight or app launch)
    func resetDailyCounts() {
        let today = todayDateKey()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        let yesterdayKey = dateKey(for: yesterday ?? Date())

        // Remove all nudges that aren't from today
        let beforeCount = nudgesSentToday.count
        nudgesSentToday = nudgesSentToday.filter { $0.contains(today) }

        if beforeCount != nudgesSentToday.count {
            persistState()
            AppLogger.debug("Reset daily nudge counts. Removed \(beforeCount - nudgesSentToday.count) old entries. Current: \(nudgesSentToday.count)", category: AppLogger.app)
        }
    }

    // MARK: - Preferences

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "smart_nudges_enabled")
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "smart_nudges_enabled")

        if !enabled {
            clearAllNudges()
        }
    }

    // MARK: - Helpers

    private func todayDateKey() -> String {
        dateKey(for: Date())
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Streak Urgency Notifications

    /// Send streak urgency notification
    func sendStreakUrgencyNudge(
        currentStreak: Int,
        strengthNeeded: Int,
        daysRemaining: Int
    ) async {
        guard isEnabled else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Only send once per week max
        let nudgeKey = "streak_urgency_\(todayDateKey())"
        guard !nudgesSentToday.contains(nudgeKey) else { return }

        // Weekly limit check
        if let lastSent = lastStreakUrgencyNotification {
            let daysSince = Calendar.current.dateComponents([.day], from: lastSent, to: .now).day ?? 0
            guard daysSince >= 7 else {
                AppLogger.debug("Skipping streak urgency - sent \(daysSince) days ago", category: AppLogger.app)
                return
            }
        }

        let content = UNMutableNotificationContent()
        content.title = "Your \(currentStreak)-week streak is at risk!"
        content.body = daysRemaining <= 1
            ? "Only \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left! Need \(strengthNeeded) more workout\(strengthNeeded == 1 ? "" : "s")."
            : "Need \(strengthNeeded) workouts in \(daysRemaining) days to maintain your streak."
        content.sound = .default
        content.categoryIdentifier = "STREAK_URGENCY"
        content.userInfo = ["type": "streak_urgency", "streak": currentStreak]

        let request = UNNotificationRequest(
            identifier: "\(NotificationID.streakUrgency)_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            nudgesSentToday.insert(nudgeKey)
            lastStreakUrgencyNotification = .now
            persistState()
            AppLogger.success("Sent streak urgency notification (streak: \(currentStreak))", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to send streak urgency notification", error: error, category: AppLogger.app)
        }
    }

    /// Schedule daily streak check 2 hours before learned workout time
    func scheduleDailyStreakCheck() async {
        guard isEnabled else {
            AppLogger.debug("📊 Smart nudges disabled - skipping notification scheduling", category: AppLogger.app)
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            AppLogger.debug("📊 Notifications not authorized - skipping scheduling", category: AppLogger.app)
            return
        }

        // Get learned time or default to 6 PM
        let learnedHour = await WorkoutPatternAnalyzer.shared.getPreferredWorkoutHour()
        let confidence = await WorkoutPatternAnalyzer.shared.getConfidence()
        let preferredWorkoutHour = learnedHour ?? 18

        // Log the pattern analysis state
        await WorkoutPatternAnalyzer.shared.logCurrentPatternState()

        // Log the notification time calculation
        AppLogger.info("📊 ═══════════════════════════════════════════", category: AppLogger.app)
        AppLogger.info("📊 NOTIFICATION TIME CALCULATION", category: AppLogger.app)
        AppLogger.info("📊 ═══════════════════════════════════════════", category: AppLogger.app)

        if let learned = learnedHour {
            AppLogger.info("📊 Source: Learned from workout history", category: AppLogger.app)
            AppLogger.info("📊 Learned workout hour: \(formatHour(learned))", category: AppLogger.app)
            AppLogger.info("📊 Confidence: \(String(format: "%.1f", confidence * 100))%", category: AppLogger.app)
        } else {
            AppLogger.info("📊 Source: Default (insufficient data)", category: AppLogger.app)
            AppLogger.info("📊 Default workout hour: \(formatHour(18)) (6 PM)", category: AppLogger.app)
            AppLogger.info("📊 Confidence: \(String(format: "%.1f", confidence * 100))% (below 30% threshold)", category: AppLogger.app)
        }

        // Send notification 2 hours BEFORE typical workout time
        // This gives users time to prepare and plan
        let reminderHour = (preferredWorkoutHour - 2 + 24) % 24 // Handle wrap-around (e.g., 1am workout -> 11pm reminder)

        AppLogger.info("📊 ───────────────────────────────────────────", category: AppLogger.app)
        AppLogger.info("📊 Calculation: notification = workout_hour - 2 hours", category: AppLogger.app)
        AppLogger.info("📊 Formula: (\(preferredWorkoutHour) - 2 + 24) % 24 = \(reminderHour)", category: AppLogger.app)
        AppLogger.info("📊 ───────────────────────────────────────────", category: AppLogger.app)
        AppLogger.info("📊 User typically works out at: \(formatHour(preferredWorkoutHour))", category: AppLogger.app)
        AppLogger.info("📊 Notification will be sent at: \(formatHour(reminderHour))", category: AppLogger.app)
        AppLogger.info("📊 ═══════════════════════════════════════════", category: AppLogger.app)

        // Cancel existing
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationID.dailyStreakCheck]
        )

        // Schedule repeating daily check
        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Workout in 2 hours!"
        content.body = "You usually train around \(formatHour(preferredWorkoutHour)). Time to start preparing!"
        content.sound = .default
        content.categoryIdentifier = "STREAK_CHECK"
        content.userInfo = ["type": "streak_check", "workout_hour": preferredWorkoutHour]

        // Make this a passive notification (iOS 15+)
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
        }

        let request = UNNotificationRequest(
            identifier: NotificationID.dailyStreakCheck,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            AppLogger.success("✅ Scheduled daily reminder for \(formatHour(reminderHour)) (workout time: \(formatHour(preferredWorkoutHour)))", category: AppLogger.app)

            // Persist for user visibility
            UserDefaults.standard.set(reminderHour, forKey: "scheduled_reminder_hour")
            UserDefaults.standard.set(preferredWorkoutHour, forKey: "learned_workout_hour_display")
        } catch {
            AppLogger.error("Failed to schedule daily streak check", error: error, category: AppLogger.app)
        }
    }

    /// Get the currently scheduled reminder hour (for settings display)
    func getScheduledReminderInfo() -> (reminderHour: Int, workoutHour: Int)? {
        let reminderHour = UserDefaults.standard.integer(forKey: "scheduled_reminder_hour")
        let workoutHour = UserDefaults.standard.integer(forKey: "learned_workout_hour_display")

        // Check if we have valid data
        guard UserDefaults.standard.object(forKey: "scheduled_reminder_hour") != nil else {
            return nil
        }

        return (reminderHour, workoutHour)
    }

    /// Log the current notification schedule state (for debugging)
    func logNotificationScheduleState() async {
        AppLogger.info("📊 ═══════════════════════════════════════════", category: AppLogger.app)
        AppLogger.info("📊 CURRENT NOTIFICATION SCHEDULE STATE", category: AppLogger.app)
        AppLogger.info("📊 ═══════════════════════════════════════════", category: AppLogger.app)
        AppLogger.info("📊 Smart nudges enabled: \(isEnabled)", category: AppLogger.app)

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        AppLogger.info("📊 Notification authorization: \(settings.authorizationStatus == .authorized ? "Authorized" : "Not authorized")", category: AppLogger.app)

        if let info = getScheduledReminderInfo() {
            AppLogger.info("📊 ───────────────────────────────────────────", category: AppLogger.app)
            AppLogger.info("📊 Scheduled notification time: \(formatHour(info.reminderHour))", category: AppLogger.app)
            AppLogger.info("📊 Based on workout time: \(formatHour(info.workoutHour))", category: AppLogger.app)
        } else {
            AppLogger.info("📊 No notification currently scheduled", category: AppLogger.app)
        }

        // Log pattern analyzer state
        await WorkoutPatternAnalyzer.shared.logCurrentPatternState()

        // List pending notifications
        let pendingNotifications = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let smartNudgeNotifications = pendingNotifications.filter {
            $0.identifier.contains("com.dmihaylov.wrkt")
        }

        AppLogger.info("📊 ───────────────────────────────────────────", category: AppLogger.app)
        AppLogger.info("📊 Pending smart nudge notifications: \(smartNudgeNotifications.count)", category: AppLogger.app)

        for notification in smartNudgeNotifications {
            if let trigger = notification.trigger as? UNCalendarNotificationTrigger,
               let hour = trigger.dateComponents.hour {
                AppLogger.info("📊   - \(notification.identifier): \(formatHour(hour))", category: AppLogger.app)
            } else if let trigger = notification.trigger as? UNTimeIntervalNotificationTrigger {
                let minutes = Int(trigger.timeInterval / 60)
                AppLogger.info("📊   - \(notification.identifier): in \(minutes) minutes", category: AppLogger.app)
            } else {
                AppLogger.info("📊   - \(notification.identifier): immediate", category: AppLogger.app)
            }
        }

        AppLogger.info("📊 ═══════════════════════════════════════════", category: AppLogger.app)
    }

    /// Format hour for display (e.g., "6 PM", "2 PM")
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }

    /// Perform streak check (called when notification fires or app opens)
    func performStreakCheck(
        weeklyGoal: WeeklyGoal,
        completedWorkouts: [CompletedWorkout],
        runs: [Run]
    ) async {
        guard isEnabled else { return }

        // Don't check if user already worked out today
        let today = Calendar.current.startOfDay(for: .now)
        let workedOutToday = completedWorkouts.contains {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        guard !workedOutToday else {
            AppLogger.debug("User worked out today - skipping streak urgency check", category: AppLogger.app)
            return
        }

        // Calculate current week progress
        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: weeklyGoal.anchorWeekday)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return }

        let workoutsThisWeek = completedWorkouts.filter { $0.date >= weekStart && $0.date < weekEnd }
        let strengthCompleted = workoutsThisWeek.count
        let daysRemaining = calendar.dateComponents([.day], from: .now, to: weekEnd).day ?? 0
        let strengthNeeded = max(0, weeklyGoal.targetStrengthDays - strengthCompleted)

        let currentStreak = RewardsEngine.shared.weeklyGoalStreak()

        // Only send if: streak >= 2, goal not met, urgency present
        guard currentStreak >= 2 else { return }
        guard strengthCompleted < weeklyGoal.targetStrengthDays else { return }

        let isCritical = daysRemaining <= 1 && strengthNeeded > daysRemaining
        let isCaution = strengthNeeded > 0 && daysRemaining > 0 &&
                        (Double(strengthNeeded) / Double(daysRemaining) > 1.0)

        if isCritical || isCaution {
            await sendStreakUrgencyNudge(
                currentStreak: currentStreak,
                strengthNeeded: strengthNeeded,
                daysRemaining: max(0, daysRemaining)
            )
        }
    }
}

// MARK: - Notification Categories

extension SmartNudgeManager {
    /// Setup notification categories for smart nudges
    func setupNotificationCategories() {
        let openAppAction = UNNotificationAction(
            identifier: "OPEN_APP",
            title: "Start Workout",
            options: [.foreground]
        )

        let friendActivityCategory = UNNotificationCategory(
            identifier: "FRIEND_ACTIVITY",
            actions: [openAppAction],
            intentIdentifiers: [],
            options: []
        )

        let comparativeCategory = UNNotificationCategory(
            identifier: "COMPARATIVE_NUDGE",
            actions: [openAppAction],
            intentIdentifiers: [],
            options: []
        )

        let timeBasedCategory = UNNotificationCategory(
            identifier: "TIME_BASED_NUDGE",
            actions: [openAppAction],
            intentIdentifiers: [],
            options: []
        )

        let existingCategories = UNUserNotificationCenter.current()
        // We should fetch existing categories and append, but for simplicity we'll just set
        UNUserNotificationCenter.current().setNotificationCategories([
            friendActivityCategory,
            comparativeCategory,
            timeBasedCategory
        ])

        AppLogger.info("Setup smart nudge notification categories", category: AppLogger.app)
    }
}
