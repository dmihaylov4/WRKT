//
//  RewardsHubView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


import SwiftUI
import SwiftData

struct RewardsHubView: View {
    @Query(sort: \RewardLedgerEntry.occurredAt, order: .reverse)
    private var ledger: [RewardLedgerEntry]

    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse)
    private var achievements: [Achievement]

    @Query private var progress: [RewardProgress]   // single row "global"

    var body: some View {
        List {
            if let p = progress.first {
                Section("Profile") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Level \(p.level)").dsFont(.headline)
                            Text("XP \(p.xp) • Next at \(p.nextLevelXP)")
                                .foregroundStyle(.secondary)
                                .dsFont(.footnote)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Text("Streak \(p.currentStreak)")
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                        .dsFont(.headline)
                    }
                }
            }

            Section("Achievements") {
                ForEach(achievements) { a in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(a.title).dsFont(.subheadline, weight: .semibold)
                            Text(a.desc).dsFont(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let when = a.unlockedAt {
                            Text(when, style: .date).dsFont(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(a.progress)/\(a.target)")
                                .dsFont(.caption, monospacedDigits: true)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Recent rewards") {
                ForEach(ledger.prefix(50)) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.event.replacingOccurrences(of: "_", with: " ").capitalized)
                                .dsFont(.subheadline, weight: .medium)
                            if let m = e.metadataJSON, !m.isEmpty {
                                Text(m).dsFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        let parts = [e.deltaXP != 0 ? "XP \(e.deltaXP)" : nil,
                                     e.deltaCoins != 0 ? "Coins \(e.deltaCoins)" : nil].compactMap { $0 }
                        Text(parts.joined(separator: " • "))
                            .dsFont(.caption, monospacedDigits: true).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Rewards")
    }
}
