import SwiftUI

/// Banner shown when app is offline
struct OfflineBanner: View {
    let queueCount: Int
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if queueCount > 0 {
                    Text("\(queueCount) action\(queueCount == 1 ? "" : "s") queued")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("Showing cached content")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Spacer()

            if queueCount > 0 {
                Button(action: onSync) {
                    Text("Sync")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(.orange)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

