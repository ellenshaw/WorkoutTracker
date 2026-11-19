//
//  ExerciseLibrary.swift
//  WorkoutTracker
//
//  The built-in exercise directory (used for strength logging) and the activity
//  presets (used for cardio, climbing, sport and mobility).
//

import Foundation
import UIKit

// MARK: - Strength exercises

struct Exercise: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var primary: [MuscleGroup]
    var secondary: [MuscleGroup] = []
    var isCustom = false

    static func slug(_ name: String) -> String {
        name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
    }

    var muscleSummary: String {
        let main = primary.map(\.title).joined(separator: ", ")
        return secondary.isEmpty ? main : main + " · " + secondary.map(\.title).joined(separator: ", ")
    }
}

enum ExerciseLibrary {
    private static func ex(_ name: String, _ primary: [MuscleGroup], _ secondary: [MuscleGroup] = []) -> Exercise {
        Exercise(id: Exercise.slug(name), name: name, primary: primary, secondary: secondary)
    }

    private static let chest: [Exercise] = [
        ex("Bench Press (Barbell)", [.chest], [.shoulders, .triceps]),
        ex("Incline Bench Press (Barbell)", [.chest], [.shoulders, .triceps]),
        ex("Bench Press (Dumbbell)", [.chest], [.shoulders, .triceps]),
        ex("Incline Bench Press (Dumbbell)", [.chest], [.shoulders, .triceps]),
        ex("Chest Press (Machine)", [.chest], [.shoulders, .triceps]),
        ex("Chest Fly (Dumbbell)", [.chest], [.shoulders]),
        ex("Cable Fly Crossover", [.chest], [.shoulders]),
        ex("Pec Deck (Machine)", [.chest], [.shoulders]),
        ex("Push Up", [.chest], [.shoulders, .triceps, .abs]),
        ex("Chest Dip", [.chest, .triceps], [.shoulders])
    ]

    private static let back: [Exercise] = [
        ex("Deadlift (Barbell)", [.lowerBack, .glutes, .hamstrings], [.traps, .lats, .forearms, .quads]),
        ex("Pull Up", [.lats], [.biceps, .forearms, .traps]),
        ex("Chin Up", [.lats, .biceps], [.forearms]),
        ex("Lat Pulldown (Cable)", [.lats], [.biceps, .forearms]),
        ex("Bent Over Row (Barbell)", [.lats, .traps], [.biceps, .lowerBack, .forearms]),
        ex("One Arm Row (Dumbbell)", [.lats], [.biceps, .traps]),
        ex("Seated Cable Row", [.lats, .traps], [.biceps]),
        ex("T-Bar Row", [.lats, .traps], [.biceps, .lowerBack]),
        ex("Straight Arm Pulldown", [.lats]),
        ex("Face Pull", [.traps, .shoulders]),
        ex("Shrug (Dumbbell)", [.traps], [.forearms]),
        ex("Back Extension", [.lowerBack], [.glutes, .hamstrings])
    ]

    private static let shoulders: [Exercise] = [
        ex("Overhead Press (Barbell)", [.shoulders], [.triceps, .traps, .chest]),
        ex("Shoulder Press (Dumbbell)", [.shoulders], [.triceps]),
        ex("Shoulder Press (Machine)", [.shoulders], [.triceps]),
        ex("Arnold Press (Dumbbell)", [.shoulders], [.triceps]),
        ex("Lateral Raise (Dumbbell)", [.shoulders]),
        ex("Front Raise (Dumbbell)", [.shoulders], [.chest]),
        ex("Rear Delt Fly (Dumbbell)", [.shoulders], [.traps]),
        ex("Upright Row (Barbell)", [.shoulders, .traps], [.biceps])
    ]

