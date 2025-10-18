// WeeklyGoalCard.swift
import SwiftUI

struct WeeklyGoalCard: View {
    let progress: WeeklyProgress
    let onTap: () -> Void

    private var paceChip: (label: String, color: Color) {
        switch progress.paceStatus {
        case .ahead:   return ("Ahead", .green)
        case .onTrack: return ("On track", .green)
        case .behind:  return ("Behind", .orange)
        }
    }

    private var leftLine: String {
        var parts: [String] = []
        if progress.minutesLeft > 0 {
            parts.append("\(progress.minutesLeft) min left")
        }
        if progress.strengthDaysLeft > 0 {
            parts.append("\(progress.strengthDaysLeft) strength day\(progress.strengthDaysLeft == 1 ? "" : "s") left")
        }
        return parts.isEmpty ? "Weekly targets complete" : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Left: MVPA ring
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress.mvpaPct)
                        .stroke(
                            AngularGradient(colors: [Color(hex:"#F4E409"),
                                                     Color(hex:"#FFE869"),
                                                     Color(hex:"#F4E409")],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(Int(progress.mvpaPct * 100))%")
                            .font(.headline.monospacedDigit())
                        Text("MVPA").font(.caption2).opacity(0.7)
                    }
                }
                .frame(width: 72, height: 72)

                // Right: text + bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("This week").font(.headline)
                        PaceChip(text: paceChip.label, color: paceChip.color)
                    }

                    // “112/150 min • 2/3 strength”
                    Text("\(progress.mvpaDone)/\(progress.mvpaTarget) min  •  \(progress.strengthDaysDone)/\(progress.strengthTarget) strength")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    // bar for MVPA minutes
                    GeometryReader { geo in
                        let w = geo.size.width
                        let p = CGFloat(progress.mvpaPct)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(Color(hex:"#F4E409")).frame(width: max(8, w * p))
                        }
                    }
                    .frame(height: 8)

                    // Left to go (or done)
                    Text(leftLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                Spacer()

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex:"#F4E409"))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex:"#232323"), Color(hex:"#353535")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

private struct PaceChip: View {
    let text: String; let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
            .foregroundStyle(color)
    }
}

private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self = Color(.sRGB,
                     red:   Double((v >> 16) & 0xFF)/255.0,
                     green: Double((v >>  8) & 0xFF)/255.0,
                     blue:  Double( v        & 0xFF)/255.0,
                     opacity: 1.0)
    }
}
