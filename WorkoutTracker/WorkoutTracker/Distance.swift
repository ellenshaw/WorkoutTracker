//
//  Distance.swift
//  WorkoutTracker
//
//  Distance, pace and cardio records: which activities track distance, how pace is shown for each
//  (per km, per 500 m for rowing, per 100 m for swimming, speed for cycling), the cardio personal
//  records, and the plain logic that turns GPS samples into distance.
//

import Foundation

// MARK: - Units

enum DistanceUnit: String, CaseIterable, Identifiable {
    case km, mi

    var id: String { rawValue }
    var symbol: String { rawValue }
    var title: String { self == .km ? "km" : "mi" }

    private static let kmPerMile = 1.609344
    private static let yardsPerKm = 1093.6133

    func fromKm(_ km: Double) -> Double { self == .km ? km : km / DistanceUnit.kmPerMile }
    func toKm(_ value: Double) -> Double { self == .km ? value : value * DistanceUnit.kmPerMile }

    /// Short distances (swimming, rowing) are entered in meters, or yards for imperial.
    var shortSymbol: String { self == .km ? "m" : "yd" }
    func fromKmShort(_ km: Double) -> Double { self == .km ? km * 1000 : km * DistanceUnit.yardsPerKm }
    func toKmShort(_ value: Double) -> Double { self == .km ? value / 1000 : value / DistanceUnit.yardsPerKm }

    /// "5.2" or "10": at most two decimals, no trailing zeros.
    func format(km: Double) -> String {
        let value = (fromKm(km) * 100).rounded() / 100
        return value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

// MARK: - Which activities track what

enum PaceStyle: Equatable {
    case perDistance   // running, walking, hiking: min per km or per mile
    case per500m       // rowing
    case per100        // swimming: per 100 m (or 100 yd)
    case speed         // cycling: km/h or mph
}

enum ActivityMetrics {
    static let distanceActivities: Set<String> = [
        "Running", "Walking", "Hiking", "Cycling", "Swimming", "Rowing", "Kayaking"
    ]
    /// Outdoor activities where a phone's GPS makes sense.
    static let gpsActivities: Set<String> = [
        "Running", "Walking", "Hiking", "Cycling", "Rowing", "Kayaking"
    ]

    static func tracksDistance(_ activity: String) -> Bool { distanceActivities.contains(activity) }
    static func supportsGPS(_ activity: String) -> Bool { gpsActivities.contains(activity) }

    /// Entered in meters/yards rather than kilometers/miles.
    static func usesShortDistance(_ activity: String) -> Bool { ["Swimming", "Rowing"].contains(activity) }

    static func paceStyle(for activity: String) -> PaceStyle {
        switch activity {
        case "Rowing", "Kayaking": return .per500m
        case "Swimming": return .per100
        case "Cycling": return .speed
        default: return .perDistance
        }
    }

    /// Below this distance a pace isn't meaningful enough to count as a record.
    static func minimumRecordDistanceKm(for activity: String) -> Double {
        switch activity {
        case "Swimming": return 0.1
        case "Rowing", "Kayaking": return 0.5
        case "Cycling": return 5
        default: return 1
        }
    }
}

// MARK: - Pace

enum PaceFormat {
    /// "5:12" or "1:02:30".
    static func clock(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// The common yardstick for comparing any activity: seconds per kilometre. Lower is faster.
    static func secondsPerKm(distanceKm: Double, seconds: Double) -> Double {
        distanceKm > 0 ? seconds / distanceKm : 0
    }

    /// "5:12 /km", "8:23 /mi", "1:58 /500m", "1:45 /100m", "24.5 km/h".
    static func format(secondsPerKm: Double, style: PaceStyle, unit: DistanceUnit) -> String {
        guard secondsPerKm > 0 else { return "–" }
        switch style {
        case .perDistance:
            let perUnit = unit == .km ? secondsPerKm : secondsPerKm * 1.609344
            return "\(clock(perUnit)) /\(unit.symbol)"
        case .per500m:
            return "\(clock(secondsPerKm / 2)) /500m"
        case .per100:
            if unit == .km { return "\(clock(secondsPerKm / 10)) /100m" }
            return "\(clock(secondsPerKm / 1093.6133 * 100 * 1)) /100yd"
        case .speed:
            let perHour = 3600 / secondsPerKm
            let value = unit == .km ? perHour : perHour / 1.609344
            return String(format: "%.1f %@", value, unit == .km ? "km/h" : "mph")
        }
    }
}

extension Workout {
    /// Time in seconds: exact when it was timed (GPS or entered with seconds), else the minutes.
    var elapsedSeconds: Int { durationSeconds ?? duration * 60 }

    /// Seconds per kilometre, for comparing workouts. Nil when no distance was logged.
    var paceSecondsPerKm: Double? {
        guard let distanceKm, distanceKm > 0, elapsedSeconds > 0 else { return nil }
        return Double(elapsedSeconds) / distanceKm
    }
}

// MARK: - Cardio records

struct CardioRecord: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case bestPace, longestDistance, longestTime
        case fastest5K, fastest10K, fastestHalf, fastestMarathon

        var title: String {
            switch self {
            case .bestPace: return "Best pace"
            case .longestDistance: return "Longest distance"
            case .longestTime: return "Longest time"
            case .fastest5K: return "Fastest 5K"
            case .fastest10K: return "Fastest 10K"
            case .fastestHalf: return "Fastest half marathon"
            case .fastestMarathon: return "Fastest marathon"
            }
        }
    }

    let activity: String
    let kind: Kind
    /// Seconds per km (pace), kilometres (distance) or seconds (time; also for the standard distances).
    let value: Double
    let workoutID: UUID
    let date: Date
    /// True when a slightly longer run was scaled down to the standard distance.
    let estimated: Bool

    var id: String { "\(activity)-\(kind.rawValue)" }
}

enum CardioRecords {
    static let standardDistances: [(kind: CardioRecord.Kind, km: Double)] = [
        (.fastest5K, 5), (.fastest10K, 10), (.fastestHalf, 21.0975), (.fastestMarathon, 42.195)
    ]