    private static let arms: [Exercise] = [
        ex("Bicep Curl (Barbell)", [.biceps], [.forearms]),
        ex("Bicep Curl (Dumbbell)", [.biceps], [.forearms]),
        ex("Hammer Curl (Dumbbell)", [.biceps, .forearms]),
        ex("Preacher Curl", [.biceps]),
        ex("Incline Curl (Dumbbell)", [.biceps]),
        ex("Cable Curl", [.biceps], [.forearms]),
        ex("Tricep Pushdown (Cable)", [.triceps]),
        ex("Skullcrusher (Barbell)", [.triceps]),
        ex("Overhead Tricep Extension (Dumbbell)", [.triceps]),
        ex("Close Grip Bench Press (Barbell)", [.triceps], [.chest, .shoulders]),
        ex("Tricep Dip", [.triceps], [.chest, .shoulders]),
        ex("Tricep Kickback (Dumbbell)", [.triceps]),
        ex("Wrist Curl (Barbell)", [.forearms]),
        ex("Reverse Curl (Barbell)", [.forearms, .biceps]),
        ex("Farmer's Walk", [.forearms, .traps], [.abs])
    ]

    private static let legs: [Exercise] = [
        ex("Squat (Barbell)", [.quads, .glutes], [.hamstrings, .lowerBack, .abs]),
        ex("Front Squat (Barbell)", [.quads], [.glutes, .abs]),
        ex("Goblet Squat (Kettlebell)", [.quads, .glutes], [.abs]),
        ex("Hack Squat (Machine)", [.quads], [.glutes]),
        ex("Leg Press (Machine)", [.quads], [.glutes, .hamstrings]),
        ex("Lunge (Dumbbell)", [.quads, .glutes], [.hamstrings]),
        ex("Bulgarian Split Squat (Dumbbell)", [.quads, .glutes], [.hamstrings]),
        ex("Step Up (Dumbbell)", [.quads, .glutes]),
        ex("Leg Extension (Machine)", [.quads]),
        ex("Romanian Deadlift (Barbell)", [.hamstrings, .glutes], [.lowerBack, .forearms]),
        ex("Good Morning (Barbell)", [.hamstrings, .lowerBack], [.glutes]),
        ex("Lying Leg Curl (Machine)", [.hamstrings], [.calves]),
        ex("Seated Leg Curl (Machine)", [.hamstrings], [.calves]),
        ex("Hip Thrust (Barbell)", [.glutes], [.hamstrings]),
        ex("Glute Bridge", [.glutes], [.hamstrings]),
        ex("Hip Abduction (Machine)", [.glutes]),
        ex("Kettlebell Swing", [.glutes, .hamstrings], [.lowerBack, .shoulders, .forearms]),
        ex("Standing Calf Raise (Machine)", [.calves]),
        ex("Seated Calf Raise (Machine)", [.calves])
    ]

    private static let core: [Exercise] = [
        ex("Crunch", [.abs]),
        ex("Sit Up", [.abs]),
        ex("Cable Crunch", [.abs]),
        ex("Hanging Leg Raise", [.abs], [.forearms]),
        ex("Plank", [.abs], [.shoulders, .lowerBack]),
        ex("Side Plank", [.obliques], [.abs, .shoulders]),
        ex("Russian Twist", [.obliques], [.abs]),
        ex("Bicycle Crunch", [.abs, .obliques]),
        ex("Cable Woodchopper", [.obliques], [.abs, .shoulders]),
        ex("Ab Wheel Rollout", [.abs], [.shoulders, .lats])
    ]

    static let all: [Exercise] = chest + back + shoulders + arms + legs + core
}

// MARK: - Activity presets (non-strength)

struct ActivityPreset: Identifiable, Hashable {
    let name: String
    let icon: String
    /// Muscles this activity typically works, used as the starting point for the 3D map.
    let muscles: [MuscleGroup: HeatLevel]

    var id: String { name }

    /// The icon, falling back to a generic one if this iOS version doesn't have that symbol.
    var symbol: String {
        UIImage(systemName: icon) != nil ? icon : "sportscourt.fill"
    }
}

