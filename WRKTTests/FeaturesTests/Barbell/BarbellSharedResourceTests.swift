import Foundation
import RealityKit
import Testing
@testable import WRKT

/// Process-wide resources the barbell scenes share instead of loading or generating per build.
@MainActor
@Suite struct BarbellSharedResourceTests {
    /// Every caller gets the same result from one lookup. Today the lookup finds nothing
    /// (IndoorHDRI.exr is not in a .skybox folder), so the shared result is nil for everyone,
    /// exactly as each caller's own lookup was before.
    @Test func indoorEnvironmentIsLookedUpOnceAndShared() async {
        async let first = sharedIndoorEnvironmentResource()
        async let second = sharedIndoorEnvironmentResource()
        let a = await first, b = await second
        let c = await sharedIndoorEnvironmentResource()
        #expect(a === b)
        #expect(a === c)
        let direct = try? await EnvironmentResource(named: "IndoorHDRI")
        #expect((a == nil) == (direct == nil), "the shared lookup matches a direct one")
    }

    @Test func barKnurlingTextureIsGeneratedOnceAndShared() throws {
        let first = try #require(sharedBarKnurlingRoughnessTexture())
        #expect(sharedBarKnurlingRoughnessTexture() === first)
        #expect(makeBarMaterial(skinID: 0).roughness.texture?.resource === first)
        #expect(makeBarMaterial(skinID: 1).roughness.texture?.resource === first)
    }
}
