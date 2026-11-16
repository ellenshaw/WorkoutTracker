//
//  WorkoutTrackerTests.swift
//  WorkoutTrackerTests
//

import XCTest
@testable import WorkoutTracker

final class WorkoutTrackerTests: XCTestCase {

    private func workout(minutes: Int, daysAgo: Int = 0, muscles: [MuscleGroup: Double], now: Date = Date()) -> Workout {
        var w = Workout(
            name: "Test",
            category: .strength,
            duration: minutes,
            notes: "",
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        )
        w.heat = muscles
        return w
    }

    // MARK: Heat

    func testHeatRoundTripsThroughStoredPercentages() {
        var w = workout(minutes: 30, muscles: [.chest: 1.0, .abs: 0.35])
        XCTAssertEqual(w.heat[.chest] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(w.heat[.abs] ?? 0, 0.35, accuracy: 0.001)
        w.heat = [.quads: 0, .calves: 0.65]
        XCTAssertEqual(Set(w.heat.keys), [.calves])
    }

    func testSingleWorkoutLandsWhereExpected() {
        let now = Date()
        let w = workout(minutes: 45, muscles: [.chest: 1.0, .calves: 0.35], now: now)
        let heat = HeatCalculator.weeklyHeat(workouts: [w], now: now)
        XCTAssertEqual(heat[.chest] ?? 0, 1.0 / 1.2, accuracy: 0.001)
        XCTAssertEqual(heat[.calves] ?? 0, 0.35 / 1.2, accuracy: 0.001)
        XCTAssertNil(heat[.quads])
    }

    func testRepeatedSessionsRaiseHeatAndCapAtMax() {
        let now = Date()
        let a = workout(minutes: 45, muscles: [.biceps: 0.35], now: now)
        let b = workout(minutes: 45, daysAgo: 2, muscles: [.biceps: 0.35], now: now)
        let one = HeatCalculator.weeklyHeat(workouts: [a], now: now)[.biceps] ?? 0
        let two = HeatCalculator.weeklyHeat(workouts: [a, b], now: now)[.biceps] ?? 0
        XCTAssertGreaterThan(two, one)

        let many = (0..<6).map { workout(minutes: 60, daysAgo: $0, muscles: [.biceps: 1.0], now: now) }
        XCTAssertEqual(HeatCalculator.weeklyHeat(workouts: many, now: now)[.biceps], 1.0)
    }

    func testOldWorkoutsAreIgnored() {
        let now = Date()
        let old = workout(minutes: 60, daysAgo: 10, muscles: [.lats: 1.0], now: now)
        XCTAssertTrue(HeatCalculator.weeklyHeat(workouts: [old], now: now).isEmpty)
    }

    func testHeatLevelCycleAndIntensity() {
        XCTAssertEqual(HeatLevel.none.next, .light)
        XCTAssertEqual(HeatLevel.light.next, .moderate)
        XCTAssertEqual(HeatLevel.moderate.next, .heavy)
        XCTAssertEqual(HeatLevel.heavy.next, .none)
        for level in HeatLevel.allCases {
            XCTAssertEqual(HeatLevel(nearest: level.intensity), level)
        }
    }

    func testHeatScaleRunsFromBlueToRed() {
        let cold = HeatScale.rgb(0)
        let hot = HeatScale.rgb(1)
        XCTAssertGreaterThan(cold.z, cold.x)       // blue
        XCTAssertGreaterThan(hot.x, hot.z)         // red
        XCTAssertGreaterThan(HeatScale.rgb(0.4).y, HeatScale.rgb(0.4).x)   // green in the middle
        XCTAssertEqual(HeatScale.rgb(-3), cold)
        XCTAssertEqual(HeatScale.rgb(9), hot)
    }

    func testStrengthHeatFromSets() {
        let bench = LoggedExercise(exerciseID: "bench", name: "Bench Press (Barbell)",
                                   primary: [.chest], secondary: [.shoulders, .triceps],
                                   sets: Array(repeating: LoggedSet(weightKg: 60, reps: 8), count: 4))
        let heat = HeatCalculator.strengthHeat(exercises: [bench])
        XCTAssertEqual(heat[.chest] ?? 0, 0.4, accuracy: 0.001)       // 4 primary sets
        XCTAssertEqual(heat[.shoulders] ?? 0, 0.2, accuracy: 0.001)   // 2 points
        XCTAssertNil(heat[.quads])

        let fly = LoggedExercise(exerciseID: "fly", name: "Chest Fly", primary: [.chest], secondary: [],
                                 sets: Array(repeating: LoggedSet(weightKg: 10, reps: 12), count: 8))
        XCTAssertEqual(HeatCalculator.strengthHeat(exercises: [bench, fly])[.chest], 1.0)
    }

    // MARK: Units, library, store

    func testWeightUnitConversion() {
        XCTAssertEqual(WeightUnit.kg.format(kg: 62.5), "62.5")
        XCTAssertEqual(WeightUnit.lb.format(kg: WeightUnit.lb.toKg(135)), "135")
    }

    func testExerciseLibraryIsConsistent() {
        let ids = ExerciseLibrary.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "exercise ids must be unique")
        XCTAssertTrue(ExerciseLibrary.all.allSatisfy { !$0.primary.isEmpty })
        for muscle in MuscleGroup.allCases {
            XCTAssertTrue(ExerciseLibrary.all.contains { $0.primary.contains(muscle) }, "no exercise for \(muscle)")
        }
    }

