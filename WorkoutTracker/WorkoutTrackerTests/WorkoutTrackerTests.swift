//
//  WorkoutTrackerTests.swift
//  WorkoutTrackerTests
//

import XCTest
@testable import WorkoutTracker

final class WorkoutTrackerTests: XCTestCase {

    private func workout(minutes: Int, daysAgo: Int = 0, muscles: [MuscleGroup: HeatLevel], now: Date = Date()) -> Workout {
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

    func testHeatRoundTripsThroughMuscleLevels() {
        var w = workout(minutes: 30, muscles: [.chest: .heavy, .abs: .light])
        XCTAssertEqual(w.heat[.chest], .heavy)
        XCTAssertEqual(w.heat[.abs], .light)
        w.heat = [.quads: .none, .calves: .moderate]
        XCTAssertEqual(w.heat, [.calves: .moderate])
    }

    func testSingleWorkoutKeepsChosenLevel() {
        let now = Date()
        let w = workout(minutes: 45, muscles: [.chest: .heavy, .abs: .moderate, .calves: .light], now: now)
        let heat = HeatCalculator.weeklyHeat(workouts: [w], now: now)
        XCTAssertEqual(heat[.chest], .heavy)
        XCTAssertEqual(heat[.abs], .moderate)
        XCTAssertEqual(heat[.calves], .light)
        XCTAssertNil(heat[.quads])
    }

    func testRepeatedSessionsRaiseHeat() {
        let now = Date()
        let a = workout(minutes: 45, muscles: [.biceps: .light], now: now)
        let b = workout(minutes: 45, daysAgo: 2, muscles: [.biceps: .light], now: now)
        XCTAssertEqual(HeatCalculator.weeklyHeat(workouts: [a, b], now: now)[.biceps], .moderate)
    }

    func testOldWorkoutsAreIgnored() {
        let now = Date()
        let old = workout(minutes: 60, daysAgo: 10, muscles: [.lats: .heavy], now: now)
        XCTAssertTrue(HeatCalculator.weeklyHeat(workouts: [old], now: now).isEmpty)
    }

    func testHeatLevelCycle() {
        XCTAssertEqual(HeatLevel.none.next, .light)
        XCTAssertEqual(HeatLevel.light.next, .moderate)
        XCTAssertEqual(HeatLevel.moderate.next, .heavy)
        XCTAssertEqual(HeatLevel.heavy.next, .none)
    }

    @MainActor
    func testStorePersistsWorkouts() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkoutStore(fileURL: url)
        store.add(workout(minutes: 30, muscles: [.glutes: .heavy]))
        XCTAssertEqual(store.workouts.count, 1)

        let reloaded = WorkoutStore(fileURL: url)
        XCTAssertEqual(reloaded.workouts.count, 1)
        XCTAssertEqual(reloaded.workouts.first?.heat[.glutes], .heavy)

        reloaded.removeAll()
        XCTAssertTrue(WorkoutStore(fileURL: url).workouts.isEmpty)
    }

    // MARK: Strength, pinning, directory

    func testStrengthHeatFromSets() {
        let bench = LoggedExercise(exerciseID: "bench", name: "Bench Press (Barbell)",
                                   primary: [.chest], secondary: [.shoulders, .triceps],
                                   sets: Array(repeating: LoggedSet(weightKg: 60, reps: 8), count: 4))
        let heat = HeatCalculator.strengthHeat(exercises: [bench])
        XCTAssertEqual(heat[.chest], .moderate)    // 4 primary sets
        XCTAssertEqual(heat[.shoulders], .light)   // 2 points
        XCTAssertNil(heat[.quads])

        let more = LoggedExercise(exerciseID: "fly", name: "Chest Fly", primary: [.chest], secondary: [],
                                  sets: Array(repeating: LoggedSet(weightKg: 10, reps: 12), count: 4))
        XCTAssertEqual(HeatCalculator.strengthHeat(exercises: [bench, more])[.chest], .heavy)
    }

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

    func testBodySpecIsConsistent() {
        let tubes = Set(BodySpec.tubes.map(\.name))
        XCTAssertTrue(BodySpec.patches.allSatisfy { tubes.contains($0.host) })
        for tube in BodySpec.tubes {
            let ys = tube.keys.map(\.y)
            XCTAssertEqual(ys, ys.sorted(), "\(tube.name) keys must ascend in y")
        }
        XCTAssertEqual(Set(BodySpec.patches.map(\.muscle)), Set(MuscleGroup.allCases))
    }

    func testDecodesWorkoutsSavedByOlderVersions() throws {
        let json = #"[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Run","category":"Cardio","duration":30,"notes":"","date":"2026-05-01T10:00:00Z","muscleLevels":{"quads":2}}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workouts = try decoder.decode([Workout].self, from: Data(json.utf8))
        XCTAssertEqual(workouts.first?.heat[.quads], .moderate)
        XCTAssertEqual(workouts.first?.isPinned, false)
        XCTAssertEqual(workouts.first?.exercises.count, 0)
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
        var w = workout(minutes: 40, muscles: [.quads: .heavy])
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
}
