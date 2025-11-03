//
//  HealthKitSyncProgress.swift
//  WRKT
//
//  Progress indicator for HealthKit sync operations
//

import SwiftUI

private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = DS.Theme.accent
}

struct HealthKitSyncProgressView: View {
    @ObservedObject var healthKit: HealthKitManager

    var body: some View {
        if healthKit.isSyncing {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Syncing Health Data")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)

                        if healthKit.syncTotalCount > 0 {
                            Text("Batch \(healthKit.syncCurrentBatch)/\(healthKit.syncTotalBatches) • \(healthKit.syncProcessedCount)/\(healthKit.syncTotalCount) workouts")
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        } else {
                            Text("Preparing...")
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        }
                    }

                    Spacer()

                    if healthKit.syncTotalCount > 0 {
                        Text("\(Int(healthKit.syncProgress * 100))%")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                }

                // Progress bar
                if healthKit.syncTotalCount > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.surface2)
                                .frame(height: 6)

                            // Foreground
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.accent)
                                .frame(
                                    width: geometry.size.width * healthKit.syncProgress,
                                    height: 6
                                )
                                .animation(.easeInOut(duration: 0.3), value: healthKit.syncProgress)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// Compact version for toolbar
struct HealthKitSyncProgressCompact: View {
    @ObservedObject var healthKit: HealthKitManager

    var body: some View {
        if healthKit.isSyncing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)

                if healthKit.syncTotalCount > 0 {
                    Text("\(healthKit.syncProcessedCount)/\(healthKit.syncTotalCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
    }
}

// Color extension
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:(a, r, g, b) = (255, 244, 228, 9)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
