//
//  ExerciseDefinitionTests.swift
//  WRKTTests
//
//  Tests for Exercise models and extensions
//

import XCTest
@testable import WRKT

final class ExerciseDefinitionTests: WRKTTestCase {

    // MARK: - String Extensions Tests

    func testStringTrimmed() {
        XCTAssertEqual("  hello  ".trimmed, "hello")
        XCTAssertEqual("hello".trimmed, "hello")
        XCTAssertEqual("  ".trimmed, "")
        XCTAssertEqual("".trimmed, "")
    }

    func testStringTrimmedOrNil() {
        XCTAssertEqual("  hello  ".trimmedOrNil, "hello")
        XCTAssertEqual("hello".trimmedOrNil, "hello")
        XCTAssertNil("  ".trimmedOrNil)
        XCTAssertNil("".trimmedOrNil)
        XCTAssertNil("nan".trimmedOrNil)
        XCTAssertNil("NaN".trimmedOrNil)
        XCTAssertNil("null".trimmedOrNil)
        XCTAssertNil("NULL".trimmedOrNil)
        XCTAssertNil("none".trimmedOrNil)
        XCTAssertNil("NONE".trimmedOrNil)
    }

    func testOptionalStringTrimmedOrNil() {
        let string1: String? = "  hello  "
        XCTAssertEqual(string1.trimmedOrNil, "hello")

        let string2: String? = nil
        XCTAssertNil(string2.trimmedOrNil)

        let string3: String? = "nan"
        XCTAssertNil(string3.trimmedOrNil)
    }

    // MARK: - DifficultyLevel Tests

    func testDifficultyLevelInit() {
        XCTAssertEqual(DifficultyLevel("novice"), .novice)
        XCTAssertEqual(DifficultyLevel("Novice"), .novice)
        XCTAssertEqual(DifficultyLevel("NOVICE"), .novice)
        XCTAssertEqual(DifficultyLevel("beginner"), .beginner)
        XCTAssertEqual(DifficultyLevel("intermediate"), .intermediate)
        XCTAssertEqual(DifficultyLevel("advanced"), .advanced)
    }

    func testDifficultyLevelInitWithInvalidValue() {
        XCTAssertNil(DifficultyLevel("expert"))
        XCTAssertNil(DifficultyLevel(""))
        XCTAssertNil(DifficultyLevel(nil))
    }

    func testDifficultyLevelLabels() {
        XCTAssertEqual(DifficultyLevel.novice.label, "Novice")
        XCTAssertEqual(DifficultyLevel.beginner.label, "Beginner")
        XCTAssertEqual(DifficultyLevel.intermediate.label, "Intermediate")
        XCTAssertEqual(DifficultyLevel.advanced.label, "Advanced")
    }

    func testDifficultyLevelCodable() {
        assertCodable(DifficultyLevel.novice)
        assertCodable(DifficultyLevel.beginner)
        assertCodable(DifficultyLevel.intermediate)
        assertCodable(DifficultyLevel.advanced)
    }

    // MARK: - Exercise Tests

    func testExerciseCreation() {
        let exercise = Exercise(
            id: "bench-press",
            name: "Bench Press",
            force: "push",
            level: "intermediate",
            mechanic: "compound",
            equipment: "barbell",
            secondaryEquipment: nil,
            grip: "overhand",
            primaryMuscles: ["chest"],
            secondaryMuscles: ["triceps", "shoulders"],
            tertiaryMuscles: [],
            instructions: ["Step 1", "Step 2"],
            images: ["image1.jpg"],
            category: "strength",
            subregionTags: ["upper_chest"]
        )

        XCTAssertEqual(exercise.id, "bench-press")
        XCTAssertEqual(exercise.name, "Bench Press")
        XCTAssertEqual(exercise.force, "push")
        XCTAssertEqual(exercise.level, "intermediate")
        XCTAssertEqual(exercise.mechanic, "compound")
        XCTAssertEqual(exercise.equipment, "barbell")
        XCTAssertNil(exercise.secondaryEquipment)
        XCTAssertEqual(exercise.grip, "overhand")
        XCTAssertEqual(exercise.primaryMuscles, ["chest"])
        XCTAssertEqual(exercise.secondaryMuscles, ["triceps", "shoulders"])
        XCTAssertEqual(exercise.tertiaryMuscles, [])
        XCTAssertEqual(exercise.instructions.count, 2)
        XCTAssertEqual(exercise.images, ["image1.jpg"])
        XCTAssertEqual(exercise.category, "strength")
        XCTAssertEqual(exercise.subregionTags, ["upper_chest"])
    }

