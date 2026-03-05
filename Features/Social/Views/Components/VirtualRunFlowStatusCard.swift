//
//  VirtualRunFlowStatusCard.swift
//  WRKT
//
//  Persistent floating card that surfaces every phase of the Virtual Run
//  invite → accept → Watch-sync → active run lifecycle for both inviter and invitee.
//  Reads VirtualRunInviteCoordinator; drives zero business logic.
//

import SwiftUI

struct VirtualRunFlowStatusCard: View {
    @State private var coordinator = VirtualRunInviteCoordinator.shared

    private var phase: VirtualRunFlowPhase { coordinator.flowPhase }
    private var retryAction: (@MainActor @Sendable () async -> Void)? { coordinator.retryAction }

    var body: some View {
        ZStack {
            if phase != .idle {
                cardBody
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: phase)
    }

    // MARK: - Card Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if case .activeRun = phase {
                activeRunStats
            } else {
                statusRow
                actionRow
            }
        }
        .padding(16)
        .background {
            ChamferedRectangle(.xl)
                .fill(DS.Semantic.card)
                .overlay(
                    ChamferedRectangle(.xl)
                        .stroke(DS.Semantic.border, lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.marone)
            Text("Virtual Run")
                .font(.subheadline.weight(.semibold))
            if case .activeRun = phase {
                PulsingDot(color: DS.Semantic.success, size: 7)
            }
            Spacer()
            // No dismiss button during an active run — card lives for the run duration
            if case .activeRun = phase {
                EmptyView()
            } else {
                Button {
                    coordinator.dismissFlowCard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Pre-run Status Row

    private var statusRow: some View {
        HStack(spacing: 12) {
            statusIndicator
                .frame(width: 24, height: 24)
            Text(messageText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: messageText)
            Spacer()
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch phase {
        case .sendingInvite, .connecting, .syncingWithWatch:
            ProgressView()
                .controlSize(.small)
        case .waitingForPartner:
            PulsingDot()
        case .watchReady:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(DS.Palette.marone)
        case .failed(let err):
            Image(systemName: err == .watchUnreachable ? "applewatch.radiowaves.left.and.right" : "exclamationmark.triangle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.orange)
        case .idle, .activeRun:
            EmptyView()
        }
    }

    private var messageText: String {
        switch phase {
        case .idle:                                 return ""
        case .sendingInvite:                        return "Sending invite…"
        case .waitingForPartner(let name):          return "Waiting for \(name) to accept"
        case .connecting:                           return "Connecting to run…"
        case .syncingWithWatch:                     return "Starting run on your Watch…"
        case .watchReady:                           return "Get ready!"
        case .activeRun:                            return ""
        case .failed(.sendFailed):                  return "Couldn't send the invite"
        case .failed(.watchUnreachable):            return "Couldn't reach your Watch"
        case .failed(.acceptFailed):                return "Couldn't join the run"
        case .failed(.generic(let msg)):            return msg
        }
    }

    // MARK: - Action Row

    @ViewBuilder
    private var actionRow: some View {
        switch phase {
        case .waitingForPartner:
            Button {
                Task { await coordinator.cancelSentInvite() }
            } label: {
                Text("Cancel Invite")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(DS.Semantic.surface50)
                    .clipShape(ChamferedRectangle(.large))
            }
            .buttonStyle(.plain)

        case .failed:
            HStack(spacing: 10) {
                if let retry = retryAction {
                    Button {
                        Task { await retry() }
                    } label: {
                        Text("Try Again")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(DS.Palette.marone)
                            .foregroundStyle(.white)
                            .clipShape(ChamferedRectangle(.large))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    coordinator.dismissFlowCard()
                } label: {
                    Text("Dismiss")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(DS.Semantic.surface50)
                        .clipShape(ChamferedRectangle(.large))
                }
                .buttonStyle(.plain)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Active Run Stats

    private var activeRunStats: some View {
        let mySnap = coordinator.myRunSnapshot
        let partnerSnap = coordinator.partnerRunSnapshot
        let partnerName: String = {
            if case .activeRun(let name) = phase { return name }
            return "Partner"
        }()

        return VStack(spacing: 0) {
            // Column headers
            HStack {
                Text("Me")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(partnerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            Divider()
                .padding(.bottom, 8)

            // Distance
            statRow(
                icon: "ruler",
                myValue: mySnap.map { formatDistance($0.distanceM) } ?? "—",
                partnerValue: partnerSnap.map { formatDistance($0.distanceM) } ?? "—"
            )
            .padding(.bottom, 6)

            // Pace
            statRow(
                icon: "speedometer",
                myValue: mySnap?.currentPaceSecPerKm.map { formatPace($0) } ?? "—",
                partnerValue: partnerSnap?.currentPaceSecPerKm.map { formatPace($0) } ?? "—"
            )
            .padding(.bottom, 6)

            // Heart Rate
            statRow(
                icon: "heart.fill",
                myValue: mySnap?.heartRate.map { "\($0) bpm" } ?? "—",
                partnerValue: partnerSnap?.heartRate.map { "\($0) bpm" } ?? "—"
            )
        }
    }

    private func statRow(icon: String, myValue: String, partnerValue: String) -> some View {
        HStack {
            Text(myValue)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(partnerValue)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    // MARK: - Formatting

    private func formatDistance(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1000)
    }

    private func formatPace(_ secPerKm: Int) -> String {
        let mins = secPerKm / 60
        let secs = secPerKm % 60
        return String(format: "%d:%02d /km", mins, secs)
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    var color: Color = DS.Palette.marone
    var size: CGFloat = 10
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(pulsing ? 1.0 : 0.75)
            .opacity(pulsing ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
