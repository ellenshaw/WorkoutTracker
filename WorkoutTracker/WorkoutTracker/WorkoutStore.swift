//
//  WorkoutStore.swift
//  WorkoutTracker
//

import Foundation

/// Holds all workouts and saves them as JSON in the app's Documents folder.
@MainActor
final class WorkoutStore: ObservableObject {
    @Published private(set) var workouts: [Workout] = []

    @Published private(set) var customExercises: [Exercise] = []
    /// Records typed in by hand, for lifts done outside the app.
    @Published private(set) var manualRecords: [PersonalRecord] = []

    private let fileURL: URL
    private let exercisesURL: URL
    private let recordsURL: URL

    init(fileURL: URL? = nil) {
        let url = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workouts.json")
        self.fileURL = url
        self.exercisesURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-exercises.json")
        self.recordsURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-records.json")
        load()
    }

    /// Built-in directory plus the user's own exercises, A to Z.
    var allExercises: [Exercise] {
        (ExerciseLibrary.all + customExercises).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var pinnedWorkouts: [Workout] {
        workouts.filter(\.isPinned)
    }

    /// The sets from the most recent workout that included this exercise.
    func lastSets(for exerciseID: String) -> [LoggedSet] {
        for workout in workouts {
            if let match = workout.exercises.first(where: { $0.exerciseID == exerciseID }) {
                return match.sets
            }
        }
        return []
    }

    func togglePin(_ workoutID: UUID) {
        guard let index = workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        workouts[index].isPinned.toggle()
        save()
    }

    func setManualRecord(_ record: PersonalRecord) {
        var saved = record
        saved.isManual = true
        manualRecords.removeAll { $0.exerciseID == record.exerciseID }
        manualRecords.append(saved)
        saveRecords()
    }

    func clearManualRecord(exerciseID: String) {
        manualRecords.removeAll { $0.exerciseID == exerciseID }
        saveRecords()
    }

    @discardableResult
    func addCustomExercise(name: String, primary: [MuscleGroup], secondary: [MuscleGroup]) -> Exercise {
        let exercise = Exercise(id: "custom-" + UUID().uuidString, name: name, primary: primary,
                                secondary: secondary, isCustom: true)
        customExercises.append(exercise)
        saveExercises()
        return exercise
    }

    var workoutsThisWeek: [Workout] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return workouts.filter { $0.date >= start }
    }

    var minutesThisWeek: Int {
        workoutsThisWeek.reduce(0) { $0 + $1.duration }
    }

    /// Muscle heat now: recent workouts count most, and each one fades as time passes.
    func currentHeat(halfLifeDays: Double = 3.5) -> [MuscleGroup: Double] {
        HeatCalculator.recoveryHeat(workouts: workouts, halfLifeDays: halfLifeDays)
    }

    func add(_ workout: Workout) {
        workouts.append(workout)
        workouts.sort { $0.date > $1.date }
        save()
    }

    func delete(at offsets: IndexSet) {
        workouts.remove(atOffsets: offsets)
        save()
    }

    func removeAll() {
        workouts = []
        customExercises = []
        manualRecords = []
        save()
        saveExercises()
        saveRecords()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([Workout].self, from: data) {
            workouts = decoded.sorted { $0.date > $1.date }
        }
        if let data = try? Data(contentsOf: exercisesURL),
           let decoded = try? JSONDecoder().decode([Exercise].self, from: data) {
            customExercises = decoded
        }
        if let data = try? Data(contentsOf: recordsURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([PersonalRecord].self, from: data) {
                manualRecords = decoded
            }
        }
    }

    private func saveRecords() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(manualRecords) else { return }
        try? data.write(to: recordsURL, options: [.atomic])
    }

    private func saveExercises() {
        guard let data = try? JSONEncoder().encode(customExercises) else { return }
        try? data.write(to: exercisesURL, options: [.atomic])
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(workouts) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