    /// Pace values outside this range are almost certainly typos or bad GPS, so they never count.
    private static let plausiblePace: ClosedRange<Double> = 60...2400

    private static func qualifies(_ workout: Workout) -> Bool {
        guard let distance = workout.distanceKm, distance >= ActivityMetrics.minimumRecordDistanceKm(for: workout.activityName),
              let pace = workout.paceSecondsPerKm else { return false }
        return plausiblePace.contains(pace)
    }

    static func compute(workouts: [Workout]) -> [CardioRecord] {
        var grouped: [String: [Workout]] = [:]
        for workout in workouts where ActivityMetrics.tracksDistance(workout.activityName) && (workout.distanceKm ?? 0) > 0 {
            grouped[workout.activityName, default: []].append(workout)
        }

        var records: [CardioRecord] = []
        for (activity, items) in grouped {
            let valid = items.filter(qualifies)
            if let best = valid.min(by: { ($0.paceSecondsPerKm ?? .infinity) < ($1.paceSecondsPerKm ?? .infinity) }),
               let pace = best.paceSecondsPerKm {
                records.append(CardioRecord(activity: activity, kind: .bestPace, value: pace,
                                            workoutID: best.id, date: best.date, estimated: false))
            }
            if let farthest = items.max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }), let distance = farthest.distanceKm {
                records.append(CardioRecord(activity: activity, kind: .longestDistance, value: distance,
                                            workoutID: farthest.id, date: farthest.date, estimated: false))
            }
            if let longest = items.max(by: { $0.elapsedSeconds < $1.elapsedSeconds }) {
                records.append(CardioRecord(activity: activity, kind: .longestTime, value: Double(longest.elapsedSeconds),
                                            workoutID: longest.id, date: longest.date, estimated: false))
            }

