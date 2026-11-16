//
//  WorkoutHomeView.swift
//  WorkoutTracker
//

import SwiftUI

struct WorkoutHomeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var showingAddWorkout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(workoutCount: store.workoutsThisWeek.count, totalMinutes: store.minutesThisWeek)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if store.workouts.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No workouts yet", systemImage: "figure.run")
                        } description: {
                            Text("Log a workout to see which muscles you hit on the 3D body.")
                        } actions: {
                            Button("Log a workout") { showingAddWorkout = true }
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
                        showingAddWorkout = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add workout")
                }
            }
            .sheet(isPresented: $showingAddWorkout) {
                AddWorkoutView()
            }
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    /// Hardest-worked muscles first, as colored dots.
    private var topMuscles: [(key: MuscleGroup, value: HeatLevel)] {
        let sorted = workout.heat.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key.title < rhs.key.title
        }
        return Array(sorted.prefix(6))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.category.icon)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.18))
                .foregroundStyle(Theme.accent)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name)
                    .font(.headline)

                Text("\(workout.duration) min · \(workout.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !workout.heat.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(topMuscles, id: \.key) { item in
                            Circle()
                                .fill(item.value.color)
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