    func testExerciseCodable() {
        let exercise = TestFixtures.benchPress
        assertCodable(exercise)
    }

    func testExerciseWithMinimalData() {
        let exercise = Exercise(
            id: "minimal-exercise",
            name: "Minimal Exercise",
            force: nil,
            level: nil,
            mechanic: nil,
            equipment: nil,
            secondaryEquipment: nil,
            grip: nil,
            primaryMuscles: [],
            secondaryMuscles: [],
            tertiaryMuscles: [],
            instructions: [],
            images: nil,
            category: "other",
            subregionTags: []
        )

        XCTAssertEqual(exercise.id, "minimal-exercise")
        XCTAssertEqual(exercise.name, "Minimal Exercise")
        XCTAssertNil(exercise.force)
        XCTAssertNil(exercise.level)
        XCTAssertNil(exercise.mechanic)
        XCTAssertNil(exercise.equipment)
        XCTAssertEqual(exercise.primaryMuscles, [])
        XCTAssertEqual(exercise.instructions, [])
        XCTAssertNil(exercise.images)
    }

    // MARK: - ExcelExerciseDTO Tests

    func testExcelExerciseDTONameAlias() {
        let dto = ExcelExerciseDTO(
            id: "test-id",
            slug: "test-slug",
            exercise: "Test Exercise",
            difficulty: "intermediate",
            targetMuscleGroup: "chest",
            primeMover: "pectoralis",
            secondaryMuscle: "triceps",
            tertiaryMuscle: nil,
            primaryEquipment: "barbell",
            primaryItemsCount: 1,
            secondaryEquipment: nil,
            secondaryItemsCount: nil,
            posture: "lying",
            armMode: "bilateral",
            armsPattern: "push",
            grip: "overhand",
            loadPosition: "front",
            legsPattern: nil,
            footElevation: nil,
            combination: nil,
            movementPattern1: "horizontal_push",
            movementPattern2: nil,
            movementPattern3: nil,
            planeOfMotion1: "sagittal",
            planeOfMotion2: nil,
            planeOfMotion3: nil,
            bodyRegion: "upper_body",
            forceType: "push",
            mechanics: "compound",
            laterality: "bilateral",
            primaryClassification: "strength"
        )

        XCTAssertEqual(dto.name, "Test Exercise")
        XCTAssertEqual(dto.name, dto.exercise)
    }

    func testExcelExerciseDTOCodable() throws {
        let json = """
        {
            "id": "test-id",
            "slug": "test-slug",
            "exercise": "Test Exercise",
            "difficulty": "intermediate",
            "targetMuscleGroup": "chest",
            "primeMover": "pectoralis",
            "secondaryMuscle": "triceps",
            "tertiaryMuscle": null,
            "primaryEquipment": "barbell",
            "primaryItemsCount": 1,
            "secondaryEquipment": null,
            "secondaryItemsCount": null,
            "posture": "lying",
            "armMode": "bilateral",
            "armsPattern": "push",
            "grip": "overhand",
            "loadPosition": "front",
            "legsPattern": null,
            "footElevation": null,
            "combination": null,
            "movementPattern1": "horizontal_push",
            "movementPattern2": null,
            "movementPattern3": null,
            "planeOfMotion1": "sagittal",
            "planeOfMotion2": null,
            "planeOfMotion3": null,
            "bodyRegion": "upper_body",
            "forceType": "push",
            "mechanics": "compound",
            "laterality": "bilateral",
            "primaryClassification": "strength"
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(ExcelExerciseDTO.self, from: data)

        XCTAssertEqual(dto.id, "test-id")
        XCTAssertEqual(dto.slug, "test-slug")
        XCTAssertEqual(dto.exercise, "Test Exercise")
        XCTAssertEqual(dto.difficulty, "intermediate")
        XCTAssertEqual(dto.primaryEquipment, "barbell")
        XCTAssertNil(dto.tertiaryMuscle)
    }
}
