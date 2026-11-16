//
//  Workout.swift
//  WorkoutTracker
//

import Foundation

struct Workout: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: WorkoutCategory
    var duration: Int
    var notes: String
    var date: Date
    /// Muscle raw value → `HeatLevel` raw value. Stored with String keys so JSON stays an object.
    var muscleLevels: [String: Int] = [:]

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
}
