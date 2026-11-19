//
//  MuscleGroup.swift
//  WorkoutTracker
//

import SwiftUI
import simd

/// The heat scale used everywhere: cold blue (not used) through cyan, green and yellow to hot red.
enum HeatScale {
    private static let stops: [(position: Double, color: SIMD3<Float>)] = [
        (0.0, SIMD3<Float>(0.12, 0.45, 1.00)),   // blue
        (0.2, SIMD3<Float>(0.00, 0.85, 1.00)),   // cyan
        (0.4, SIMD3<Float>(0.20, 0.90, 0.40)),   // green
        (0.6, SIMD3<Float>(1.00, 0.90, 0.20)),   // yellow
        (0.8, SIMD3<Float>(1.00, 0.55, 0.10)),   // orange
        (1.0, SIMD3<Float>(0.93, 0.16, 0.16))    // red
    ]

    /// Color for an intensity from 0 (not worked) to 1 (maximum).
    ///
    /// Zero is the cold blue of the body. Anything above zero jumps to at least cyan, so even a
    /// light or faded muscle is clearly a different color from the unworked body instead of
    /// blending into it.
    static func rgb(_ value: Double) -> SIMD3<Float> {
        let clamped = min(max(value, 0), 1)
        let t = clamped > 0 ? 0.2 + 0.8 * clamped : 0
        for i in 0..<(stops.count - 1) {
            let lower = stops[i]
            let upper = stops[i + 1]
            if t <= upper.position {
                let u = Float((t - lower.position) / (upper.position - lower.position))
                return lower.color * (1 - u) + upper.color * u
            }
        }
        return stops[stops.count - 1].color
    }

    static func color(_ value: Double) -> Color {
        let c = rgb(value)
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    /// Words for the breakdown list.
    static func label(_ value: Double) -> String {
        switch value {
        case ..<0.25: return "Light"
        case ..<0.5: return "Moderate"
        case ..<0.75: return "High"
        default: return "Max"
        }
    }

    static var gradient: LinearGradient {
        LinearGradient(
            stops: (0...10).map { step -> Gradient.Stop in
                let position = Double(step) / 10
                return Gradient.Stop(color: color(position), location: position)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// The four steps you cycle through when tapping a muscle chip. Each sits at a point on the heat scale.
enum HeatLevel: Int, CaseIterable, Comparable, Codable {
    case none = 0
    case light
    case moderate
    case heavy

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

    /// Position on the heat scale, 0 (cold blue) to 1 (hot red).
    var intensity: Double {
        switch self {
        case .none: return 0
        case .light: return 0.35
        case .moderate: return 0.65
        case .heavy: return 1.0
        }
    }

    /// The chip step closest to a continuous intensity.
    init(nearest intensity: Double) {
        if intensity <= 0 {
            self = .none
        } else if intensity < 0.5 {
            self = .light
        } else if intensity < 0.82 {
            self = .moderate
        } else {
            self = .heavy
        }
    }

    var color: Color {
        self == .none ? Color(.systemGray) : HeatScale.color(intensity)
    }

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
    /// Turns a strength session into muscle intensity (0...1). A set counts 1 for each primary
    /// muscle and 0.5 for each secondary muscle; 10 points is the top of the scale.
    static func strengthHeat(exercises: [LoggedExercise]) -> [MuscleGroup: Double] {
        var scores: [MuscleGroup: Double] = [:]
        for exercise in exercises {
            let sets = Double(exercise.sets.count)
            for muscle in exercise.primary { scores[muscle, default: 0] += sets }
            for muscle in exercise.secondary { scores[muscle, default: 0] += sets * 0.5 }
        }
        return scores.mapValues { min($0 / 10, 1) }
    }

    /// Combines recent workouts into one intensity per muscle, fading as time passes.
    ///
    /// Each workout contributes `intensity × (duration / 45 min)`, with the duration factor
    /// clamped to 0.5…1.5 so one marathon session can't dominate. Its contribution then halves
    /// every `halfLifeDays`, so a muscle's colour cools gradually from red back toward blue as it
    /// recovers instead of vanishing on a deadline. Repeated sessions stack up to the top of the scale.
    static func recoveryHeat(workouts: [Workout],
                             now: Date = Date(),
                             halfLifeDays: Double = 3.5,
                             maxDays: Double = 21) -> [MuscleGroup: Double] {
        var scores: [MuscleGroup: Double] = [:]
        for workout in workouts {
            let ageDays = max(now.timeIntervalSince(workout.date) / 86_400, 0)
            guard ageDays <= maxDays else { continue }

            let decay = pow(0.5, ageDays / max(halfLifeDays, 0.1))
            let factor = min(max(Double(workout.duration) / 45.0, 0.5), 1.5)
            for (muscle, intensity) in workout.heat {
                scores[muscle, default: 0] += intensity * factor * decay
            }
        }
        return scores.compactMapValues { score in
            score > 0.01 ? min(score / 1.2, 1) : nil
        }
    }
}