            if activity == "Running" {
                for (kind, target) in standardDistances {
                    // A run of 5.0–5.5 km counts toward the 5K, with the time scaled to exactly 5 km.
                    let candidates = valid.compactMap { workout -> (Workout, Double)? in
                        guard let distance = workout.distanceKm, distance >= target * 0.995, distance <= target * 1.1 else { return nil }
                        return (workout, Double(workout.elapsedSeconds) * target / distance)
                    }
                    if let best = candidates.min(by: { $0.1 < $1.1 }) {
                        let exact = (best.0.distanceKm ?? target) <= target * 1.01
                        records.append(CardioRecord(activity: activity, kind: kind, value: best.1,
                                                    workoutID: best.0.id, date: best.0.date, estimated: !exact))
                    }
                }
            }
        }
        return records.sorted { ($0.activity, $0.kind.rawValue) < ($1.activity, $1.kind.rawValue) }
    }

    /// What this workout set, compared with everything else logged: "Best pace", "Longest distance"...
    static func badges(for workout: Workout, among workouts: [Workout]) -> [CardioRecord.Kind] {
        guard ActivityMetrics.tracksDistance(workout.activityName), let distance = workout.distanceKm, distance > 0 else { return [] }
        let others = workouts.filter { $0.id != workout.id && $0.activityName == workout.activityName && ($0.distanceKm ?? 0) > 0 }
        guard !others.isEmpty else { return [] }

        var kinds: [CardioRecord.Kind] = []
        if qualifies(workout), let pace = workout.paceSecondsPerKm {
            let best = others.filter(qualifies).compactMap(\.paceSecondsPerKm).min() ?? .infinity
            if pace < best - 0.5 { kinds.append(.bestPace) }
        }
        if distance > (others.compactMap(\.distanceKm).max() ?? 0) + 0.005 { kinds.append(.longestDistance) }
        return kinds
    }
}

// MARK: - GPS

struct GPSSample: Equatable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    /// Meters; negative means the reading is invalid.
    var horizontalAccuracy: Double
}

struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
}

/// Turns a stream of GPS readings into distance, ignoring poor or impossible ones.
struct OutdoorSession {
    private(set) var distanceMeters: Double = 0
    private(set) var points: [GPSSample] = []
    private var lastAccepted: GPSSample?

    /// Readings less accurate than this, or that jump faster than a person or bike can travel, are ignored.
    static let maxAccuracyMeters = 30.0
    static let maxSpeedMetersPerSecond = 25.0
    /// Movement smaller than this is just GPS wobble while standing still.
    static let minStepMeters = 3.0

    var distanceKm: Double { distanceMeters / 1000 }

    mutating func add(_ sample: GPSSample) {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= OutdoorSession.maxAccuracyMeters else { return }

        guard let last = lastAccepted else {
            lastAccepted = sample
            points.append(sample)
            return
        }
        let seconds = sample.timestamp.timeIntervalSince(last.timestamp)
        guard seconds > 0 else { return }
        let step = OutdoorSession.distance(from: last, to: sample)
        guard step >= OutdoorSession.minStepMeters, step / seconds <= OutdoorSession.maxSpeedMetersPerSecond else { return }

        distanceMeters += step
        lastAccepted = sample
        points.append(sample)
    }

    /// After a pause the person may have moved, so the next reading starts a fresh segment instead
    /// of counting the gap as distance.
    mutating func startNewSegment() {
        lastAccepted = nil
    }

    /// Great-circle distance in meters.
    static func distance(from a: GPSSample, to b: GPSSample) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, h.squareRoot()))
    }

    /// The route for saving and drawing, thinned to at most `maxPoints` so a long run stays small.
    func route(maxPoints: Int = 300) -> [RoutePoint] {
        guard points.count > maxPoints, maxPoints > 1 else {
            return points.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) }
        }
        let step = Double(points.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { index in
            let sample = points[Int((Double(index) * step).rounded())]
            return RoutePoint(latitude: sample.latitude, longitude: sample.longitude)
        }
    }

    /// A guess at what the person was doing from their average speed, so a run that was really a
    /// ride can be corrected.
    static func suggestedActivity(averageKmh: Double) -> String? {
        switch averageKmh {
        case ..<1: return nil
        case ..<6.5: return "Walking"
        case ..<17: return "Running"
        case ..<60: return "Cycling"
        default: return nil
        }
    }
}
