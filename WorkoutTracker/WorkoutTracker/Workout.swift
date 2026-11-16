//
//  Workout.swift
//  WorkoutTracker
//

import Foundation

struct LoggedSet: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Always stored in kilograms; converted for display by `WeightUnit`.
    var weightKg: Double
    var reps: Int
}

struct LoggedExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseID: String
    var name: String
    var primary: [MuscleGroup]
    var secondary: [MuscleGroup]
    var sets: [LoggedSet]

    var volumeKg: Double {
        sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }
}

struct Workout: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: WorkoutCategory
    var duration: Int
    var notes: String
    var date: Date
    /// Muscle raw value → `HeatLevel` raw value. Stored with String keys so JSON stays an object.
    var muscleLevels: [String: Int] = [:]
    /// Filled for strength workouts (Hevy-style exercises with sets).
    var exercises: [LoggedExercise] = []
    /// Pinned workouts show up on the home screen as one-tap templates.
    var isPinned = false

    init(id: UUID = UUID(),
         name: String,
         category: WorkoutCategory,
         duration: Int,
         notes: String,
         date: Date,
         muscleLevels: [String: Int] = [:],
         exercises: [LoggedExercise] = [],
         isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.duration = duration
        self.notes = notes
        self.date = date
        self.muscleLevels = muscleLevels
        self.exercises = exercises
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, duration, notes, date, muscleLevels, exercises, isPinned
    }

    // Tolerant decoding so data saved by older versions keeps loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(WorkoutCategory.self, forKey: .category) ?? .strength
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        date = try c.decode(Date.self, forKey: .date)
        muscleLevels = try c.decodeIfPresent([String: Int].self, forKey: .muscleLevels) ?? [:]
        exercises = try c.decodeIfPresent([LoggedExercise].self, forKey: .exercises) ?? []
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    var heat: [MuscleGroup: HeatLevel] {
        get {
            var result: [MuscleGroup: HeatLevel] = [:]
            for (key, value) in muscleLevels {
                if let muscle = MuscleGroup(rawValue: key), let level = HeatLevel(rawValue: value), level != .none {
                    result[muscle] = level
                }
            }
            return result
        }
        set {
            var levels: [String: Int] = [:]
            for (muscle, level) in newValue where level != HeatLevel.none {
                levels[muscle.rawValue] = level.rawValue
            }
            muscleLevels = levels
        }
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var totalVolumeKg: Double {
        exercises.reduce(0) { $0 + $1.volumeKg }
    }

    /// One-line description for lists and pinned cards.
    var summary: String {
        if exercises.isEmpty {
            return "\(duration) min"
        }
        let count = exercises.count
        return "\(count) exercise\(count == 1 ? "" : "s") · \(totalSets) sets"
    }
}
