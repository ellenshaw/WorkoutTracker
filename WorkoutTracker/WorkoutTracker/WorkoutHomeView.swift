//
//  WorkoutHomeView.swift
//  WorkoutTracker
//

import SwiftUI

struct WorkoutHomeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var session: LogSession?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(workoutCount: store.workoutsThisWeek.count, totalMinutes: store.minutesThisWeek)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if !store.pinnedWorkouts.isEmpty {
                    Section("Pinned") {
                        pinnedStrip
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if store.workouts.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No workouts yet", systemImage: "figure.run")
                        } description: {
                            Text("Log a workout to see which muscles you hit on the 3D body.")
                        } actions: {
                            Button("Log a workout") { session = LogSession() }
                                .buttonStyle(.borderedProminent)
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("History") {
                        ForEach(store.workouts) { workout in
                            NavigationLink(value: workout) {
                                WorkoutRow(workout: workout)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    store.togglePin(workout.id)
                                } label: {
                                    Label(workout.isPinned ? "Unpin" : "Pin", systemImage: workout.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(Theme.accent)
                            }
                            .contextMenu {
                                Button {
                                    store.togglePin(workout.id)
                                } label: {
                                    Label(workout.isPinned ? "Unpin" : "Pin to top", systemImage: workout.isPinned ? "pin.slash" : "pin")
                                }
                                Button {
                                    session = LogSession(template: workout)
                                } label: {
                                    Label("Repeat workout", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("My Workouts")
            .navigationDestination(for: Workout.self) { workout in
                WorkoutResultView(workout: workout)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        session = LogSession()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add workout")
                }
            }
            .sheet(item: $session) { session in
                AddWorkoutView(template: session.template)
            }
        }
    }

    private var pinnedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.pinnedWorkouts) { workout in
                    Button {
                        session = LogSession(template: workout)
                    } label: {
                        PinnedCard(workout: workout)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            store.togglePin(workout.id)
                        } label: {
                            Label("Unpin", systemImage: "pin.slash")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}

/// One-tap template: starts a new log with this workout's exercises or activity filled in.
private struct PinnedCard: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: workout.category.icon)
                    .foregroundStyle(workout.category.tint)
                    .frame(width: 34, height: 34)
                    .background(workout.category.tint.opacity(0.18))
                    .clipShape(Circle())
                Spacer()
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(workout.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(workout.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Label("Start", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(width: 150, height: 128, alignment: .topLeading)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts a new workout from this one")
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    /// Hardest-worked muscles first, as colored dots.
    private var topMuscles: [(key: MuscleGroup, value: Double)] {
        let sorted = workout.heat.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key.title < rhs.key.title
        }
        return Array(sorted.prefix(6))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.category.icon)
                .frame(width: 36, height: 36)
                .background(workout.category.tint.opacity(0.18))
                .foregroundStyle(workout.category.tint)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(workout.name)
                        .font(.headline)
                    if workout.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }
                }

                Text("\(workout.summary) · \(workout.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !workout.heat.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(topMuscles, id: \.key) { item in
                            Circle()
                                .fill(HeatScale.color(item.value))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
