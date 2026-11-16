//
//  WorkoutHomeView.swift
//  WorkoutTracker
//
//  Created by ellen hsiao on 5/6/26.
//

import Foundation
import SwiftUI

struct WorkoutHomeView: View {
    @State private var workouts: [Workout] = [
        Workout(name: "Rock Climbing", category: "Strength", duration: 90, notes: "Worked on V2 routes", date: Date()),
        Workout(name: "Run", category: "Cardio", duration: 30, notes: "Easy pace", date: Date())
    ]

    @State private var showingAddWorkout = false

    var totalMinutes: Int {
        workouts.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        NavigationStack {
            VStack {
                SummaryCard(workoutCount: workouts.count, totalMinutes: totalMinutes)

                List {
                    ForEach(workouts) { workout in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(workout.name)
                                    .font(.headline)

                                Spacer()

                                Text(workout.category)
                                    .font(.caption)
                                    .padding(6)
                                    .background(.blue.opacity(0.15))
                                    .clipShape(Capsule())
                            }

                            Text("\(workout.duration) min")
                                .foregroundStyle(.secondary)

                            if !workout.notes.isEmpty {
                                Text(workout.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        workouts.remove(atOffsets: indexSet)
                    }
                }
            }
            .navigationTitle("My Workouts")
            .toolbar {
                Button {
                    showingAddWorkout = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .sheet(isPresented: $showingAddWorkout) {
                AddWorkoutView(workouts: $workouts)
            }
        }
    }
}