extension WorkoutCategory {
    /// Tap-to-pick blocks shown when logging this category. Strength uses the exercise directory instead.
    var activities: [ActivityPreset] {
        switch self {
        case .strength:
            return []

        case .cardio:
            return [
                ActivityPreset(name: "Running", icon: "figure.run",
                               muscles: [.quads: .moderate, .hamstrings: .moderate, .calves: .heavy, .glutes: .moderate, .abs: .light]),
                ActivityPreset(name: "Walking", icon: "figure.walk",
                               muscles: [.calves: .light, .quads: .light, .glutes: .light, .hamstrings: .light]),
                ActivityPreset(name: "Cycling", icon: "figure.outdoor.cycle",
                               muscles: [.quads: .heavy, .glutes: .moderate, .calves: .moderate, .hamstrings: .light]),
                ActivityPreset(name: "Spin Class", icon: "figure.indoor.cycle",
                               muscles: [.quads: .heavy, .glutes: .moderate, .calves: .moderate, .hamstrings: .light, .abs: .light]),
                ActivityPreset(name: "Swimming", icon: "figure.pool.swim",
                               muscles: [.shoulders: .heavy, .lats: .heavy, .chest: .moderate, .triceps: .moderate, .abs: .moderate, .quads: .light]),
                ActivityPreset(name: "Rowing", icon: "figure.rower",
                               muscles: [.lats: .heavy, .quads: .moderate, .hamstrings: .moderate, .glutes: .moderate, .biceps: .moderate, .lowerBack: .moderate, .forearms: .light, .abs: .light]),
                ActivityPreset(name: "HIIT", icon: "figure.highintensity.intervaltraining",
                               muscles: [.quads: .moderate, .glutes: .moderate, .calves: .moderate, .shoulders: .moderate, .abs: .moderate, .chest: .light]),
                ActivityPreset(name: "Elliptical", icon: "figure.elliptical",
                               muscles: [.quads: .moderate, .hamstrings: .moderate, .glutes: .moderate, .calves: .light]),
                ActivityPreset(name: "Stair Climber", icon: "figure.stairs",
                               muscles: [.glutes: .heavy, .quads: .moderate, .calves: .moderate, .hamstrings: .light]),
                ActivityPreset(name: "Jump Rope", icon: "figure.jumprope",
                               muscles: [.calves: .heavy, .shoulders: .moderate, .forearms: .light, .quads: .light, .abs: .light]),
                ActivityPreset(name: "Hiking", icon: "figure.hiking",
                               muscles: [.quads: .moderate, .glutes: .moderate, .calves: .moderate, .hamstrings: .light]),
                ActivityPreset(name: "Dance", icon: "figure.dance",
                               muscles: [.quads: .moderate, .calves: .moderate, .glutes: .moderate, .abs: .light])
            ]

        case .climbing:
            return [
                ActivityPreset(name: "Bouldering", icon: "figure.climbing",
                               muscles: [.forearms: .heavy, .lats: .heavy, .biceps: .moderate, .shoulders: .moderate, .abs: .moderate, .traps: .light, .quads: .light]),
                ActivityPreset(name: "Top Rope", icon: "figure.climbing",
                               muscles: [.forearms: .moderate, .lats: .moderate, .biceps: .moderate, .shoulders: .moderate, .quads: .moderate, .calves: .light]),
                ActivityPreset(name: "Lead Climbing", icon: "figure.climbing",
                               muscles: [.forearms: .heavy, .lats: .heavy, .biceps: .heavy, .shoulders: .moderate, .abs: .moderate]),
                ActivityPreset(name: "Hangboard", icon: "hand.raised.fill",
                               muscles: [.forearms: .heavy, .lats: .moderate, .biceps: .light, .shoulders: .light]),
                ActivityPreset(name: "Outdoor Climb", icon: "mountain.2.fill",
                               muscles: [.forearms: .heavy, .lats: .heavy, .biceps: .moderate, .shoulders: .moderate, .quads: .moderate, .calves: .light])
            ]

        case .sport:
            return [
                ActivityPreset(name: "Basketball", icon: "basketball.fill",
                               muscles: [.quads: .moderate, .calves: .moderate, .glutes: .moderate, .shoulders: .light]),
                ActivityPreset(name: "Soccer", icon: "soccerball",
                               muscles: [.quads: .heavy, .hamstrings: .moderate, .calves: .moderate, .glutes: .moderate, .abs: .light]),
                ActivityPreset(name: "Tennis", icon: "tennis.racket",
                               muscles: [.shoulders: .moderate, .forearms: .moderate, .obliques: .moderate, .quads: .moderate, .calves: .light]),
                ActivityPreset(name: "Table Tennis", icon: "figure.table.tennis",
                               muscles: [.forearms: .moderate, .shoulders: .light, .quads: .light, .calves: .light, .obliques: .light]),
                ActivityPreset(name: "Pickleball", icon: "figure.pickleball",
                               muscles: [.shoulders: .moderate, .forearms: .moderate, .quads: .moderate, .calves: .moderate, .glutes: .light, .obliques: .light]),
                ActivityPreset(name: "Badminton", icon: "figure.badminton",
                               muscles: [.shoulders: .moderate, .forearms: .moderate, .quads: .moderate, .calves: .moderate]),
                ActivityPreset(name: "Squash", icon: "figure.squash",
                               muscles: [.quads: .heavy, .glutes: .moderate, .calves: .moderate, .shoulders: .moderate, .forearms: .moderate, .abs: .light]),
                ActivityPreset(name: "Racquetball", icon: "figure.racquetball",
                               muscles: [.quads: .moderate, .glutes: .moderate, .shoulders: .moderate, .forearms: .moderate, .calves: .moderate]),
                ActivityPreset(name: "Volleyball", icon: "volleyball.fill",
                               muscles: [.shoulders: .moderate, .quads: .moderate, .calves: .moderate, .abs: .light]),
                ActivityPreset(name: "Golf", icon: "figure.golf",
                               muscles: [.obliques: .moderate, .shoulders: .light, .forearms: .light, .glutes: .light, .lowerBack: .light]),
                ActivityPreset(name: "Baseball / Softball", icon: "figure.baseball",
                               muscles: [.shoulders: .moderate, .obliques: .moderate, .forearms: .moderate, .quads: .light, .glutes: .light]),
                ActivityPreset(name: "Football", icon: "football.fill",
                               muscles: [.quads: .moderate, .glutes: .moderate, .hamstrings: .moderate, .calves: .moderate, .shoulders: .light, .chest: .light]),
                ActivityPreset(name: "Rugby", icon: "figure.rugby",
                               muscles: [.quads: .heavy, .hamstrings: .moderate, .glutes: .moderate, .shoulders: .moderate, .traps: .light, .lats: .light, .abs: .light]),
                ActivityPreset(name: "Hockey", icon: "figure.hockey",
                               muscles: [.quads: .heavy, .glutes: .moderate, .hamstrings: .moderate, .abs: .moderate, .forearms: .light, .shoulders: .light]),
                ActivityPreset(name: "Lacrosse", icon: "figure.lacrosse",
                               muscles: [.quads: .moderate, .hamstrings: .moderate, .forearms: .moderate, .shoulders: .moderate, .abs: .light]),
                ActivityPreset(name: "Cricket", icon: "figure.cricket",
                               muscles: [.shoulders: .moderate, .forearms: .light, .quads: .light, .obliques: .light]),
                ActivityPreset(name: "Handball", icon: "figure.handball",
                               muscles: [.shoulders: .moderate, .quads: .moderate, .calves: .light, .abs: .light]),
                ActivityPreset(name: "Ultimate Frisbee", icon: "figure.disc.sports",
                               muscles: [.quads: .moderate, .hamstrings: .moderate, .calves: .moderate, .shoulders: .light]),
                ActivityPreset(name: "Skateboarding", icon: "figure.skateboarding",
                               muscles: [.quads: .moderate, .calves: .moderate, .glutes: .moderate, .abs: .light]),
                ActivityPreset(name: "Surfing", icon: "figure.surfing",
                               muscles: [.shoulders: .heavy, .lats: .moderate, .triceps: .moderate, .abs: .moderate, .quads: .light]),
                ActivityPreset(name: "Skiing / Snowboarding", icon: "figure.skiing.downhill",
                               muscles: [.quads: .heavy, .glutes: .moderate, .abs: .moderate, .calves: .light, .hamstrings: .light]),
                ActivityPreset(name: "Kayaking", icon: "figure.kayaking",
                               muscles: [.lats: .moderate, .shoulders: .moderate, .forearms: .moderate, .abs: .moderate, .triceps: .light, .biceps: .light]),
                ActivityPreset(name: "Water Polo", icon: "figure.waterpolo",
                               muscles: [.shoulders: .heavy, .lats: .moderate, .quads: .moderate, .abs: .moderate]),
                ActivityPreset(name: "Boxing", icon: "figure.boxing",
                               muscles: [.shoulders: .heavy, .chest: .moderate, .triceps: .moderate, .abs: .moderate, .obliques: .moderate, .forearms: .moderate, .calves: .light]),
                ActivityPreset(name: "Martial Arts", icon: "figure.martial.arts",
                               muscles: [.quads: .moderate, .hamstrings: .moderate, .abs: .moderate, .obliques: .moderate, .shoulders: .light, .glutes: .light]),
                ActivityPreset(name: "Wrestling", icon: "figure.wrestling",
                               muscles: [.shoulders: .moderate, .lats: .moderate, .traps: .moderate, .abs: .moderate, .quads: .moderate, .forearms: .moderate, .lowerBack: .light]),
                ActivityPreset(name: "Jiu-Jitsu", icon: "figure.martial.arts",
                               muscles: [.forearms: .moderate, .lats: .moderate, .abs: .moderate, .quads: .light, .biceps: .light, .shoulders: .light]),
                ActivityPreset(name: "Fencing", icon: "figure.fencing",
                               muscles: [.quads: .moderate, .forearms: .moderate, .calves: .moderate, .shoulders: .light, .glutes: .light]),
                ActivityPreset(name: "Gymnastics", icon: "figure.gymnastics",
                               muscles: [.shoulders: .heavy, .abs: .heavy, .forearms: .moderate, .lats: .moderate, .triceps: .moderate, .chest: .moderate, .quads: .light])
            ]

        case .mobility:
            return [
                ActivityPreset(name: "Yoga", icon: "figure.yoga",
                               muscles: [.shoulders: .light, .abs: .light, .hamstrings: .light, .quads: .light, .glutes: .light, .lowerBack: .light]),
                ActivityPreset(name: "Stretching", icon: "figure.flexibility",
                               muscles: [.hamstrings: .light, .quads: .light, .glutes: .light, .lowerBack: .light]),
                ActivityPreset(name: "Pilates", icon: "figure.pilates",
                               muscles: [.abs: .moderate, .obliques: .light, .glutes: .light, .lowerBack: .light, .quads: .light]),
                ActivityPreset(name: "Foam Rolling", icon: "figure.cooldown",
                               muscles: [.quads: .light, .calves: .light, .lats: .light, .glutes: .light]),
                ActivityPreset(name: "Mobility Drills", icon: "figure.mind.and.body",
                               muscles: [.shoulders: .light, .glutes: .light, .lowerBack: .light, .hamstrings: .light])
            ]
        }
    }
}


