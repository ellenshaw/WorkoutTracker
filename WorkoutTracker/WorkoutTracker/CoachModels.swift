//
//  CoachModels.swift
//  WorkoutTracker
//
//  Training plans made by the AI coach: the plan, its sessions, how they map onto calendar days,
//  progress, and how a planned session becomes a pre-filled workout to log.
//

import Foundation

enum PlanStatus: String, Codable {
    case proposed   // suggested by the coach, not started
    case active
    case completed
    case archived   // stopped or replaced
}

struct PlannedExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var sets: Int
    /// "5", "8-10", "AMRAP", "45s"...
    var reps: String
    var percentOfOneRepMax: Double?
    var weightKg: Double?
    var muscles: [MuscleGroup] = []
    var notes: String = ""
}

struct PlanSession: Codable, Hashable, Identifiable {
    var id = UUID()
    /// 1-based week of the plan.
    var week: Int
    /// 1 = Monday … 7 = Sunday.
    var day: Int
    var title: String
    var category: WorkoutCategory
    var activity: String = ""
    var durationMinutes: Int
    var notes: String = ""
    var exercises: [PlannedExercise] = []
    var targetDistanceKm: Double?
    var intensity: String?

    var completedAt: Date?
    var completedWorkoutID: UUID?
    var skipped = false

    var isDone: Bool { completedAt != nil }
    var isPending: Bool { !isDone && !skipped }
}

enum PlanSessionState: Equatable {
    case completed, skipped, today, upcoming, missed
    /// The plan hasn't been started, so sessions have no dates yet.
    case unscheduled
}

struct TrainingPlan: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var goal: String
    var summary: String
    var weeks: Int
    var sessions: [PlanSession]
    var status: PlanStatus = .proposed
    var createdAt = Date()
    var startDate: Date?
}

// MARK: - Calendar

extension TrainingPlan {
    /// Monday = 1 … Sunday = 7.
    static func mondayBasedWeekday(of date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    /// The calendar day a session is planned for. Week 1 begins on the start date, and each
    /// session lands on its weekday within its 7-day block, so a plan started on a Wednesday
    /// puts "Monday" sessions on the following Monday.
    func scheduledDate(for session: PlanSession, calendar: Calendar = .current) -> Date? {
        guard let startDate else { return nil }
        let start = calendar.startOfDay(for: startDate)
        let startWeekday = TrainingPlan.mondayBasedWeekday(of: start, calendar: calendar)
        let withinBlock = (session.day - startWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: (session.week - 1) * 7 + withinBlock, to: start)
    }

    func state(of session: PlanSession, now: Date = Date(), calendar: Calendar = .current) -> PlanSessionState {
        if session.isDone { return .completed }
        if session.skipped { return .skipped }
        guard let date = scheduledDate(for: session, calendar: calendar) else { return .unscheduled }
        let today = calendar.startOfDay(for: now)
        if date == today { return .today }
        return date < today ? .missed : .upcoming
    }

    /// The last day of the plan.
    func endDate(calendar: Calendar = .current) -> Date? {
        guard let startDate else { return nil }
        return calendar.date(byAdding: .day, value: weeks * 7 - 1, to: calendar.startOfDay(for: startDate))
    }

    /// Which week of the plan today falls in (nil before it starts, capped at the last week).
    func currentWeek(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let startDate else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 0 { return nil }
        return min(days / 7 + 1, weeks)
    }

    var totalSessions: Int { sessions.count }
    var completedSessions: Int { sessions.filter(\.isDone).count }
    var skippedSessions: Int { sessions.filter(\.skipped).count }

    /// 0…1, counting only sessions actually done.
    var progress: Double {
        totalSessions == 0 ? 0 : Double(completedSessions) / Double(totalSessions)
    }

    var averageMinutes: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.durationMinutes } / sessions.count
    }

    func sessions(inWeek week: Int) -> [PlanSession] {
        sessions.filter { $0.week == week }.sorted { $0.day < $1.day }
    }

    /// The session to do next: the earliest pending one that isn't in the past, otherwise the
    /// earliest one that was missed.
    func nextSession(now: Date = Date(), calendar: Calendar = .current) -> PlanSession? {
        let pending = sessions.filter(\.isPending).sorted { ($0.week, $0.day) < ($1.week, $1.day) }
        guard startDate != nil else { return pending.first }
        let today = calendar.startOfDay(for: now)
        return pending.first { (scheduledDate(for: $0, calendar: calendar) ?? .distantFuture) >= today } ?? pending.first
    }
}

// MARK: - From the server

/// A plan exactly as the backend sends it. The backend has already validated and clamped it.
struct PlanDraft: Decodable {
    struct Exercise: Decodable {
        var name: String
        var sets: Int
        var reps: String
        var percentOfOneRepMax: Double?
        var weightKg: Double?
        var muscles: [String]?
        var notes: String?
    }

    struct Session: Decodable {
        var week: Int
        var day: Int
        var title: String
        var type: String
        var activity: String?
        var durationMinutes: Int
        var notes: String?
        var exercises: [Exercise]?
        var targetDistanceKm: Double?
        var intensity: String?
    }

    var title: String
    var goal: String
    var summary: String
    var weeks: Int
    var sessions: [Session]

