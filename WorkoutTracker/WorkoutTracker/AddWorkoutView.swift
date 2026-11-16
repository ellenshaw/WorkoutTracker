//
//  AddWorkoutView.swift
//  WorkoutTracker
//
//  Created by ellen hsiao on 5/6/26.
//

import Foundation
import SwiftUI

struct AddWorkoutView: View {
    @Binding var workouts: [Workout]
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "Strength"
    @State private var duration = ""
    @State private var notes = ""

    let categories = ["Strength", "Cardio", "Climbing", "Sport", "Mobility"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Workout name", text: $name)

                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { category in
                        Text(category)
                    }
                }

                TextField("Duration in minutes", text: $duration)
                    .keyboardType(.numberPad)

                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("Add Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newWorkout = Workout(
                            name: name,
                            category: category,
                            duration: Int(duration) ?? 0,
                            notes: notes,
                            date: Date()
                        )

                        workouts.append(newWorkout)
                        dismiss()
                    }
                    .disabled(name.isEmpty || duration.isEmpty)
                }
            }
        }
    }
}
