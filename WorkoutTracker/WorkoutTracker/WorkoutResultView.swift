//
//  WorkoutResultView.swift
//  WorkoutTracker
//
//  Shown right after logging a workout (isNew) and when opening one from history.
//

import SwiftUI

struct WorkoutResultView: View {
    let workout: Workout
    var isNew = false
    var onDone: () -> Void = {}

    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var isPinned: Bool {
        store.workouts.first(where: { $0.id == workout.id })?.isPinned ?? false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                HeatBodyCard(heat: workout.heat)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Muscles worked")
                        .font(.headline)
                    MuscleBreakdownList(heat: workout.heat)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                if !workout.exercises.isEmpty {
                    exercisesCard
                }

                if !workout.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.headline)
                        Text(workout.notes)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isNew ? "Workout logged" : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isNew)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.togglePin(workout.id)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(isPinned ? "Unpin workout" : "Pin workout")
            }
            if isNew {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Exercises")
                    .font(.headline)
                Spacer()
                Text("\(unit.format(kg: workout.totalVolumeKg)) \(unit.symbol) total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(workout.exercises) { exercise in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        if store.isPersonalRecord(exercise, in: workout) {
                            Label("PR", systemImage: "trophy.fill")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.25))
                                .foregroundStyle(Color.yellow)
                                .clipShape(Capsule())
                                .accessibilityLabel("New personal record")
                        }
                    }

                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(unit.format(kg: set.weightKg)) \(unit.symbol) × \(set.reps)")
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.category.icon)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.18))
                .foregroundStyle(Theme.accent)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.title3.weight(.semibold))
                Text("\(workout.category.rawValue) · \(workout.duration) min")
                    .foregroundStyle(.secondary)
                if !workout.variantText.isEmpty {
                    Text(workout.variantText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
