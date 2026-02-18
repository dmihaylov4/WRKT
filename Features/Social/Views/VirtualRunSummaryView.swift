//
//  VirtualRunSummaryView.swift
//  WRKT
//
//  Head-to-head summary screen shown after a virtual run completes.
//  Staggered "slamming" animation on stat rows with winner highlighting.
//

import SwiftUI

struct VirtualRunSummaryView: View {
    let data: VirtualRunCompletionData
    let onDismiss: () -> Void
    var showDismissButton: Bool = true

    // Staggered reveal state
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var revealedRows: Set<Int> = []
    @State private var showButton = false

    private var statRows: [StatRow] {
        [
            StatRow(
                label: "DISTANCE",
                myValue: formatDistance(data.myDistanceM),
                partnerValue: formatDistance(data.partnerDistanceM),
                myWins: data.myDistanceM > data.partnerDistanceM,
                partnerWins: data.partnerDistanceM > data.myDistanceM
            ),
            StatRow(
                label: "DURATION",
                myValue: formatDuration(data.myDurationS),
                partnerValue: formatDuration(data.partnerDurationS),
                myWins: data.myDurationS > data.partnerDurationS,
                partnerWins: data.partnerDurationS > data.myDurationS
            ),
            StatRow(
                label: "PACE",
                myValue: formatPace(data.myPaceSecPerKm),
                partnerValue: formatPace(data.partnerPaceSecPerKm),
                // Lower pace is better
                myWins: comparePace(mine: data.myPaceSecPerKm, partner: data.partnerPaceSecPerKm) == .myWin,
                partnerWins: comparePace(mine: data.myPaceSecPerKm, partner: data.partnerPaceSecPerKm) == .partnerWin
            ),
            StatRow(
                label: "AVG HR",
                myValue: formatHR(data.myAvgHR),
                partnerValue: formatHR(data.partnerAvgHR),
                // Higher HR = worked harder, highlight as "winner"
                myWins: compareOptionalInt(mine: data.myAvgHR, partner: data.partnerAvgHR) == .myWin,
                partnerWins: compareOptionalInt(mine: data.myAvgHR, partner: data.partnerAvgHR) == .partnerWin
            )
        ]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                // Icon
                if showIcon {
                    Image(systemName: "figure.run")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(DS.Theme.accent)
                        .symbolEffect(.bounce, options: .repeat(1))
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer().frame(height: 16)

                // Title + subtitle
                if showTitle {
                    Text("Virtual Run Complete")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    Text("You vs \(data.partnerName)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 32)

                // Stat rows
                VStack(spacing: 0) {
                    ForEach(Array(statRows.enumerated()), id: \.offset) { index, row in
                        if revealedRows.contains(index) {
                            VStack(spacing: 0) {
                                if index > 0 {
                                    Divider().background(.white.opacity(0.08))
                                }
                                StatRowView(
                                    row: row,
                                    partnerName: shortenedName(data.partnerName)
                                )
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
                .padding(.horizontal, 20)

                Spacer()

                // Continue button or swipe hint
                if showButton {
                    if showDismissButton {
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
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Text("Swipe for route maps →")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear { startStaggeredReveal() }
    }

    // MARK: - Animation Sequence

    private func startStaggeredReveal() {
        // T+0.0s: Icon
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showIcon = true
        }

        // T+0.3s: Title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showTitle = true
            }
        }

        // T+0.6s onwards: Stat rows (150ms apart)
        for i in 0..<statRows.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 0.15) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    revealedRows.insert(i)
                }
                Haptics.medium()
            }
        }

        // T+1.3s: Continue button
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showButton = true
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatDistance(_ meters: Double) -> String {
        if meters <= 0 { return "--" }
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters))m"
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "--" }
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatPace(_ secPerKm: Int?) -> String {
        guard let pace = secPerKm, pace > 0 else { return "--" }
        let m = pace / 60
        let s = pace % 60
        return String(format: "%d:%02d/km", m, s)
    }

    private func formatHR(_ hr: Int?) -> String {
        guard let hr = hr, hr > 0 else { return "--" }
        return "\(hr) bpm"
    }

    private func shortenedName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if let first = parts.first { return String(first) }
        return name
    }

    private enum CompareResult { case myWin, partnerWin, tie }

    private func comparePace(mine: Int?, partner: Int?) -> CompareResult {
        guard let m = mine, m > 0, let p = partner, p > 0 else { return .tie }
        if m < p { return .myWin }      // lower pace = faster
        if p < m { return .partnerWin }
        return .tie
    }

    private func compareOptionalInt(mine: Int?, partner: Int?) -> CompareResult {
        guard let m = mine, m > 0, let p = partner, p > 0 else { return .tie }
        if m > p { return .myWin }
        if p > m { return .partnerWin }
        return .tie
    }
}

// MARK: - Stat Row Model

private struct StatRow {
    let label: String
    let myValue: String
    let partnerValue: String
    let myWins: Bool
    let partnerWins: Bool
}

// MARK: - Stat Row View

private struct StatRowView: View {
    let row: StatRow
    let partnerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            HStack {
                // My value
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.myValue)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(row.myWins ? DS.Theme.accent : .white)
                    Text("You")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                // Partner value
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.partnerValue)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(row.partnerWins ? DS.Theme.accent : .white)
                    Text(partnerName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }
}
