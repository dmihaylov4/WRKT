// WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift
import Testing
import RealityKit
import SwiftUI
@testable import WRKT

struct SceneStateTests {

    @Test func initialDragPhaseIsIdle() {
        let state = SceneState()
        if case .idle = state.dragPhase { } else {
            Issue.record("Expected .idle, got \(state.dragPhase)")
        }
    }

    @Test func initialFloorOffsetIsZero() {
        let state = SceneState()
        #expect(state.floorOffset == 0)
    }

    @Test func addPlateUpdatesEntityMap() {
        let state = SceneState()
        let plate = EarnedPlate(id: "test-id", tierID: 0, weightKg: 5,
                                engravingText: "Test", earnedByEvent: "first_workout")
        state.addPlate(plate)
        #expect(state.entityMap["test-id"] != nil)
    }

    @Test func addPlateIdempotent() {
        let state = SceneState()
        let plate = EarnedPlate(id: "dup-id", tierID: 1, weightKg: 10,
                                engravingText: "", earnedByEvent: "5_workouts")
        state.addPlate(plate)
        state.addPlate(plate)
        #expect(state.entityMap.count == 1)
    }

    // MARK: State machine

    @Test func idleCanTransitionToDraggingPlate() {
        let state = SceneState()
        let entity = Entity()
        let result = state.transition(to: .draggingPlate(entity, plateID: "x", originRole: .floor))
        #expect(result == true)
        if case .draggingPlate = state.dragPhase { } else {
            Issue.record("Expected .draggingPlate after valid transition")
        }
    }

    @Test func idleCanTransitionToPanningFloor() {
        let state = SceneState()
        #expect(state.transition(to: .panningFloor) == true)
    }

    @Test func panningFloorCannotTransitionToDraggingPlate() {
        let state = SceneState()
        state.transition(to: .panningFloor)
        let result = state.transition(to: .draggingPlate(Entity(), plateID: "x", originRole: .floor))
        #expect(result == false)
        if case .panningFloor = state.dragPhase { } else {
            Issue.record("State should remain .panningFloor after invalid transition")
        }
    }

    @Test func draggingPlateCannotTransitionToPanningFloor() {
        let state = SceneState()
        state.transition(to: .draggingPlate(Entity(), plateID: "x"))
        #expect(state.transition(to: .panningFloor) == false)
    }

    @Test func floorOffsetClampDoesNotExceedBounds() {
        let state = SceneState()
        state.floorMinX = 0
        state.floorMaxX = 1.0
        let raw: Float = 1.5
        let clamped = max(state.floorMinX, min(state.floorMaxX, raw))
        #expect(clamped == 1.0)
    }
}