    func makePlan() -> TrainingPlan {
        let converted = sessions.map { session -> PlanSession in
            let category = WorkoutCategory.allCases.first { $0.rawValue.lowercased() == session.type.lowercased() } ?? .strength
            let exercises = (session.exercises ?? []).map { e in
                PlannedExercise(name: e.name, sets: max(e.sets, 1), reps: e.reps,
                                percentOfOneRepMax: e.percentOfOneRepMax, weightKg: e.weightKg,
                                muscles: (e.muscles ?? []).compactMap { MuscleGroup(rawValue: $0) },
                                notes: e.notes ?? "")
            }
            return PlanSession(week: session.week, day: session.day, title: session.title,
                               category: category, activity: session.activity ?? "",
                               durationMinutes: session.durationMinutes, notes: session.notes ?? "",
                               exercises: exercises, targetDistanceKm: session.targetDistanceKm,
                               intensity: session.intensity)
        }
        return TrainingPlan(title: title, goal: goal, summary: summary, weeks: max(weeks, 1),
                            sessions: converted.sorted { ($0.week, $0.day) < ($1.week, $1.day) })
    }
}

// MARK: - Planned session → workout to log

enum PlanTemplates {
    private static func words(_ text: String) -> Set<String> {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return Set(String(cleaned).split(separator: " ").map(String.init))
    }

    /// Finds the directory exercise a planned name refers to. Exact matches win, then the closest
    /// by shared words; otherwise a stand-alone exercise built from the plan's own muscle list.
    static func resolveExercise(_ planned: PlannedExercise, in exercises: [Exercise]) -> Exercise {
        let target = words(planned.name)
        if let exact = exercises.first(where: { words($0.name) == target }) { return exact }

        var best: (exercise: Exercise, score: Double)?
        for candidate in exercises {
            let w = words(candidate.name)
            let union = w.union(target).count
            guard union > 0 else { continue }
            let score = Double(w.intersection(target).count) / Double(union)
            if score > (best?.score ?? 0) { best = (candidate, score) }
        }
        if let best, best.score >= 0.6 { return best.exercise }

        return Exercise(id: "plan-" + Exercise.slug(planned.name), name: planned.name,
                        primary: planned.muscles, secondary: [])
    }

    /// The first whole number in a rep string ("8-10" → 8, "AMRAP" → 0).
    static func firstNumber(in text: String) -> Int {
        var digits = ""
        for character in text {
            if character.isNumber { digits.append(character) } else if !digits.isEmpty { break }
        }
        return Int(digits) ?? 0
    }

    /// Working weight for the first set: an explicit weight, or a percentage of the user's
    /// estimated one-rep max rounded to 2.5 kg. Zero when unknown.
    static func targetWeightKg(for planned: PlannedExercise, record: PersonalRecord?) -> Double {
        if let weight = planned.weightKg, weight > 0 { return weight }
        if let percent = planned.percentOfOneRepMax, let record {
            return (record.estimatedOneRepMaxKg * percent / 100 / 2.5).rounded() * 2.5
        }
        return 0
    }

    /// A workout pre-filled from a planned session, ready to open in the logger.
    static func template(for session: PlanSession,
                         exercises library: [Exercise],
                         record: (String) -> PersonalRecord?) -> Workout {
        if session.category == .strength {
            let logged = session.exercises.map { planned -> LoggedExercise in
                let exercise = resolveExercise(planned, in: library)
                let weight = targetWeightKg(for: planned, record: record(exercise.id))
                let reps = firstNumber(in: planned.reps)
                let sets = (0..<max(planned.sets, 1)).map { _ in LoggedSet(weightKg: weight, reps: reps) }
                return LoggedExercise(exerciseID: exercise.id, name: exercise.name,
                                      primary: exercise.primary, secondary: exercise.secondary, sets: sets)
            }
            return Workout(name: session.title, category: .strength, duration: session.durationMinutes,
                           notes: session.notes, date: Date(), exercises: logged)
        }

        let wanted = words(session.activity.isEmpty ? session.title : session.activity)
        let preset = session.category.activities.first { words($0.name).isSubset(of: wanted) || wanted.isSubset(of: words($0.name)) }

        var notes = [session.notes]
        if let distance = session.targetDistanceKm, distance > 0 {
            notes.append("Target: \(distance.formatted(.number.precision(.fractionLength(0...1)))) km")
        }
        if let intensity = session.intensity { notes.append("Effort: \(intensity)") }

        var workout = Workout(name: preset?.name ?? (session.activity.isEmpty ? session.title : session.activity),
                              category: session.category, duration: session.durationMinutes,
                              notes: notes.filter { !$0.isEmpty }.joined(separator: " · "), date: Date())
        if let preset {
            let factor = HeatCalculator.durationFactor(minutes: session.durationMinutes)
            workout.heat = preset.muscles.mapValues { min($0.intensity * factor, 1) }
        }
        return workout
    }
}

/// One line describing a planned exercise: "Bench Press (Barbell) · 5 × 5 @ 80 kg".
extension PlannedExercise {
    func summary(record: PersonalRecord?, unit: WeightUnit) -> String {
        var text = "\(name) · \(sets) × \(reps)"
        let weight = PlanTemplates.targetWeightKg(for: self, record: record)
        if weight > 0 {
            text += " @ \(unit.format(kg: weight)) \(unit.symbol)"
        } else if let percent = percentOfOneRepMax {
            text += " @ \(Int(percent))% of max"
        }
        return text
    }
}
