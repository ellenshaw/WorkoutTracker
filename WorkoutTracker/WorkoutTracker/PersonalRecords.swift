//
//  PersonalRecords.swift
//  WorkoutTracker
//
//  Personal records (PRs). Every logged set counts automatically; a record can also be entered
//  by hand for lifts done elsewhere. A record is the set with the best estimated one-rep max.
//

import Foundation

struct PersonalRecord: Codable, Hashable, Identifiable {
    var exerciseID: String
    var name: String
    var weightKg: Double
    var reps: Int
    var date: Date
    /// Entered by hand rather than found in a logged workout.
    var isManual = false

    var id: String { exerciseID }

    var estimatedOneRepMaxKg: Double {
        PersonalRecord.estimateOneRepMax(weightKg: weightKg, reps: reps)
    }

    /// Epley formula; a single rep is its own one-rep max.
    static func estimateOneRepMax(weightKg: Double, reps: Int) -> Double {
        reps <= 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }
}

/// The three lifts every profile tracks.
enum BigLift: String, CaseIterable, Identifiable {
    case bench, squat, deadlift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bench: return "Bench Press"
        case .squat: return "Squat"
        case .deadlift: return "Deadlift"
        }
    }

    /// Name of the matching exercise in the directory, so logged sets feed the record.
    var exerciseName: String {
        switch self {
        case .bench: return "Bench Press (Barbell)"
        case .squat: return "Squat (Barbell)"
        case .deadlift: return "Deadlift (Barbell)"
        }
    }

    var exerciseID: String { Exercise.slug(exerciseName) }

    var icon: String {
        switch self {
        case .bench: return "figure.strengthtraining.traditional"
        case .squat: return "figure.strengthtraining.functional"
        case .deadlift: return "dumbbell.fill"
        }
    }
}

extension WorkoutStore {
    /// The best set ever for an exercise, from logged workouts and any manual record.
    /// Pass a workout to leave it out, to ask "did that workout beat everything else?".
    func bestRecord(for exerciseID: String, excluding workoutID: UUID? = nil) -> PersonalRecord? {
        var best: PersonalRecord?
        func consider(_ record: PersonalRecord) {
            if let current = best, current.estimatedOneRepMaxKg >= record.estimatedOneRepMaxKg { return }
            best = record
        }

        for workout in workouts where workout.id != workoutID {
            for exercise in workout.exercises where exercise.exerciseID == exerciseID {
                for set in exercise.sets where set.reps > 0 && set.weightKg > 0 {
                    consider(PersonalRecord(exerciseID: exerciseID, name: exercise.name,
                                            weightKg: set.weightKg, reps: set.reps, date: workout.date))
                }
            }
        }
        if let manual = manualRecords.first(where: { $0.exerciseID == exerciseID }) {
            consider(manual)
        }
        return best
    }

    /// One record for every exercise that has any, A to Z.
    func allRecords() -> [PersonalRecord] {
        var ids = Set(manualRecords.map(\.exerciseID))
        for workout in workouts {
            for exercise in workout.exercises { ids.insert(exercise.exerciseID) }
        }
        return ids.compactMap { bestRecord(for: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// True when this workout's best set for the exercise beats everything logged before or after it.
    func isPersonalRecord(_ exercise: LoggedExercise, in workout: Workout) -> Bool {
        let mine = exercise.sets
            .filter { $0.reps > 0 && $0.weightKg > 0 }
            .map { PersonalRecord.estimateOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }
            .max()
        guard let mine, let previous = bestRecord(for: exercise.exerciseID, excluding: workout.id) else {
            return false
        }
        return mine > previous.estimatedOneRepMaxKg + 0.001
    }

    /// Estimated one-rep max for the three big lifts added together.
    var bigThreeTotalKg: Double {
        BigLift.allCases.reduce(0) { $0 + (bestRecord(for: $1.exerciseID)?.estimatedOneRepMaxKg ?? 0) }
    }
}