// MARK: - Session types and positions

/// How a session was played: practice, a game, an easy run, a tempo run... A multiplier on the
/// activity's usual muscle effort.
struct ActivityMode: Hashable, Identifiable {
    var name: String
    var multiplier: Double
    /// Selected when the activity is first chosen.
    var isDefault = false

    var id: String { name }
}

/// A position (handler, cutter, goalkeeper...) or style (a swimming stroke). Adds to or takes from
/// the activity's usual intensity for particular muscles.
struct ActivityRole: Hashable, Identifiable {
    var name: String
    var adjustments: [MuscleGroup: Double]

    var id: String { name }
}

enum ActivityVariants {
    private static let teamOrRacquet: [ActivityMode] = [
        ActivityMode(name: "Practice", multiplier: 0.75),
        ActivityMode(name: "Pickup", multiplier: 0.9),
        ActivityMode(name: "Game", multiplier: 1.0, isDefault: true),
        ActivityMode(name: "Tournament", multiplier: 1.15)
    ]

    private static let endurance: [ActivityMode] = [
        ActivityMode(name: "Easy", multiplier: 0.6),
        ActivityMode(name: "Long", multiplier: 0.85),
        ActivityMode(name: "Tempo", multiplier: 1.0, isDefault: true),
        ActivityMode(name: "Intervals", multiplier: 1.2),
        ActivityMode(name: "Race", multiplier: 1.25)
    ]

