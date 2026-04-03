import Testing
import RealityKit
@testable import WRKT

struct BarbellEntityBuilderTests {

    @Test func makePlateEntityHasRequiredComponents() {
        for tierID in 0...7 {
            let entity = makePlateEntity(tierID: tierID)
            #expect(entity.components[InputTargetComponent.self] != nil,
                    "tier \(tierID) missing InputTargetComponent")
            #expect(entity.components[CollisionComponent.self] != nil,
                    "tier \(tierID) missing CollisionComponent")
            #expect(entity.components[PlateRoleComponent.self] != nil,
                    "tier \(tierID) missing PlateRoleComponent")
            #expect(entity.components[PhysicsBodyComponent.self] != nil,
                    "tier \(tierID) missing PhysicsBodyComponent")
            #expect(entity.components[TierIDComponent.self] != nil,
                    "tier \(tierID) missing TierIDComponent")
            #expect(entity.components[PlateAudioCategoryComponent.self] != nil,
                    "tier \(tierID) missing PlateAudioCategoryComponent")
            #expect(entity.components[PhysicsMotionComponent.self] != nil,
                    "tier \(tierID) missing PhysicsMotionComponent")
        }
    }

    @Test func makePlateEntityDefaultRoleIsFloor() {
        let entity = makePlateEntity(tierID: 0)
        #expect(entity.components[PlateRoleComponent.self]?.role == .floor)
    }

    @Test func makePlateEntityBarRoleRoundtrips() {
        let entity = makePlateEntity(tierID: 2, role: .bar)
        #expect(entity.components[PlateRoleComponent.self]?.role == .bar)
    }

    @Test func makePlateEntityPhysicsIsKinematicByDefault() {
        let entity = makePlateEntity(tierID: 0)
        #expect(entity.components[PhysicsBodyComponent.self]?.mode == .kinematic)
    }

    @Test func makePlateEntityAcceptsExternalMaterial() {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .red)
        let entity = makePlateEntity(tierID: 0, material: mat)
        #expect(entity.components[PlateRoleComponent.self] != nil)
    }

    @Test func makeBarEntityIsNonNil() {
        for skinID in 0..<BarSkin.all.count {
            let bar = makeBarEntity(skinID: skinID)
            #expect(bar.model != nil, "skinID \(skinID) missing mesh")
        }
    }

    @Test func makeCollarEntityIsNonNil() {
        let collar = makeCollarEntity()
        #expect(collar.model != nil)
    }

    @Test func makeRackStandEntityIsNonNil() {
        let stand = makeRackStandEntity()
        #expect(!stand.children.isEmpty, "stand has no children")
    }
}
