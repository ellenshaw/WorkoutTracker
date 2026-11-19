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
        let heat = HeatCalculator.recoveryHeat(workouts: [w], now: now)
        // A fresh workout shows exactly the colors it had on its own screen.
        XCTAssertEqual(heat[.chest] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(heat[.calves] ?? 0, 0.35, accuracy: 0.001)
        XCTAssertNil(heat[.quads])
    }

    func testRepeatedSessionsRaiseHeatAndCapAtMax() {
        let now = Date()
        let a = workout(minutes: 45, muscles: [.biceps: 0.35], now: now)
        let b = workout(minutes: 45, daysAgo: 2, muscles: [.biceps: 0.35], now: now)
        let one = HeatCalculator.recoveryHeat(workouts: [a], now: now)[.biceps] ?? 0
        let two = HeatCalculator.recoveryHeat(workouts: [a, b], now: now)[.biceps] ?? 0
        XCTAssertGreaterThan(two, one)

        let many = (0..<6).map { workout(minutes: 60, daysAgo: $0, muscles: [.biceps: 1.0], now: now) }
        XCTAssertGreaterThanOrEqual(HeatCalculator.recoveryHeat(workouts: many, now: now)[.biceps] ?? 0, 0.99)
    }

    func testHeatFadesGraduallyInsteadOfDisappearing() {
        let now = Date()
        func heat(afterDays days: Int) -> Double {
            let w = workout(minutes: 45, daysAgo: days, muscles: [.lats: 1.0], now: now)
            return HeatCalculator.recoveryHeat(workouts: [w], now: now)[.lats] ?? 0
        }
        let fresh = heat(afterDays: 0)
        let three = heat(afterDays: 3)
        let week = heat(afterDays: 7)
        XCTAssertGreaterThan(fresh, three)
        XCTAssertGreaterThan(three, week)
        XCTAssertGreaterThan(week, 0, "a week-old workout should be faded, not gone")

        // A slower fade setting keeps more color.
        let w = workout(minutes: 45, daysAgo: 7, muscles: [.lats: 1.0], now: now)
        let slow = HeatCalculator.recoveryHeat(workouts: [w], now: now, halfLifeDays: 6)[.lats] ?? 0
        XCTAssertGreaterThan(slow, week)
    }

    func testVeryOldWorkoutsAreIgnored() {
        let now = Date()
        let old = workout(minutes: 60, daysAgo: 30, muscles: [.lats: 1.0], now: now)
        XCTAssertTrue(HeatCalculator.recoveryHeat(workouts: [old], now: now).isEmpty)
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
        // Any worked muscle is clearly different from the blue body, even a faint one.
        let faint = HeatScale.rgb(0.05)
        XCTAssertGreaterThan(faint.y, 0.7, "a barely-worked muscle should read as cyan, not blue")
        XCTAssertGreaterThan(faint.y - faint.x, 0.5)
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
        // Weight is never capped; only the model's shape stops changing at extremes.
        XCTAssertEqual(BodyProfile(genderRaw: "male", age: 30, weightKg: 350, heightCm: 180).weightKg, 350)
        XCTAssertEqual(BodyProfile(genderRaw: "male", age: 30, weightKg: 350, heightCm: 180).weightFactor, 1)
        // Out-of-range age and nonsense values are still sanitised.
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

    // MARK: Records, units, activities

    @MainActor
    func testPersonalRecords() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer {
            for suffix in ["", "-exercises", "-records"] {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.deletingPathExtension().lastPathComponent + suffix + ".json"))
            }
        }
        let store = WorkoutStore(fileURL: url)
        let squat = BigLift.squat

        func logged(_ kg: Double, reps: Int, daysAgo: Int) -> Workout {
            var w = workout(minutes: 45, daysAgo: daysAgo, muscles: [.quads: 0.8])
            w.exercises = [LoggedExercise(exerciseID: squat.exerciseID, name: squat.exerciseName,
                                          primary: [.quads], secondary: [],
                                          sets: [LoggedSet(weightKg: kg, reps: reps)])]
            return w
        }
        let first = logged(100, reps: 5, daysAgo: 10)
        let second = logged(110, reps: 5, daysAgo: 3)
        store.add(first)
        store.add(second)

        XCTAssertFalse(store.isPersonalRecord(first.exercises[0], in: first), "beaten by a later lift")
        XCTAssertTrue(store.isPersonalRecord(second.exercises[0], in: second))
        XCTAssertEqual(store.bestRecord(for: squat.exerciseID)?.weightKg, 110)

        // A heavier record entered by hand takes over and survives a reload.
        store.setManualRecord(PersonalRecord(exerciseID: squat.exerciseID, name: squat.exerciseName,
                                             weightKg: 160, reps: 1, date: Date()))
        XCTAssertEqual(store.bestRecord(for: squat.exerciseID)?.weightKg, 160)
        XCTAssertFalse(store.isPersonalRecord(second.exercises[0], in: second))
        XCTAssertEqual(WorkoutStore(fileURL: url).manualRecords.count, 1)

        store.clearManualRecord(exerciseID: squat.exerciseID)
        XCTAssertEqual(store.bestRecord(for: squat.exerciseID)?.weightKg, 110)
    }

    func testBigLiftsExistInTheDirectory() {
        for lift in BigLift.allCases {
            XCTAssertTrue(ExerciseLibrary.all.contains { $0.id == lift.exerciseID }, "\(lift.title) missing from directory")
        }
    }

    func testOneRepMaxEstimate() {
        XCTAssertEqual(PersonalRecord.estimateOneRepMax(weightKg: 100, reps: 1), 100)
        XCTAssertEqual(PersonalRecord.estimateOneRepMax(weightKg: 100, reps: 5), 100 * (1 + 5.0 / 30), accuracy: 0.001)
    }

    func testHeightUnitFormatting() {
        XCTAssertEqual(HeightUnit.cm.format(cm: 172), "172 cm")
        XCTAssertEqual(HeightUnit.feetInches.format(cm: 172.72), "5′8″")
        XCTAssertEqual(HeightUnit.feetInches.format(cm: 182.88), "6′0″")
    }

    func testSportsHaveUniqueNamesAndIncludeTheNewOnes() {
        let names = WorkoutCategory.sport.activities.map(\.name)
        XCTAssertEqual(names.count, Set(names).count)
        for expected in ["Table Tennis", "Pickleball", "Squash", "Golf", "Hockey", "Skateboarding"] {
            XCTAssertTrue(names.contains(expected), "missing \(expected)")
        }
        for category in WorkoutCategory.allCases {
            let all = category.activities.map(\.name)
            XCTAssertEqual(all.count, Set(all).count, "duplicate activity in \(category)")
            XCTAssertTrue(category.activities.allSatisfy { !$0.muscles.isEmpty })
        }
    }

    func testMaleAndFemaleBodiesAreClearlyDifferent() throws {
        let base = try XCTUnwrap(BodyAsset.loadBase())
        func shoulderWidth(_ gender: BodyGender) -> Float {
            let mesh = BodyAsset.morph(base, profile: BodyProfile(gender: gender))
            let band = mesh.positions.filter { $0.y > 5.3 && $0.y < 5.6 }
            return (band.map(\.x).max() ?? 0) - (band.map(\.x).min() ?? 0)
        }
        let male = shoulderWidth(.male)
        let neutral = shoulderWidth(.neutral)
        let female = shoulderWidth(.female)
        XCTAssertGreaterThan(male - female, 0.15, "male and female shoulders should differ visibly")
        XCTAssertGreaterThan(male, neutral)
        XCTAssertGreaterThan(neutral, female)
    }

    // MARK: Plans and the AI coach

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour))!
    }

    private func session(week: Int, day: Int, title: String = "S", category: WorkoutCategory = .cardio) -> PlanSession {
        PlanSession(week: week, day: day, title: title, category: category, durationMinutes: 30)
    }

    func testMondayBasedWeekday() {
        // 2026-11-16 is a Monday.
        XCTAssertEqual(TrainingPlan.mondayBasedWeekday(of: day(2026, 11, 16), calendar: utc), 1)
        XCTAssertEqual(TrainingPlan.mondayBasedWeekday(of: day(2026, 11, 18), calendar: utc), 3)
        XCTAssertEqual(TrainingPlan.mondayBasedWeekday(of: day(2026, 11, 22), calendar: utc), 7)
    }

    func testPlanSchedulingFromAMidweekStart() {
        // Started on a Wednesday: Wednesday sessions are that day, Monday sessions the following Monday.
        var plan = TrainingPlan(title: "P", goal: "G", summary: "", weeks: 2,
                                sessions: [session(week: 1, day: 3), session(week: 1, day: 1), session(week: 2, day: 3)])
        plan.startDate = day(2026, 11, 18)

        XCTAssertEqual(plan.scheduledDate(for: plan.sessions[0], calendar: utc), day(2026, 11, 18, hour: 0))
        XCTAssertEqual(plan.scheduledDate(for: plan.sessions[1], calendar: utc), day(2026, 11, 23, hour: 0))
        XCTAssertEqual(plan.scheduledDate(for: plan.sessions[2], calendar: utc), day(2026, 11, 25, hour: 0))
        XCTAssertEqual(plan.endDate(calendar: utc), day(2026, 12, 1, hour: 0))

        XCTAssertEqual(plan.state(of: plan.sessions[0], now: day(2026, 11, 18), calendar: utc), .today)
        XCTAssertEqual(plan.state(of: plan.sessions[1], now: day(2026, 11, 18), calendar: utc), .upcoming)
        XCTAssertEqual(plan.state(of: plan.sessions[0], now: day(2026, 11, 20), calendar: utc), .missed)

        XCTAssertNil(plan.currentWeek(now: day(2026, 11, 17), calendar: utc))
        XCTAssertEqual(plan.currentWeek(now: day(2026, 11, 18), calendar: utc), 1)
        XCTAssertEqual(plan.currentWeek(now: day(2026, 11, 25), calendar: utc), 2)
        XCTAssertEqual(plan.currentWeek(now: day(2027, 3, 1), calendar: utc), 2, "capped at the last week")
    }

    func testUnstartedPlanHasNoDates() {
        let plan = TrainingPlan(title: "P", goal: "G", summary: "", weeks: 1, sessions: [session(week: 1, day: 1)])
        XCTAssertNil(plan.scheduledDate(for: plan.sessions[0], calendar: utc))
        XCTAssertEqual(plan.state(of: plan.sessions[0], calendar: utc), .unscheduled)
        XCTAssertEqual(plan.nextSession(calendar: utc)?.id, plan.sessions[0].id)
    }

    func testNextSessionSkipsDoneAndPrefersUpcomingOverMissed() {
        var plan = TrainingPlan(title: "P", goal: "G", summary: "", weeks: 1,
                                sessions: [session(week: 1, day: 1, title: "mon"), session(week: 1, day: 3, title: "wed"),
                                           session(week: 1, day: 5, title: "fri")])
        plan.startDate = day(2026, 11, 16)    // a Monday
        // On Wednesday, Monday is missed; the next one is Wednesday.
        XCTAssertEqual(plan.nextSession(now: day(2026, 11, 18), calendar: utc)?.title, "wed")
        plan.sessions[1].completedAt = day(2026, 11, 18)
        XCTAssertEqual(plan.nextSession(now: day(2026, 11, 18), calendar: utc)?.title, "fri")
        // Past the end, only the missed ones remain.
        plan.sessions[2].skipped = true
        XCTAssertEqual(plan.nextSession(now: day(2026, 11, 30), calendar: utc)?.title, "mon")
        XCTAssertEqual(plan.completedSessions, 1)
        XCTAssertEqual(plan.skippedSessions, 1)
        XCTAssertEqual(plan.progress, 1.0 / 3.0, accuracy: 0.001)
    }

    @MainActor
    func testPlanStoreLifecycle() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-plans.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = PlanStore(fileURL: url)
        let first = store.add(TrainingPlan(title: "A", goal: "g", summary: "", weeks: 1,
                                           sessions: [session(week: 1, day: 1), session(week: 1, day: 2)]))
        let second = store.add(TrainingPlan(title: "B", goal: "g", summary: "", weeks: 1, sessions: [session(week: 1, day: 1)]))
        XCTAssertEqual(store.proposedPlans.count, 2)
        XCTAssertNil(store.activePlan)

        store.start(first.id, on: Date())
        XCTAssertEqual(store.activePlan?.id, first.id)

        // Starting another plan archives the first.
        store.start(second.id, on: Date())
        XCTAssertEqual(store.activePlan?.id, second.id)
        XCTAssertEqual(store.plan(id: first.id)?.status, .archived)

        // Completing every session finishes the plan; undoing reopens it.
        let sessionID = store.plan(id: second.id)!.sessions[0].id
        let workoutID = UUID()
        store.complete(sessionID: sessionID, workoutID: workoutID)
        XCTAssertEqual(store.plan(id: second.id)?.status, .completed)
        XCTAssertEqual(store.plan(id: second.id)?.sessions[0].completedWorkoutID, workoutID)
        store.undoCompletion(sessionID: sessionID)
        XCTAssertEqual(store.plan(id: second.id)?.status, .active)

        // Skipping counts as handled, so the plan can finish without that session.
        store.setSkipped(true, sessionID: sessionID)
        XCTAssertEqual(store.plan(id: second.id)?.status, .completed)
        store.setSkipped(false, sessionID: sessionID)
        XCTAssertEqual(store.plan(id: second.id)?.status, .active)

        // Persists.
        let reloaded = PlanStore(fileURL: url)
        XCTAssertEqual(reloaded.plans.count, 2)
        reloaded.delete(first.id)
        XCTAssertEqual(reloaded.plans.count, 1)
    }

    func testPlanDraftDecodingAndConversion() throws {
        let json = #"""
        {
          "title": "8-week bench builder", "goal": "Add 10 kg", "summary": "Heavy and light days.", "weeks": 8,
          "sessions": [
            { "week": 2, "day": 3, "title": "Easy run", "type": "cardio", "activity": "Running", "durationMinutes": 30,
              "targetDistanceKm": 5, "intensity": "easy" },
            { "week": 1, "day": 1, "title": "Heavy bench", "type": "strength", "durationMinutes": 60,
              "exercises": [ { "name": "Bench Press (Barbell)", "sets": 5, "reps": "5", "percentOfOneRepMax": 80,
                               "muscles": ["chest", "nonsense"] } ] }
          ]
        }
        """#
        let draft = try JSONDecoder().decode(PlanDraft.self, from: Data(json.utf8))
        let plan = draft.makePlan()
        XCTAssertEqual(plan.status, .proposed)
        XCTAssertEqual(plan.weeks, 8)
        XCTAssertEqual(plan.sessions.map(\.title), ["Heavy bench", "Easy run"], "sorted by week then day")
        XCTAssertEqual(plan.sessions[0].category, .strength)
        XCTAssertEqual(plan.sessions[0].exercises[0].muscles, [.chest], "unknown muscles are dropped")
        XCTAssertEqual(plan.sessions[1].category, .cardio)
        XCTAssertEqual(plan.sessions[1].targetDistanceKm, 5)
    }

    func testPlanTemplatesMatchExercisesAndWeights() {
        // Different word order and punctuation still find the directory exercise.
        let planned = PlannedExercise(name: "barbell bench press", sets: 3, reps: "8-10", percentOfOneRepMax: 80)
        let resolved = PlanTemplates.resolveExercise(planned, in: ExerciseLibrary.all)
        XCTAssertEqual(resolved.id, BigLift.bench.exerciseID)

        // Something unknown becomes its own exercise, using the muscles the plan gave.
        let odd = PlannedExercise(name: "Landmine Press", sets: 3, reps: "10", muscles: [.shoulders])
        let custom = PlanTemplates.resolveExercise(odd, in: ExerciseLibrary.all)
        XCTAssertTrue(custom.id.hasPrefix("plan-"))
        XCTAssertEqual(custom.primary, [.shoulders])

        XCTAssertEqual(PlanTemplates.firstNumber(in: "8-10"), 8)
        XCTAssertEqual(PlanTemplates.firstNumber(in: "AMRAP"), 0)
        XCTAssertEqual(PlanTemplates.firstNumber(in: "45s"), 45)

        // 80% of a 100 kg estimated max is 80 kg; with no record there is nothing to prefill.
        let record = PersonalRecord(exerciseID: BigLift.bench.exerciseID, name: "Bench", weightKg: 100, reps: 1, date: Date())
        XCTAssertEqual(PlanTemplates.targetWeightKg(for: planned, record: record), 80)
        XCTAssertEqual(PlanTemplates.targetWeightKg(for: planned, record: nil), 0)
        // An explicit weight wins.
        let explicit = PlannedExercise(name: "x", sets: 1, reps: "5", percentOfOneRepMax: 80, weightKg: 42.5)
        XCTAssertEqual(PlanTemplates.targetWeightKg(for: explicit, record: record), 42.5)
    }

    func testStrengthAndActivityTemplates() {
        var strength = PlanSession(week: 1, day: 1, title: "Heavy bench", category: .strength, durationMinutes: 60)
        strength.exercises = [PlannedExercise(name: "Bench Press (Barbell)", sets: 4, reps: "5", percentOfOneRepMax: 80)]
        let record = PersonalRecord(exerciseID: BigLift.bench.exerciseID, name: "Bench", weightKg: 100, reps: 1, date: Date())
        let workout = PlanTemplates.template(for: strength, exercises: ExerciseLibrary.all) { _ in record }
        XCTAssertEqual(workout.category, .strength)
        XCTAssertEqual(workout.exercises.count, 1)
        XCTAssertEqual(workout.exercises[0].sets.count, 4)
        XCTAssertEqual(workout.exercises[0].sets[0].weightKg, 80)
        XCTAssertEqual(workout.exercises[0].sets[0].reps, 5)

        var run = PlanSession(week: 1, day: 2, title: "Easy 5 km", category: .cardio, durationMinutes: 30)
        run.activity = "Running"
        run.targetDistanceKm = 5
        run.intensity = "easy"
        let runWorkout = PlanTemplates.template(for: run, exercises: ExerciseLibrary.all) { _ in nil }
        XCTAssertEqual(runWorkout.name, "Running", "matches the Running tile")
        XCTAssertEqual(runWorkout.duration, 30)
        XCTAssertTrue(runWorkout.notes.contains("5 km"))
        XCTAssertNotNil(runWorkout.heat[.calves], "uses the activity's muscle map")
    }

    // A stand-in for the coach server.
    private final class FakeTransport: CoachTransport {
        var results: [Result<CoachReply, Error>]
        private(set) var received: [[CoachAPIMessage]] = []
        private(set) var contexts: [CoachContext] = []

        init(_ results: [Result<CoachReply, Error>]) { self.results = results }

        func send(messages: [CoachAPIMessage], context: CoachContext) async throws -> CoachReply {
            received.append(messages)
            contexts.append(context)
            return try results.removeFirst().get()
        }
    }

    @MainActor
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name).json")
    }

    @MainActor
    func testCoachChatSavesPlansAndRecoversFromErrors() async throws {
        let chatURL = tempURL("chat"), planURL = tempURL("plans"), workoutURL = tempURL("workouts")
        defer { [chatURL, planURL, workoutURL].forEach { try? FileManager.default.removeItem(at: $0) } }

        let draft = PlanDraft(title: "Bench builder", goal: "g", summary: "s", weeks: 4,
                              sessions: [PlanDraft.Session(week: 1, day: 1, title: "Heavy", type: "strength", durationMinutes: 45)])
        let transport = FakeTransport([
            .failure(CoachError.offline),
            .success(CoachReply(text: "Here's a plan.", plan: draft, refused: nil)),
            .success(CoachReply(text: "Sure, easy.", plan: nil, refused: nil))
        ])
        let coach = CoachModel(transport: transport, fileURL: chatURL)
        let plans = PlanStore(fileURL: planURL)
        let context = { CoachContext(today: "2026-11-16", weekday: "Monday", units: .init(weight: "kg", height: "cm"),
                                      body: nil, records: [], recentWorkouts: [], activePlan: nil, knownExercises: []) }

        // A failed send keeps the user's message and offers a retry.
        await coach.send("Help me bench more", context: context, plans: plans)
        XCTAssertEqual(coach.messages.count, 1)
        XCTAssertNotNil(coach.errorMessage)
        XCTAssertTrue(plans.plans.isEmpty)

        await coach.retry(context: context, plans: plans)
        XCTAssertNil(coach.errorMessage)
        XCTAssertEqual(coach.messages.count, 2, "retry doesn't repeat the user's message")
        XCTAssertEqual(plans.proposedPlans.count, 1)
        XCTAssertEqual(coach.messages.last?.planID, plans.proposedPlans.first?.id)

        // The next request carries the earlier turns, with a note about the plan that was made.
        await coach.send("Make it easier", context: context, plans: plans)
        let sent = transport.received.last!
        XCTAssertEqual(sent.map(\.role), ["user", "assistant", "user"])
        XCTAssertTrue(sent[1].content.contains("Plan created: \"Bench builder\""))
        XCTAssertEqual(sent.last?.content, "Make it easier")

        // Conversation survives a restart; clearing empties it.
        XCTAssertEqual(CoachModel(transport: transport, fileURL: chatURL).messages.count, 4)
        coach.clear()
        XCTAssertTrue(coach.messages.isEmpty)
        XCTAssertTrue(CoachModel(transport: transport, fileURL: chatURL).messages.isEmpty)
    }

    @MainActor
    func testCoachContextRespectsPrivacyChoice() throws {
        let workoutURL = tempURL("workouts"), planURL = tempURL("plans")
        defer { [workoutURL, planURL].forEach { try? FileManager.default.removeItem(at: $0) } }

        let store = WorkoutStore(fileURL: workoutURL)
        let plans = PlanStore(fileURL: planURL)
        var w = workout(minutes: 45, muscles: [.quads: 0.8])
        w.exercises = [LoggedExercise(exerciseID: BigLift.squat.exerciseID, name: BigLift.squat.exerciseName,
                                      primary: [.quads], secondary: [], sets: [LoggedSet(weightKg: 100, reps: 5)])]
        store.add(w)
        let profile = BodyProfile(gender: .female, age: 31, weightKg: 62.04, heightCm: 168.4)

        let shared = CoachContextBuilder.make(workouts: store, plans: plans, profile: profile,
                                              weightUnit: .lb, heightUnit: .feetInches, shareHistory: true)
        XCTAssertEqual(shared.body?.age, 31)
        XCTAssertEqual(shared.body?.weightKg, 62.0)
        XCTAssertEqual(shared.units.weight, "lb")
        XCTAssertEqual(shared.records.first?.exercise, BigLift.squat.exerciseName)
        XCTAssertEqual(shared.recentWorkouts.count, 1)
        XCTAssertFalse(shared.knownExercises.isEmpty)

        let private_ = CoachContextBuilder.make(workouts: store, plans: plans, profile: profile,
                                                weightUnit: .kg, heightUnit: .cm, shareHistory: false)
        XCTAssertNil(private_.body)
        XCTAssertTrue(private_.records.isEmpty)
        XCTAssertTrue(private_.recentWorkouts.isEmpty)

        // Nothing that identifies the person, and no gender, is ever included.
        let json = String(decoding: try JSONEncoder().encode(shared), as: UTF8.self).lowercased()
        for forbidden in ["email", "username", "gender", "female"] {
            XCTAssertFalse(json.contains(forbidden), "context should not contain \(forbidden)")
        }
    }

    // MARK: Crystal hologram

    func testCrystalMeshIsBuiltFromTheLowPolyTriangles() throws {
        let base = try XCTUnwrap(BodyAsset.loadBase())
        XCTAssertGreaterThan(base.lowPolyTriangles.count, 3 * 1000, "low-poly triangles missing")
        XCTAssertLessThan(base.lowPolyTriangles.count, 3 * 6000)
        XCTAssertEqual(base.lowPolyTriangles.count % 3, 0)
        XCTAssertTrue(base.lowPolyTriangles.allSatisfy { Int($0) < base.positions.count })

        let mesh = BodyAsset.morph(base, profile: BodyProfile(gender: .male))
        let crystal = BodyAsset.crystal(for: mesh, triangles: base.lowPolyTriangles)

        XCTAssertGreaterThan(crystal.triangleCount, 1000)
        XCTAssertEqual(crystal.positions.count, crystal.normals.count)
        XCTAssertEqual(crystal.positions.count, crystal.corners.count)
        XCTAssertEqual(crystal.positions.count % 3, 0)
        // Flat shading: every unit normal, pointing away from the body's centre line.
        XCTAssertTrue(crystal.normals.allSatisfy { abs(simd_length($0) - 1) < 0.01 })

        // Each edge appears once, so there are fewer edges than triangle sides.
        XCTAssertEqual(crystal.edgePositions.count % 2, 0)
        XCTAssertLessThan(crystal.edgePositions.count / 2, crystal.triangleCount * 3)
        XCTAssertGreaterThan(crystal.edgePositions.count / 2, crystal.triangleCount)
        XCTAssertEqual(crystal.edgePositions.count, crystal.edgeVertices.count)
        XCTAssertEqual(crystal.dotPositions.count, crystal.dotVertices.count)
        XCTAssertGreaterThan(crystal.dotPositions.count, 1000)

        // Colors: one per corner, edge vertex and node; heat changes them.
        let cold = BodyAsset.crystalFillColors(for: crystal, mesh: mesh, heat: [:])
        let hot = BodyAsset.crystalFillColors(for: crystal, mesh: mesh, heat: [.chest: 1.0])
        XCTAssertEqual(cold.count, crystal.positions.count)
        XCTAssertNotEqual(cold, hot)
        XCTAssertEqual(BodyAsset.crystalLineColors(vertices: crystal.edgeVertices, mesh: mesh, heat: [:], edge: true).count,
                       crystal.edgeVertices.count)

        // Worked muscles get their own bright layer; nothing is drawn when nothing is worked.
        XCTAssertTrue(BodyAsset.crystalHeatFacets(for: crystal, mesh: mesh, heat: [:]).positions.isEmpty)
        let layer = BodyAsset.crystalHeatFacets(for: crystal, mesh: mesh, heat: [.chest: 1.0])
        XCTAssertFalse(layer.positions.isEmpty)
        XCTAssertEqual(layer.positions.count % 3, 0)
        XCTAssertEqual(layer.positions.count, layer.colors.count)
        XCTAssertLessThan(layer.positions.count, crystal.positions.count / 4, "only the chest, not the whole body")
        // Strongest heat is red: red channel leads.
        XCTAssertTrue(layer.colors.allSatisfy { $0.x > $0.z })
    }

    func testCrystalStyleKeepsOnlyMuscleOutlines() throws {
        let mesh = try XCTUnwrap(BodyAsset.load())
        let crystalLines = BodyAsset.lines(for: mesh, style: .crystal)
        XCTAssertFalse(crystalLines.kind.isEmpty)
        XCTAssertTrue(crystalLines.kind.allSatisfy { $0 == 2 }, "crystal draws its own facets; only outlines remain")
        let regular = BodyAsset.lines(for: mesh, style: .lines)
        XCTAssertTrue(regular.kind.contains(0))
        XCTAssertTrue(regular.kind.contains(1))
    }

    func testHologramStylesIncludeCrystalFirst() {
        XCTAssertEqual(HologramStyle.allCases.first, .crystal)
        XCTAssertEqual(Set(HologramStyle.allCases.map(\.title)), ["Crystal", "Lines", "Grid"])
    }

    func testBodyTabAddsUpEveryWorkoutAndKeepsRising() {
        let now = Date()
        // Moderate sessions, so there is headroom to keep climbing.
        let a = workout(minutes: 45, daysAgo: 0, muscles: [.chest: 0.5, .triceps: 0.65], now: now)
        let b = workout(minutes: 45, daysAgo: 1, muscles: [.chest: 0.5, .lats: 0.65], now: now)
        let c = workout(minutes: 45, daysAgo: 2, muscles: [.chest: 0.5, .quads: 1.0], now: now)
        let d = workout(minutes: 45, daysAgo: 3, muscles: [.chest: 0.5], now: now)

        func heat(_ workouts: [Workout]) -> [MuscleGroup: Double] {
            HeatCalculator.recoveryHeat(workouts: workouts, now: now)
        }

        // The chest keeps climbing with every extra session; none of them is ignored.
        let counts = (1...4).map { heat(Array([a, b, c, d].prefix($0)))[.chest] ?? 0 }
        for i in 1..<counts.count {
            XCTAssertGreaterThan(counts[i], counts[i - 1], "workout \(i + 1) should still raise the chest")
        }
        XCTAssertLessThan(counts.last ?? 2, 1.0)

        // Muscles from every workout show up together.
        let all = heat([a, b, c, d])
        for muscle in [MuscleGroup.chest, .triceps, .lats, .quads] {
            XCTAssertNotNil(all[muscle], "\(muscle) from one of the workouts is missing")
        }
        // Order doesn't matter.
        XCTAssertEqual(heat([d, c, b, a])[.chest] ?? 0, all[.chest] ?? 1, accuracy: 1e-9)
    }

    func testOneHeavyShortWorkoutLooksTheSameOnTheBodyTab() {
        // The bug this guards against: a 30-minute climb with heavy forearms read as yellow on the
        // Body tab although the workout itself showed red.
        let now = Date()
        var climb = Workout(name: "Bouldering", category: .climbing, duration: 30, notes: "", date: now)
        climb.heat = [.forearms: HeatLevel.heavy.intensity, .lats: HeatLevel.heavy.intensity, .biceps: HeatLevel.moderate.intensity]

        let body = HeatCalculator.recoveryHeat(workouts: [climb], now: now)
        XCTAssertEqual(body[.forearms] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(body[.biceps] ?? 0, HeatLevel.moderate.intensity, accuracy: 0.001)

        // A longer session is boosted a little but never past the top.
        var long = climb
        long.duration = 90
        long.heat = [.biceps: HeatLevel.moderate.intensity]
        XCTAssertGreaterThan(HeatCalculator.recoveryHeat(workouts: [long], now: now)[.biceps] ?? 0, HeatLevel.moderate.intensity)
        XCTAssertLessThanOrEqual(HeatCalculator.recoveryHeat(workouts: [long], now: now)[.biceps] ?? 2, 1.0)
    }
}