    private static let walking: [ActivityMode] = [
        ActivityMode(name: "Easy", multiplier: 0.7),
        ActivityMode(name: "Brisk", multiplier: 1.0, isDefault: true),
        ActivityMode(name: "Hard", multiplier: 1.2)
    ]

    private static let combat: [ActivityMode] = [
        ActivityMode(name: "Drills", multiplier: 0.7),
        ActivityMode(name: "Sparring", multiplier: 1.0, isDefault: true),
        ActivityMode(name: "Competition", multiplier: 1.2)
    ]

    private static let individual: [ActivityMode] = [
        ActivityMode(name: "Casual", multiplier: 0.75),
        ActivityMode(name: "Session", multiplier: 1.0, isDefault: true),
        ActivityMode(name: "Competition", multiplier: 1.15)
    ]

    private static let climbing: [ActivityMode] = [
        ActivityMode(name: "Warm-up", multiplier: 0.5),
        ActivityMode(name: "Volume", multiplier: 0.9),
        ActivityMode(name: "Training", multiplier: 1.0, isDefault: true),
        ActivityMode(name: "Project", multiplier: 1.2)
    ]

    static func modes(for preset: ActivityPreset, category: WorkoutCategory) -> [ActivityMode] {
        switch category {
        case .strength, .mobility:
            return []
        case .cardio:
            return ["Walking", "Hiking"].contains(preset.name) ? walking : endurance
        case .climbing:
            return climbing
        case .sport:
            switch preset.name {
            case "Boxing", "Martial Arts", "Wrestling", "Jiu-Jitsu", "Fencing":
                return combat
            case "Golf", "Surfing", "Skateboarding", "Skiing / Snowboarding", "Kayaking", "Gymnastics":
                return individual
            default:
                return teamOrRacquet
            }
        }
    }

