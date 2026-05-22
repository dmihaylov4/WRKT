import SwiftUI

/// Shows the earned plate spinning on a Y-axis for 4 seconds then settling.
struct SpinningPlateView: View {
    let plate: EarnedPlateInfo

    @State private var degrees: Double = 0
    @State private var settled = false

    var body: some View {
        PlateFaceView(
            tierID: plate.tierID,
            progressionTier: .iron,
            liftTypeID: nil,
            weightKg: plate.weightKg
        )
        .frame(width: 220, height: 220)
        .rotation3DEffect(.degrees(degrees), axis: (x: 0, y: 1, z: 0))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .onAppear {
            withAnimation(.linear(duration: 4)) {
                degrees = 720
            }
        }
    }
}
