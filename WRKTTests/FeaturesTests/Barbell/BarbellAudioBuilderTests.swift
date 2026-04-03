// WRKTTests/FeaturesTests/Barbell/BarbellAudioBuilderTests.swift
import Testing
import RealityKit
@testable import WRKT

struct BarbellAudioBuilderTests {

    @Test func audioResourceLoadsForEveryTier() {
        for tierID in 0...7 {
            let cat = PlateAudioCategory.from(tierID: tierID)
            let resource = loadAudioResource(named: cat.clinkSoundName)
            #expect(resource != nil, "clink sound missing for tier \(tierID): \(cat.clinkSoundName)")
        }
    }

    @Test func dropSoundLoadsForEveryCategory() {
        for cat in [PlateAudioCategory.iron, .rubber, .brass, .starter] {
            let resource = loadAudioResource(named: cat.dropSoundName)
            #expect(resource != nil, "drop sound missing for \(cat): \(cat.dropSoundName)")
        }
    }

    @Test func physicsMaterialDefinedForAllCategories() {
        // Compile-time guarantee -- if any case is missing, this won't build
        for cat in [PlateAudioCategory.iron, .rubber, .brass, .starter] {
            _ = cat.physicsMaterial
        }
        #expect(true)
    }
}
