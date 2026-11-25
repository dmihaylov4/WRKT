import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Renders the rack rail's stand pictures for every earnable tier plus engraved and lifted faces,
/// and writes them as PNGs and one contact sheet, to judge the plates outside the screen. Also
/// checks that the pictures never enter the room's face cache.
/// TEST_RUNNER_VOLIA_RAIL_SPRITES=1 enables it; TEST_RUNNER_VOLIA_CAPTURE_DIR=<directory>.
@MainActor
@Suite(.serialized)
struct CutRackRailSpriteHarnessTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RAIL_SPRITES"] == "1"))
    func renderSprites() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-rail")
            .appendingPathComponent("sprites", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = RackRailSpriteService.shared
        service.removeAllForTesting()
        let facesBefore = LatheFaceCache.count
        let weights: [Double] = [20, 25, 20, 15, 10, 5]
        var requests = PlateTier.all.map(\.id).filter { $0 != 7 }.enumerated().map { index, tier in
            LathePlateRequest(tierID: tier, weightKg: weights[index % weights.count], engravingText: "",
                              projection: BarbellPlateRenderProjection())
        }
        for (tier, kg, engraving) in [(8, 25.0, "75 Workouts"), (4, 20.0, "Personal Record"), (0, 5.0, "Squat"), (26, 35.0, "Volume Champion")] {
            requests.append(LathePlateRequest(tierID: tier, weightKg: kg, engravingText: engraving, projection: BarbellPlateRenderProjection()))
        }
        let started = Date()
        let images = await service.renderStandsForTesting(requests)
        print("rail stands: \(images.compactMap { $0 }.count) of \(requests.count) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        #expect(LatheFaceCache.count == facesBefore, "rail pictures must not enter the room's face cache")
        for (index, image) in images.enumerated() {
            try image?.pngData()?.write(to: root.appendingPathComponent("stand-\(index).png"))
        }
        let lifted = await service.lifted(requests[requests.count - 4])
        #expect(LatheFaceCache.count == facesBefore)

        let sheet = ImageRenderer(content: Sheet(images: images.compactMap { $0 }, lifted: lifted))
        sheet.scale = 3
        if let image = sheet.uiImage { try image.pngData()?.write(to: root.appendingPathComponent("sheet.png")) }
    }

    private struct Sheet: View {
        let images: [UIImage]
        let lifted: UIImage?

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(stride(from: 0, to: images.count, by: 6)), id: \.self) { start in
                    HStack(alignment: .bottom, spacing: -6) {
                        ForEach(start..<min(start + 6, images.count), id: \.self) { index in
                            Image(uiImage: images[index]).resizable().frame(width: 100, height: 100)
                        }
                    }
                }
                if let lifted { Image(uiImage: lifted).resizable().frame(width: 160, height: 160) }
            }
            .padding(16)
            .background(Color(white: 0.09))
        }
    }
}
