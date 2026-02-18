//
//  AppSettings.swift
//  WRKT
//
//  Global app settings using @AppStorage for persistence
//

import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    // Local mode settings
    @AppStorage("hasSkippedSocial") var hasSkippedSocial: Bool = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage("localUserID") var localUserID: String? {
        didSet { objectWillChange.send() }
    }

    @AppStorage("localUsername") var localUsername: String? {
        didSet { objectWillChange.send() }
    }

    static let shared = AppSettings()

    private init() {}

    /// Enable local-only mode (no social features)
    func enableLocalMode() {
        hasSkippedSocial = true
        localUserID = UUID().uuidString
        localUsername = "User_\(String(UUID().uuidString.prefix(8)))"
    }

    /// Disable local mode and prepare for social features
    func disableLocalMode() {
        hasSkippedSocial = false
        // Don't clear localUserID - might need for data migration
    }

    /// Check if app is in local-only mode
    var isLocalMode: Bool {
        return hasSkippedSocial && localUserID != nil
    }
}
