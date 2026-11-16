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

    private let fileURL: URL
    private let exercisesURL: URL

    init(fileURL: URL? = nil) {
        let url = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workouts.json")
        self.fileURL = url
        self.exercisesURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-exercises.json")
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

    func weeklyHeat() -> [MuscleGroup: Double] {
        HeatCalculator.weeklyHeat(workouts: workouts)
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
        save()
        saveExercises()
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