    func testEveryCategoryExceptStrengthHasActivities() {
        for category in WorkoutCategory.allCases where category != .strength {
            XCTAssertFalse(category.activities.isEmpty)
        }
    }

    func testDecodesWorkoutsSavedByOlderVersions() throws {
        let json = #"[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Run","category":"Cardio","duration":30,"notes":"","date":"2026-05-01T10:00:00Z","muscleLevels":{"quads":2,"calves":3}}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workouts = try decoder.decode([Workout].self, from: Data(json.utf8))
        XCTAssertEqual(workouts.first?.heat[.quads] ?? 0, 0.65, accuracy: 0.001)
        XCTAssertEqual(workouts.first?.heat[.calves] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(workouts.first?.isPinned, false)
        XCTAssertEqual(workouts.first?.exercises.count, 0)
    }

    func testWorkoutEncodeDecodeRoundTrip() throws {
        var w = workout(minutes: 40, muscles: [.glutes: 0.8])
        w.isPinned = true
        let data = try JSONEncoder().encode([w])
        let decoded = try JSONDecoder().decode([Workout].self, from: data)
        XCTAssertEqual(decoded.first?.id, w.id)
        XCTAssertEqual(decoded.first?.isPinned, true)
        XCTAssertEqual(decoded.first?.heat[.glutes] ?? 0, 0.8, accuracy: 0.001)
    }

    @MainActor
    func testStorePersistsWorkouts() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkoutStore(fileURL: url)
        store.add(workout(minutes: 30, muscles: [.glutes: 1.0]))
        XCTAssertEqual(store.workouts.count, 1)

        let reloaded = WorkoutStore(fileURL: url)
        XCTAssertEqual(reloaded.workouts.count, 1)
        XCTAssertEqual(reloaded.workouts.first?.heat[.glutes], 1.0)

        reloaded.removeAll()
        XCTAssertTrue(WorkoutStore(fileURL: url).workouts.isEmpty)
    }

