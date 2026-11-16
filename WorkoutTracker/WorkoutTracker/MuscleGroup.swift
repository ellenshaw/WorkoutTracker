//
//  MuscleGroup.swift
//  WorkoutTracker
//

import SwiftUI
import UIKit

/// How hard a muscle was worked. Maps directly to the heat colors on the 3D model.
enum HeatLevel: Int, CaseIterable, Comparable, Codable {
    case none = 0
    case light      // yellow
    case moderate   // orange
    case heavy      // red

    static func < (lhs: HeatLevel, rhs: HeatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .none: return "Not used"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .none: return .systemGray
        case .light: return UIColor(red: 1.00, green: 0.84, blue: 0.20, alpha: 1)
        case .moderate: return UIColor(red: 1.00, green: 0.54, blue: 0.10, alpha: 1)
        case .heavy: return UIColor(red: 0.93, green: 0.16, blue: 0.16, alpha: 1)
        }
    }

    var color: Color { Color(uiColor) }

    /// Tap-to-cycle order used by the muscle chips: none → light → moderate → heavy → none.
    var next: HeatLevel {
        HeatLevel(rawValue: (rawValue + 1) % HeatLevel.allCases.count) ?? .none
    }
}

enum MuscleGroup: String, CaseIterable, Codable, Identifiable {
    case chest, shoulders, biceps, triceps, forearms
    case abs, obliques, traps, lats, lowerBack
    case glutes, quads, hamstrings, calves

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .traps: return "Traps"
        case .lats: return "Lats"
        case .lowerBack: return "Lower back"
        case .glutes: return "Glutes"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .calves: return "Calves"
        }
    }

    /// Groups shown as sections in the muscle picker.
    static let regions: [(name: String, muscles: [MuscleGroup])] = [
        ("Upper body", [.chest, .shoulders, .biceps, .triceps, .forearms]),
        ("Back & core", [.traps, .lats, .lowerBack, .abs, .obliques]),
        ("Lower body", [.glutes, .quads, .hamstrings, .calves])
    ]
}

enum WorkoutCategory: String, CaseIterable, Codable, Identifiable {
    case strength = "Strength"
    case cardio = "Cardio"
    case climbing = "Climbing"
    case sport = "Sport"
    case mobility = "Mobility"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .climbing: return "figure.climbing"
        case .sport: return "sportscourt.fill"
        case .mobility: return "figure.flexibility"
        }
    }

    /// Distinct from the yellow / orange / red heat colors so the two never get confused.
    var tint: Color {
        switch self {
        case .strength: return Color(red: 0.30, green: 0.56, blue: 1.0)
        case .cardio: return Color(red: 0.90, green: 0.38, blue: 0.70)
        case .climbing: return Color(red: 0.18, green: 0.74, blue: 0.70)
        case .sport: return Color(red: 0.36, green: 0.78, blue: 0.40)
        case .mobility: return Color(red: 0.62, green: 0.47, blue: 0.96)
        }
    }

    var subtitle: String {
        switch self {
        case .strength: return "Lifts, sets and reps"
        case .cardio: return "Run, ride, swim and more"
        case .climbing: return "Boulder, rope, hangboard"
        case .sport: return "Court, field and combat"
        case .mobility: return "Yoga, stretching, pilates"
        }
    }
}

/// Pure calculation so it can be unit tested without a store.
enum HeatCalculator {
    /// Turns a strength session into muscle heat. A set counts 1 for each primary muscle and
    /// 0.5 for each secondary muscle; 4+ points is moderate, 8+ is heavy.
    static func strengthHeat(exercises: [LoggedExercise]) -> [MuscleGroup: HeatLevel] {
        var scores: [MuscleGroup: Double] = [:]
        for exercise in exercises {
            let sets = Double(exercise.sets.count)
            for muscle in exercise.primary { scores[muscle, default: 0] += sets }
            for muscle in exercise.secondary { scores[muscle, default: 0] += sets * 0.5 }
        }
        var result: [MuscleGroup: HeatLevel] = [:]
        for (muscle, score) in scores {
            if score >= 8 {
                result[muscle] = .heavy
            } else if score >= 4 {
                result[muscle] = .moderate
            } else if score > 0 {
                result[muscle] = .light
            }
        }
        return result
    }

    /// Combines recent workouts into one heat level per muscle.
    ///
    /// Each workout contributes `level × (duration / 45 min)`, with the duration factor clamped
    /// to 0.5…1.5 so one marathon session can't dominate. A single ~45 minute workout therefore
    /// keeps the color the user picked, and repeated sessions push a muscle up a level.
    static func weeklyHeat(workouts: [Workout], now: Date = Date(), days: Int = 7) -> [MuscleGroup: HeatLevel] {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return [:] }

        var scores: [MuscleGroup: Double] = [:]
        for workout in workouts where workout.date >= start && workout.date <= now {
            let factor = min(max(Double(workout.duration) / 45.0, 0.5), 1.5)
            for (muscle, level) in workout.heat {
                scores[muscle, default: 0] += Double(level.rawValue) * factor
            }
        }

        var result: [MuscleGroup: HeatLevel] = [:]
        for (muscle, score) in scores {
            if score >= 3 {
                result[muscle] = .heavy
            } else if score >= 1.75 {
                result[muscle] = .moderate
            } else if score > 0 {
                result[muscle] = .light
            }
        }
        return result
    }
}
