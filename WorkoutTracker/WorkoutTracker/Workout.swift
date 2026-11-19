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
    /// Muscle raw value → intensity in percent (0–100). Stored with String keys so JSON stays an object.
    var muscleIntensity: [String: Int] = [:]
    /// Filled for strength workouts (Hevy-style exercises with sets).
    var exercises: [LoggedExercise] = []
    /// Pinned workouts show up on the home screen as one-tap templates.
    var isPinned = false
    /// Session type ("Game", "Tempo", "Practice"...) and position or style ("Cutter", "Handler"...).
    var mode = ""
    var role = ""

    init(id: UUID = UUID(),
         name: String,
         category: WorkoutCategory,
         duration: Int,
         notes: String,
         date: Date,
         muscleIntensity: [String: Int] = [:],
         exercises: [LoggedExercise] = [],
         isPinned: Bool = false,
         mode: String = "",
         role: String = "") {
        self.id = id
        self.name = name
        self.category = category
        self.duration = duration
        self.notes = notes
        self.date = date
        self.muscleIntensity = muscleIntensity
        self.exercises = exercises
        self.isPinned = isPinned
        self.mode = mode
        self.role = role
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, duration, notes, date, muscleIntensity, exercises, isPinned, mode, role
        /// Written by older versions as steps 1–3 instead of percentages.
        case muscleLevels
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
        exercises = try c.decodeIfPresent([LoggedExercise].self, forKey: .exercises) ?? []
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""

        if let percent = try c.decodeIfPresent([String: Int].self, forKey: .muscleIntensity) {
            muscleIntensity = percent
        } else if let legacy = try c.decodeIfPresent([String: Int].self, forKey: .muscleLevels) {
            muscleIntensity = legacy.compactMapValues { step in
                HeatLevel(rawValue: step).flatMap { $0 == HeatLevel.none ? nil : Int($0.intensity * 100) }
            }
        } else {
            muscleIntensity = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(duration, forKey: .duration)
        try c.encode(notes, forKey: .notes)
        try c.encode(date, forKey: .date)
        try c.encode(muscleIntensity, forKey: .muscleIntensity)
        try c.encode(exercises, forKey: .exercises)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(mode, forKey: .mode)
        try c.encode(role, forKey: .role)
    }

    /// How hard each muscle was worked, 0 (not at all) to 1 (maximum).
    var heat: [MuscleGroup: Double] {
        get {
            var result: [MuscleGroup: Double] = [:]
            for (key, percent) in muscleIntensity {
                if let muscle = MuscleGroup(rawValue: key), percent > 0 {
                    result[muscle] = min(Double(percent), 100) / 100
                }
            }
            return result
        }
        set {
            var stored: [String: Int] = [:]
            for (muscle, value) in newValue where value > 0 {
                stored[muscle.rawValue] = Int((min(value, 1) * 100).rounded())
            }
            muscleIntensity = stored
        }
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var totalVolumeKg: Double {
        exercises.reduce(0) { $0 + $1.volumeKg }
    }

    /// "Game · Cutter": the session type and position, when there are any.
    var variantText: String {
        [mode, role].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// One-line description for lists and pinned cards.
    var summary: String {
        if exercises.isEmpty {
            return variantText.isEmpty ? "\(duration) min" : "\(duration) min · \(variantText)"
        }
        let count = exercises.count
        return "\(count) exercise\(count == 1 ? "" : "s") · \(totalSets) sets"
    }
}
