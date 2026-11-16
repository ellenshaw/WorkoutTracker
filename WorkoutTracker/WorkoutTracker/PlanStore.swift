//
//  PlanStore.swift
//  WorkoutTracker
//

import Foundation

/// Holds the training plans (suggested, active and past) and saves them as JSON.
@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var plans: [TrainingPlan] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plans.json")
        load()
    }

    var activePlan: TrainingPlan? { plans.first { $0.status == .active } }
    var proposedPlans: [TrainingPlan] { plans.filter { $0.status == .proposed } }
    var pastPlans: [TrainingPlan] { plans.filter { $0.status == .completed || $0.status == .archived } }

    func plan(id: UUID) -> TrainingPlan? {
        plans.first { $0.id == id }
    }

    func plan(containing sessionID: UUID) -> TrainingPlan? {
        plans.first { plan in plan.sessions.contains { $0.id == sessionID } }
    }

    /// Adds a plan the coach just made. It waits in "Suggested" until the user starts it.
    @discardableResult
    func add(_ plan: TrainingPlan) -> TrainingPlan {
        var added = plan
        added.status = .proposed
        plans.insert(added, at: 0)
        save()
        return added
    }

    /// Starts a plan on a date. Only one plan runs at a time, so any other active plan is archived.
    func start(_ planID: UUID, on date: Date) {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return }
        for i in plans.indices where plans[i].status == .active && plans[i].id != planID {
            plans[i].status = .archived
        }
        plans[index].status = .active
        plans[index].startDate = date
        save()
    }

    /// Stops following a plan but keeps its history.
    func stop(_ planID: UUID) {
        update(planID) { $0.status = .archived }
    }

    func delete(_ planID: UUID) {
        plans.removeAll { $0.id == planID }
        save()
    }

    // MARK: Sessions

    /// Marks a session done, optionally linking the workout that was logged for it.
    func complete(sessionID: UUID, workoutID: UUID?, at date: Date = Date()) {
        guard let plan = plan(containing: sessionID) else { return }
        update(plan.id) { plan in
            guard let index = plan.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            plan.sessions[index].completedAt = date
            plan.sessions[index].completedWorkoutID = workoutID
            plan.sessions[index].skipped = false
            if plan.sessions.allSatisfy({ !$0.isPending }) && plan.status == .active {
                plan.status = .completed
            }
        }
    }

    func undoCompletion(sessionID: UUID) {
        guard let plan = plan(containing: sessionID) else { return }
        update(plan.id) { plan in
            guard let index = plan.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            plan.sessions[index].completedAt = nil
            plan.sessions[index].completedWorkoutID = nil
            if plan.status == .completed { plan.status = .active }
        }
    }

    func setSkipped(_ skipped: Bool, sessionID: UUID) {
        guard let plan = plan(containing: sessionID) else { return }
        update(plan.id) { plan in
            guard let index = plan.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            plan.sessions[index].skipped = skipped
            if skipped {
                plan.sessions[index].completedAt = nil
                plan.sessions[index].completedWorkoutID = nil
            }
            if plan.sessions.allSatisfy({ !$0.isPending }) && plan.status == .active {
                plan.status = .completed
            } else if plan.status == .completed && plan.sessions.contains(where: \.isPending) {
                plan.status = .active
            }
        }
    }

    func removeAll() {
        plans = []
        save()
    }

    // MARK: Persistence

    private func update(_ planID: UUID, _ change: (inout TrainingPlan) -> Void) {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return }
        change(&plans[index])
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([TrainingPlan].self, from: data) {
            plans = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(plans) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
