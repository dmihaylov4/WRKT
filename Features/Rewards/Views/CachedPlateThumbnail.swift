import SwiftUI

/// Drop-in replacement for PlateFaceView that shows a cached RealityKit PNG
/// if available, falling back to PlateFaceView while the snapshot renders.
///
/// Usage - replace:
///   PlateFaceView(tierID: x, progressionTier: y, liftTypeID: z, weightKg: w)
/// with:
///   CachedPlateThumbnail(tierID: x, progressionTier: y, liftTypeID: z,
///                        weightKg: w, engravingText: e)
struct CachedPlateThumbnail: View {
    let tierID: Int
    let progressionTier: BarbellPlateProgressionTier
    let liftTypeID: String?
    let weightKg: Double
    var engravingText: String = ""
    var showEngravings: Bool = true

    @State private var cachedImage: UIImage? = nil

    var body: some View {
        Group {
            if let image = cachedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                PlateFaceView(
                    tierID: tierID,
                    progressionTier: progressionTier,
                    liftTypeID: liftTypeID,
                    weightKg: weightKg,
                    showEngravings: showEngravings
                )
            }
        }
        .task {
            if let image = PlateSnapshotService.shared.cachedImage(
                tierID: tierID, weightKg: weightKg, engravingText: engravingText
            ) {
                cachedImage = image
                return
            }
            await PlateSnapshotService.shared.renderIfNeeded(
                tierID: tierID, weightKg: weightKg, engravingText: engravingText
            )
            cachedImage = PlateSnapshotService.shared.cachedImage(
                tierID: tierID, weightKg: weightKg, engravingText: engravingText
            )
        }
    }
}
