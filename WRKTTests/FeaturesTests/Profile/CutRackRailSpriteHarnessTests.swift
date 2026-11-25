import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Renders the rack rail's plate sprites for every earnable tier (and a few lifted faces) and
/// writes them as PNGs plus one contact sheet, to judge the rail's plates outside the screen.
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
        let tiers = PlateTier.all.map(\.id).filter { $0 != 7 }
        let started = Date()
        let edges = await service.renderEdgesForTesting(tiers)
        print("rail sprites: \(edges.count) of \(tiers.count) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        for (id, image) in edges { try image.pngData()?.write(to: root.appendingPathComponent("edge-\(id).png")) }

        var faces: [UIImage] = []
        for (tier, kg, engraving) in [(14, 20.0, ""), (8, 25.0, "75 Workouts"), (4, 20.0, "Personal Record"), (0, 5.0, "Squat")] {
            let request = LathePlateRequest(tierID: tier, weightKg: kg, engravingText: engraving, projection: BarbellPlateRenderProjection())
            if let face = await service.face(request) {
                faces.append(face)
                try face.pngData()?.write(to: root.appendingPathComponent("face-\(tier).png"))
            }
        }

        // A contact sheet: every tier standing on a strip, as the rail draws them.
        let sheet = ImageRenderer(content: Sheet(edges: tiers.compactMap { id in edges[id].map { (id, $0) } }, faces: faces))
        sheet.scale = 3
        if let image = sheet.uiImage { try image.pngData()?.write(to: root.appendingPathComponent("sheet.png")) }
    }

    private struct Sheet: View {
        let edges: [(Int, UIImage)]
        let faces: [UIImage]

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(stride(from: 0, to: edges.count, by: 10)), id: \.self) { start in
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(edges[start..<min(start + 10, edges.count)], id: \.0) { id, image in
                            VStack(spacing: 2) {
                                ZStack(alignment: .bottomLeading) {
                                    ForEach(0..<3, id: \.self) { index in
                                        Image(uiImage: image).resizable()
                                            .frame(width: CutRackRail<EmptyView>.plateWidth, height: CutRackRail<EmptyView>.plateHeight)
                                            .offset(x: CGFloat(index) * CutRackRail<EmptyView>.step)
                                    }
                                }
                                .frame(width: CutRackRail<EmptyView>.plateWidth + 2 * CutRackRail<EmptyView>.step, alignment: .leading)
                                Text("\(id)").font(.caption2).foregroundStyle(.white)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                        Image(uiImage: face).resizable().frame(width: 132, height: 132)
                    }
                }
            }
            .padding(16)
            .background(Color(white: 0.11))
        }
    }
}
