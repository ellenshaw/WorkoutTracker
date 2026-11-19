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
    /// The activity tile it was logged under ("Running", "Rowing"...), whatever the workout is named.
    var activity = ""
    /// Cycle phase when this was logged, only if the user tracks their cycle ("menstrual", ...).
    /// Lets progress charts explain a dip. Stays on the device.
    var cyclePhase = ""
    /// Cardio: distance in kilometres (always stored as km, shown in the user's unit).
    var distanceKm: Double?
    /// Exact time in seconds when known (GPS or entered with seconds); `duration` is the rounded minutes.
    var durationSeconds: Int?
    /// GPS route for outdoor sessions, thinned to a few hundred points. Stays on this device.
    var route: [RoutePoint] = []

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
         role: String = "",
         activity: String = "",
         cyclePhase: String = "",
         distanceKm: Double? = nil,
         durationSeconds: Int? = nil,
         route: [RoutePoint] = []) {
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
        self.activity = activity
        self.cyclePhase = cyclePhase
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.route = route
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, duration, notes, date, muscleIntensity, exercises, isPinned, mode, role, activity, cyclePhase, distanceKm, durationSeconds, route
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
        activity = try c.decodeIfPresent(String.self, forKey: .activity) ?? ""
        cyclePhase = try c.decodeIfPresent(String.self, forKey: .cyclePhase) ?? ""
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        route = try c.decodeIfPresent([RoutePoint].self, forKey: .route) ?? []

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
        try c.encode(activity, forKey: .activity)
        try c.encode(cyclePhase, forKey: .cyclePhase)
        try c.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        if !route.isEmpty { try c.encode(route, forKey: .route) }
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

    /// The activity this belongs to, for grouping records: the tile it was logged under, else its name.
    var activityName: String { activity.isEmpty ? name : activity }

    /// "Game · Cutter": the session type and position, when there are any.
    var variantText: String {
        [mode, role].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// One-line description for lists and pinned cards.
    var summary: String {
        if exercises.isEmpty {
            var parts: [String] = []
            if let distanceKm, distanceKm > 0 {
                let unit = DistanceUnit(rawValue: UserDefaults.standard.string(forKey: StorageKey.distanceUnit) ?? "") ?? .km
                parts.append(ActivityMetrics.usesShortDistance(activityName)
                             ? "\(Int(unit.fromKmShort(distanceKm).rounded())) \(unit.shortSymbol)"
                             : "\(unit.format(km: distanceKm)) \(unit.symbol)")
            }
            parts.append("\(duration) min")
            if !variantText.isEmpty { parts.append(variantText) }
            return parts.joined(separator: " · ")
        }
        let count = exercises.count
        return "\(count) exercise\(count == 1 ? "" : "s") · \(totalSets) sets"
    }
}
