//
//  PlansView.swift
//  WorkoutTracker
//
//  The Plans tab: plans the coach suggested, the one you're following with its progress, and
//  the sessions inside each plan.
//

import SwiftUI

/// Builds the logging sheet for a planned session, with the exercises and weights filled in.
@MainActor
private func makeLogSession(for session: PlanSession, store: WorkoutStore) -> LogSession {
    let template = PlanTemplates.template(for: session, exercises: store.allExercises) { store.bestRecord(for: $0) }
    return LogSession(template: template, planSessionID: session.id)
}

private let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

// MARK: - Plans tab

struct PlansView: View {
    @EnvironmentObject private var plans: PlanStore
    @EnvironmentObject private var store: WorkoutStore

    @State private var showingCoach = false
    @State private var logSession: LogSession?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    coachCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if let active = plans.activePlan {
                    Section("Active plan") {
                        ActivePlanCard(plan: active) { session in
                            logSession = makeLogSession(for: session, store: store)
                        }
                    }
                }

                if !plans.proposedPlans.isEmpty {
                    Section("Suggested by your coach") {
                        ForEach(plans.proposedPlans) { plan in
                            NavigationLink(value: plan.id) {
                                PlanRow(plan: plan)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { plans.proposedPlans[$0].id }
                            ids.forEach { plans.delete($0) }
                        }
                    }
                }

                if !plans.pastPlans.isEmpty {
                    Section("Past plans") {
                        ForEach(plans.pastPlans) { plan in
                            NavigationLink(value: plan.id) {
                                PlanRow(plan: plan)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { plans.pastPlans[$0].id }
                            ids.forEach { plans.delete($0) }
                        }
                    }
                }

                if plans.plans.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No plans yet", systemImage: "calendar")
                        } description: {
                            Text("Ask the coach for a plan, like adding to your bench PR or training for a half marathon. It shows up here for you to review and start.")
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Plans")
            .navigationDestination(for: UUID.self) { id in
                PlanDetailView(planID: id)
            }
            .sheet(isPresented: $showingCoach) {
                NavigationStack {
                    CoachChatView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingCoach = false }
                            }
                        }
                }
            }
            .sheet(item: $logSession) { session in
                AddWorkoutView(template: session.template, planSessionID: session.planSessionID)
            }
        }
    }

    private var coachCard: some View {
        Button {
            showingCoach = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask your AI coach")
                        .font(.headline)
                    Text("Build a plan for a PR, a race or a new sport")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rows and cards

private struct PlanRow: View {
    let plan: TrainingPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.title)
                .font(.headline)
            Text(plan.goal)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text("\(plan.weeks) weeks · \(plan.totalSessions) sessions")
                if plan.status != .proposed {
                    Text("· \(Int(plan.progress * 100))% done")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Progress for the plan being followed, and the session to do next.
private struct ActivePlanCard: View {
    let plan: TrainingPlan
    let onStart: (PlanSession) -> Void

    @EnvironmentObject private var store: WorkoutStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: plan.id) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(plan.title)
                            .font(.headline)
                        Spacer()
                        if let week = plan.currentWeek() {
                            Text("Week \(week) of \(plan.weeks)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.18))
                                .foregroundStyle(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    PlanProgressBar(plan: plan)
                }
            }

            if let next = plan.nextSession() {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.state(of: next) == .today ? "Today" : "Up next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SessionSummary(plan: plan, session: next)
                    Button {
                        onStart(next)
                    } label: {
                        Label("Start session", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PlanProgressBar: View {
    let plan: TrainingPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: plan.progress)
                .tint(Theme.accent)
            Text("\(plan.completedSessions) of \(plan.totalSessions) sessions done")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Title, date and a one-line description of a session.
private struct SessionSummary: View {
    let plan: TrainingPlan
    let session: PlanSession

    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var dateText: String {
        if let date = plan.scheduledDate(for: session) {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return "Week \(session.week) · \(weekdayNames[min(max(session.day, 1), 7) - 1])"
    }

    private var detail: String {
        if session.category == .strength, !session.exercises.isEmpty {
            return session.exercises.prefix(3).map(\.name).joined(separator: ", ")
        }
        return session.notes.isEmpty ? session.category.rawValue : session.notes
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.category.icon)
                .frame(width: 36, height: 36)
                .background(session.category.tint.opacity(0.18))
                .foregroundStyle(session.category.tint)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(dateText) · \(session.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Plan detail

struct PlanDetailView: View {
    let planID: UUID

    @EnvironmentObject private var plans: PlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingStart = false
    @State private var confirmingStop = false
    @State private var confirmingDelete = false

    var body: some View {
        if let plan = plans.plan(id: planID) {
            List {
                Section {
                    header(plan)
                }

                Section {
                    actions(plan)
                }

                ForEach(1...max(plan.weeks, 1), id: \.self) { week in
                    let sessions = plan.sessions(inWeek: week)
                    if !sessions.isEmpty {
                        Section(weekTitle(week, plan: plan)) {
                            ForEach(sessions) { session in
                                NavigationLink {
                                    PlanSessionView(planID: plan.id, sessionID: session.id)
                                } label: {
                                    SessionRow(plan: plan, session: session)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingStart) {
                StartPlanSheet(plan: plan)
            }
            .confirmationDialog("Stop this plan?", isPresented: $confirmingStop, titleVisibility: .visible) {
                Button("Stop plan", role: .destructive) { plans.stop(plan.id) }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("It moves to Past plans, with your progress saved.")
            }
            .confirmationDialog("Delete this plan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete plan", role: .destructive) {
                    plans.delete(plan.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Plan not found", systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func weekTitle(_ week: Int, plan: TrainingPlan) -> String {
        guard let start = plan.startDate,
              let first = Calendar.current.date(byAdding: .day, value: (week - 1) * 7, to: Calendar.current.startOfDay(for: start)),
              let last = Calendar.current.date(byAdding: .day, value: 6, to: first) else {
            return "Week \(week)"
        }
        let format = Date.FormatStyle().month(.abbreviated).day()
        return "Week \(week) · \(first.formatted(format)) – \(last.formatted(format))"
    }

    private func header(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.title)
                .font(.title3.weight(.bold))
            Text(plan.goal)
                .font(.subheadline.weight(.medium))
            if !plan.summary.isEmpty {
                Text(plan.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                stat("\(plan.weeks)", "weeks")
                stat("\(plan.totalSessions)", "sessions")
                stat("\(plan.averageMinutes)", "min avg")
            }
            .padding(.top, 4)

            if plan.status == .active || plan.status == .completed {
                PlanProgressBar(plan: plan)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actions(_ plan: TrainingPlan) -> some View {
        switch plan.status {
        case .proposed:
            Button {
                showingStart = true
            } label: {
                Label("Start this plan", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Button("Discard plan", role: .destructive) { confirmingDelete = true }
        case .active:
            Button("Stop plan", role: .destructive) { confirmingStop = true }
        case .completed:
            Label("You finished this plan. Nice work!", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Button("Delete plan", role: .destructive) { confirmingDelete = true }
        case .archived:
            Button {
                showingStart = true
            } label: {
                Label("Restart this plan", systemImage: "arrow.clockwise")
            }
            Button("Delete plan", role: .destructive) { confirmingDelete = true }
        }
    }
}

private struct SessionRow: View {
    let plan: TrainingPlan
    let session: PlanSession

    private var state: PlanSessionState { plan.state(of: session) }

    private var dateText: String {
        if let date = plan.scheduledDate(for: session) {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return weekdayNames[min(max(session.day, 1), 7) - 1]
    }

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(state == .skipped)
                Text("\(dateText) · \(session.durationMinutes) min · \(session.category.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .today:
            Image(systemName: "circle.inset.filled").foregroundStyle(Theme.accent)
        case .missed:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
        case .upcoming, .unscheduled:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Starting a plan

private struct StartPlanSheet: View {
    let plan: TrainingPlan

    @EnvironmentObject private var plans: PlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date()

    private var replacing: TrainingPlan? {
        plans.activePlan.flatMap { $0.id == plan.id ? nil : $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start date", selection: $startDate, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                } footer: {
                    Text("Week 1 begins on this day. Each session lands on the weekday the coach chose.")
                }

                if let replacing {
                    Section {
                        Label("This replaces your current plan, \"\(replacing.title)\". Its progress is kept in Past plans.", systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(plan.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        plans.start(plan.id, on: startDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - A single planned session

struct PlanSessionView: View {
    let planID: UUID
    let sessionID: UUID

    @EnvironmentObject private var plans: PlanStore
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue

    @State private var logSession: LogSession?

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        if let plan = plans.plan(id: planID), let session = plan.sessions.first(where: { $0.id == sessionID }) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.title)
                            .font(.title3.weight(.bold))
                        Text(subtitle(plan: plan, session: session))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !session.notes.isEmpty {
                            Text(session.notes)
                                .font(.subheadline)
                                .padding(.top, 2)
                        }
                        if let distance = session.targetDistanceKm, distance > 0 {
                            Label("\(distance.formatted(.number.precision(.fractionLength(0...1)))) km", systemImage: "ruler")
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !session.exercises.isEmpty {
                    Section("Exercises") {
                        ForEach(session.exercises) { planned in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(planned.summary(record: record(for: planned), unit: unit))
                                    .font(.subheadline)
                                if !planned.notes.isEmpty {
                                    Text(planned.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    actions(plan: plan, session: session)
                }
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $logSession) { session in
                AddWorkoutView(template: session.template, planSessionID: session.planSessionID)
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func record(for planned: PlannedExercise) -> PersonalRecord? {
        store.bestRecord(for: PlanTemplates.resolveExercise(planned, in: store.allExercises).id)
    }

    private func subtitle(plan: TrainingPlan, session: PlanSession) -> String {
        var parts: [String] = []
        if let date = plan.scheduledDate(for: session) {
            parts.append(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        } else {
            parts.append("Week \(session.week), \(weekdayNames[min(max(session.day, 1), 7) - 1])")
        }
        parts.append("\(session.durationMinutes) min")
        parts.append(session.category.rawValue)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func actions(plan: TrainingPlan, session: PlanSession) -> some View {
        if plan.status == .proposed || plan.status == .archived {
            Label("Start the plan to log its sessions.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if session.isDone {
            if let completedAt = session.completedAt {
                Label("Done \(completedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let workoutID = session.completedWorkoutID, let workout = store.workouts.first(where: { $0.id == workoutID }) {
                NavigationLink("View the workout you logged") {
                    WorkoutResultView(workout: workout)
                }
            }
            Button("Undo", role: .destructive) { plans.undoCompletion(sessionID: session.id) }
        } else {
            Button {
                logSession = makeLogSession(for: session, store: store)
            } label: {
                Label("Start workout", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Button("Mark as done without logging") {
                plans.complete(sessionID: session.id, workoutID: nil)
            }

            if session.skipped {
                Button("Unskip") { plans.setSkipped(false, sessionID: session.id) }
            } else {
                Button("Skip this session") { plans.setSkipped(true, sessionID: session.id) }
            }
        }
    }
}