    @MainActor
    func testPinningAndLastSetsAndCustomExercises() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent()
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-exercises.json"))
        }

        let store = WorkoutStore(fileURL: url)
        let logged = LoggedExercise(exerciseID: "squat", name: "Squat (Barbell)", primary: [.quads], secondary: [],
                                    sets: [LoggedSet(weightKg: 100, reps: 5)])
        var w = workout(minutes: 40, muscles: [.quads: 1.0])
        w.exercises = [logged]
        store.add(w)

        XCTAssertTrue(store.pinnedWorkouts.isEmpty)
        store.togglePin(w.id)
        XCTAssertEqual(store.pinnedWorkouts.count, 1)
        XCTAssertEqual(store.lastSets(for: "squat").first?.reps, 5)

        let custom = store.addCustomExercise(name: "Landmine Press", primary: [.shoulders], secondary: [.chest])

        let reloaded = WorkoutStore(fileURL: url)
        XCTAssertEqual(reloaded.pinnedWorkouts.count, 1)
        XCTAssertTrue(reloaded.allExercises.contains { $0.id == custom.id })
    }

    // MARK: Body profile and 3D model

    func testBodyProfileFactors() {
        XCTAssertEqual(BodyProfile(gender: .male, age: 25, weightKg: 70, heightCm: 180).ageFactor, 0)
        XCTAssertEqual(BodyProfile(gender: .male, age: 90, weightKg: 70, heightCm: 180).ageFactor, 1)
        XCTAssertLessThan(BodyProfile(gender: .neutral, age: 30, weightKg: 52, heightCm: 175).weightFactor, 0)
        XCTAssertGreaterThan(BodyProfile(gender: .neutral, age: 30, weightKg: 110, heightCm: 175).weightFactor, 0)
        XCTAssertEqual(BodyProfile(gender: .neutral, age: 30, weightKg: 400, heightCm: 175).weightFactor, 1)
        XCTAssertEqual(BodyGender.neutral.maleShare, 0.5)
        // Out-of-range stored values are clamped.
        let clamped = BodyProfile(genderRaw: "bogus", age: 500, weightKg: -5, heightCm: 9999)
        XCTAssertEqual(clamped.gender, .neutral)
        XCTAssertEqual(clamped.age, BodyProfile.ageRange.upperBound)
    }

    func testBodyMeshLoadsAndIsWellFormed() throws {
        let base = try XCTUnwrap(BodyAsset.loadBase(), "missing body mesh resources")
        XCTAssertEqual(base.positions.count, 13380)
        XCTAssertEqual(base.targets.count, 10)
        XCTAssertEqual(base.weights.count, base.positions.count * BodyAsset.muscleOrder.count)

        for gender in BodyGender.allCases {
            let mesh = BodyAsset.morph(base, profile: BodyProfile(gender: gender))
            XCTAssertEqual(mesh.vertexCount, 13380)
            XCTAssertEqual(mesh.positions.map(\.y).max() ?? 0, BodyAsset.figureHeight, accuracy: 0.05)
            XCTAssertEqual(mesh.positions.map(\.y).min() ?? 1, 0, accuracy: 0.05)
            XCTAssertTrue(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })

            // Every muscle must exist on the body, or its heat would never show.
            for (column, muscle) in BodyAsset.muscleOrder.enumerated() {
                let covered = (0..<mesh.vertexCount).contains { mesh.weights[$0 * mesh.muscleCount + column] > 128 }
                XCTAssertTrue(covered, "\(muscle) has no vertices on the \(gender) body")
            }
        }
    }

    func testMuscleOrderCoversEveryMuscleOnce() {
        XCTAssertEqual(Set(BodyAsset.muscleOrder), Set(MuscleGroup.allCases))
        XCTAssertEqual(BodyAsset.muscleOrder.count, MuscleGroup.allCases.count)
    }

    func testProfileChangesTheBodyShape() throws {
        let base = try XCTUnwrap(BodyAsset.loadBase())

        // Width of the torso band, where weight shows most.
        func torsoWidth(_ profile: BodyProfile) -> Float {
            let mesh = BodyAsset.morph(base, profile: profile)
            let band = mesh.positions.filter { $0.y > 3.8 && $0.y < 4.2 }
            return (band.map(\.x).max() ?? 0) - (band.map(\.x).min() ?? 0)
        }
        let slim = torsoWidth(BodyProfile(gender: .neutral, age: 28, weightKg: 50, heightCm: 175))
        let average = torsoWidth(BodyProfile(gender: .neutral, age: 28, weightKg: 70, heightCm: 175))
        let heavy = torsoWidth(BodyProfile(gender: .neutral, age: 28, weightKg: 120, heightCm: 175))
        XCTAssertLessThan(slim, average)
        XCTAssertLessThan(average, heavy)

        // Male and female shapes differ.
        let maleMesh = BodyAsset.morph(base, profile: BodyProfile(gender: .male))
        let femaleMesh = BodyAsset.morph(base, profile: BodyProfile(gender: .female))
        XCTAssertNotEqual(maleMesh.positions, femaleMesh.positions)
    }

    func testLinesAnchorsAndColors() throws {
        let mesh = try XCTUnwrap(BodyAsset.load())

        let lines = BodyAsset.lines(for: mesh)
        XCTAssertGreaterThan(lines.positions.count, 1000)
        XCTAssertEqual(lines.positions.count % 2, 0)
        XCTAssertEqual(lines.positions.count, lines.muscle.count)
        XCTAssertEqual(lines.positions.count, lines.kind.count)
        XCTAssertTrue(lines.kind.contains(0), "no skin lines")
        XCTAssertTrue(lines.kind.contains(1), "no muscle fibres")
        XCTAssertTrue(lines.kind.contains(2), "no muscle outlines")
        // Every muscle gets an outline.
        for column in 0..<BodyAsset.muscleOrder.count {
            let outlined = zip(lines.muscle, lines.kind).contains { $0 == Int8(column) && $1 == 2 }
            XCTAssertTrue(outlined, "\(BodyAsset.muscleOrder[column]) has no outline")
        }

        // Every muscle can be labelled.
        let anchored = Set(BodyAsset.anchors(for: mesh).map(\.muscle))
        XCTAssertEqual(anchored, Set(MuscleGroup.allCases))

        let none = BodyAsset.fillColors(for: mesh, heat: [:])
        let hot = BodyAsset.fillColors(for: mesh, heat: [.chest: 1.0])
        XCTAssertEqual(none.count, mesh.vertexCount)
        XCTAssertNotEqual(none, hot)

        let coldLines = BodyAsset.lineColors(for: lines, heat: [:])
        let hotLines = BodyAsset.lineColors(for: lines, heat: [.chest: 1.0])
        XCTAssertEqual(coldLines.count, lines.positions.count)
        XCTAssertNotEqual(coldLines, hotLines)
    }

    func testMusclesStandOutFromTheBody() throws {
        let base = try XCTUnwrap(BodyAsset.loadBase())
        let mesh = BodyAsset.morph(base, profile: BodyProfile(gender: .male))
        // Relief pushes muscle vertices outward, so the chest sits further forward than the skin beside it.
        let chestColumn = try XCTUnwrap(BodyAsset.muscleOrder.firstIndex(of: .chest))
        let chestFront = (0..<mesh.vertexCount)
            .filter { mesh.weight(vertex: $0, column: chestColumn) > 0.8 && mesh.positions[$0].x > 0 }
            .map { mesh.positions[$0].z }
        XCTAssertFalse(chestFront.isEmpty)
        XCTAssertGreaterThan(chestFront.max() ?? 0, 0.3)
    }
}
