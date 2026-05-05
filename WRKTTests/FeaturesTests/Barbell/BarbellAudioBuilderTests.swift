// WRKTTests/FeaturesTests/Barbell/BarbellAudioBuilderTests.swift
import Testing
import RealityKit
@testable import WRKT

struct BarbellAudioBuilderTests {

    @Test func audioResourceLoadsForEveryTier() {
        for tierID in PlateTier.all.map(\.id) {
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

    @Test func physicsTuningDefinedForAllCategories() {
        #expect(PlateAudioCategory.iron.physicsTuning == PlatePhysicsTuning(friction: 0.70, restitution: 0.30))
        #expect(PlateAudioCategory.rubber.physicsTuning == PlatePhysicsTuning(friction: 0.92, restitution: 0.08))
        #expect(PlateAudioCategory.brass.physicsTuning == PlatePhysicsTuning(friction: 0.65, restitution: 0.38))
        #expect(PlateAudioCategory.starter.physicsTuning == PlatePhysicsTuning(friction: 0.85, restitution: 0.12))
    }
}