    private static func role(_ name: String, _ adjustments: [MuscleGroup: Double]) -> ActivityRole {
        ActivityRole(name: name, adjustments: adjustments)
    }

    /// The positions (or styles) that change which muscles work hardest, with the label to show.
    static func roles(for activity: String) -> (label: String, roles: [ActivityRole])? {
        switch activity {
        case "Ultimate Frisbee":
            return ("Position", [
                role("Handler", [.shoulders: 0.2, .forearms: 0.25, .abs: 0.1, .quads: -0.1, .calves: -0.1]),
                role("Cutter", [.quads: 0.25, .hamstrings: 0.25, .calves: 0.25, .glutes: 0.2, .shoulders: -0.1]),
                role("Hybrid", [.quads: 0.1, .hamstrings: 0.1, .forearms: 0.1])
            ])
        case "Soccer":
            return ("Position", [
                role("Goalkeeper", [.shoulders: 0.3, .forearms: 0.3, .quads: -0.3, .hamstrings: -0.3, .calves: -0.3, .glutes: -0.2]),
                role("Defender", [.calves: 0.1, .shoulders: 0.1]),
                role("Midfielder", [.calves: 0.2, .quads: 0.1, .glutes: 0.1]),
                role("Striker", [.hamstrings: 0.2, .glutes: 0.2, .quads: 0.1])
            ])
        case "Basketball":
            return ("Position", [
                role("Guard", [.calves: 0.15, .quads: 0.1, .forearms: 0.1]),
                role("Forward", [.shoulders: 0.15, .glutes: 0.1, .triceps: 0.1]),
                role("Center", [.shoulders: 0.25, .chest: 0.25, .triceps: 0.2, .calves: -0.1])
            ])
        case "Volleyball":
            return ("Position", [
                role("Setter", [.shoulders: 0.15, .forearms: 0.3, .triceps: 0.1]),
                role("Hitter", [.shoulders: 0.3, .quads: 0.2, .calves: 0.2, .abs: 0.15]),
                role("Libero", [.quads: 0.25, .glutes: 0.15, .hamstrings: 0.15, .shoulders: -0.1])
            ])
        case "Hockey":
            return ("Position", [
                role("Forward", [.quads: 0.1, .glutes: 0.1]),
                role("Defense", [.shoulders: 0.1, .abs: 0.1]),
                role("Goalie", [.quads: 0.2, .hamstrings: 0.3, .glutes: 0.2, .forearms: 0.2, .shoulders: -0.1])
            ])
        case "Rugby":
            return ("Position", [
                role("Forward", [.chest: 0.2, .shoulders: 0.2, .traps: 0.2, .lats: 0.1, .quads: 0.1]),
                role("Back", [.hamstrings: 0.2, .calves: 0.2, .glutes: 0.15])
            ])
        case "Football":
            return ("Position", [
                role("Quarterback", [.shoulders: 0.3, .forearms: 0.2, .obliques: 0.2, .quads: -0.2, .hamstrings: -0.2]),
                role("Lineman", [.chest: 0.3, .triceps: 0.3, .shoulders: 0.2, .glutes: 0.2, .quads: 0.2]),
                role("Receiver / Back", [.hamstrings: 0.3, .calves: 0.2, .glutes: 0.2]),
                role("Linebacker", [.quads: 0.2, .shoulders: 0.2, .abs: 0.1])
            ])
        case "Baseball / Softball":
            return ("Position", [
                role("Pitcher", [.shoulders: 0.3, .obliques: 0.2, .forearms: 0.2, .quads: 0.1, .hamstrings: 0.1]),
                role("Catcher", [.quads: 0.3, .glutes: 0.2, .calves: 0.1, .forearms: 0.1]),
                role("Infield", [.quads: 0.1, .hamstrings: 0.1, .calves: 0.1]),
                role("Outfield", [.hamstrings: 0.2, .calves: 0.2, .quads: 0.1])
            ])
        case "Cricket":
            return ("Role", [
                role("Batter", [.forearms: 0.2, .obliques: 0.2]),
                role("Bowler", [.shoulders: 0.3, .obliques: 0.2, .quads: 0.2, .forearms: 0.1]),
                role("Fielder", [.hamstrings: 0.15, .calves: 0.15])
            ])
        case "Tennis", "Pickleball", "Badminton", "Table Tennis", "Squash":
            return ("Format", [
                role("Singles", [.quads: 0.15, .calves: 0.15, .glutes: 0.1]),
                role("Doubles", [.shoulders: 0.1])
            ])
        case "Swimming":
            return ("Stroke", [
                role("Freestyle", [.lats: 0.05]),
                role("Breaststroke", [.chest: 0.3, .quads: 0.3, .glutes: 0.2, .lats: -0.3, .triceps: -0.2]),
                role("Butterfly", [.shoulders: 0.2, .abs: 0.3, .chest: 0.2, .lats: 0.1]),
                role("Backstroke", [.lats: 0.15, .triceps: 0.1, .glutes: 0.1, .chest: -0.3])
            ])
        default:
            return nil
        }
    }

    /// The muscle intensities (0...1) for an activity played in a given way: the usual muscles,
    /// plus the position's adjustments, all scaled by the session type's effort. Anything that
    /// ends up barely worked is dropped.
    static func intensities(base: [MuscleGroup: HeatLevel], mode: ActivityMode?, role: ActivityRole?) -> [MuscleGroup: Double] {
        var values = base.mapValues { $0.intensity }
        for (muscle, change) in role?.adjustments ?? [:] {
            values[muscle, default: 0] += change
        }
        let multiplier = mode?.multiplier ?? 1
        var result: [MuscleGroup: Double] = [:]
        for (muscle, value) in values {
            let scaled = min(max(value * multiplier, 0), 1)
            if scaled > 0.05 { result[muscle] = scaled }
        }
        return result
    }
}
