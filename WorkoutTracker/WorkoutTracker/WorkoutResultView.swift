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
            if isNew {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
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
