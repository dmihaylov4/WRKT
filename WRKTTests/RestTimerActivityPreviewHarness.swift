#if REST_TIMER_ACTIVITY_PREVIEW_HARNESS
import SwiftUI

/// Standalone simulator host for the actual widget view. Build this file with the
/// widget's sources and WRKT_WIDGET_EXTENSION; it is inactive in the normal test target.
@main
struct RestTimerActivityPreviewHarness: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black
                VStack(spacing: 28) {
                    Text("Lock screen: 320 pt")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    card(width: 320)
                    Text("Lock screen: 375 pt")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    card(width: 375)
                }
            }
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
        }
    }

    private func card(width: CGFloat) -> some View {
        RestTimerLockScreenView(
            attributes: RestTimerAttributes(
                exerciseName: "Dumbbell Bulgarian Split Squat",
                originalDuration: 180,
                exerciseID: "fixture-exercise",
                startTime: Date(timeIntervalSince1970: 1_000),
                timerID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")
            ),
            state: RestTimerAttributes.ContentState(
                remainingSeconds: 75,
                endDate: Date(timeIntervalSince1970: 1_075),
                isPaused: true,
                progress: 0.42,
                wasAdjusted: false,
                lastUpdate: Date(timeIntervalSince1970: 1_000)
            )
        )
        .frame(width: width)
        .background(Color(white: 0.03), in: RoundedRectangle(cornerRadius: 24))
    }
}
#endif
