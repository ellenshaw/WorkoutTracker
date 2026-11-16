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
}
