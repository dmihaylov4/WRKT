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

    init(tierID: Int, progressionTier: BarbellPlateProgressionTier, liftTypeID: String?, weightKg: Double,
         engravingText: String = "", showEngravings: Bool = true) {
        self.tierID = tierID
        self.progressionTier = progressionTier
        self.liftTypeID = liftTypeID
        self.weightKg = weightKg
        self.engravingText = engravingText
        self.showEngravings = showEngravings
        // A thumbnail already decoded this session shows in the first frame, with no fallback flash.
        _cachedImage = State(initialValue: PlateSnapshotService.shared.memoryImage(
            tierID: tierID, weightKg: weightKg, engravingText: engravingText))
    }

    var body: some View {
        Group {
            if let image = cachedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(Circle())
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
            if cachedImage != nil { return }
            // Read and decoded off the main thread.
            if let image = await PlateSnapshotService.shared.cachedImageAsync(
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
