//
//  WorkoutStore.swift
//  WorkoutTracker
//

import Foundation

/// Holds all workouts and saves them as JSON in the app's Documents folder.
@MainActor
final class WorkoutStore: ObservableObject {
    @Published private(set) var workouts: [Workout] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workouts.json")
        load()
    }

    var workoutsThisWeek: [Workout] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return workouts.filter { $0.date >= start }
    }

    var minutesThisWeek: Int {
        workoutsThisWeek.reduce(0) { $0 + $1.duration }
    }

    func weeklyHeat() -> [MuscleGroup: HeatLevel] {
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
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Workout].self, from: data) {
            workouts = decoded.sorted { $0.date > $1.date }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(workouts) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
