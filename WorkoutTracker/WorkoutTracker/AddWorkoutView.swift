//
//  AddWorkoutView.swift
//  WorkoutTracker
//

import SwiftUI

struct AddWorkoutView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = WorkoutCategory.strength
    @State private var duration = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var muscleLevels: [MuscleGroup: HeatLevel] = [:]
    @State private var musclesEdited = false
    @State private var savedWorkout: Workout?

    @FocusState private var keyboardFocused: Bool

    private var minutes: Int { Int(duration) ?? 0 }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...1440).contains(minutes)
            && savedWorkout == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Workout name", text: $name)
                        .focused($keyboardFocused)

                    Picker("Category", selection: $category) {
                        ForEach(WorkoutCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }

                    TextField("Duration in minutes", text: $duration)
                        .keyboardType(.numberPad)
                        .focused($keyboardFocused)

                    DatePicker("When", selection: $date, in: ...Date())

                    TextField("Notes", text: $notes, axis: .vertical)
                        .focused($keyboardFocused)
                }

                Section {
                    Text("Tap a muscle to set how hard you worked it: yellow is light, orange is moderate, red is heavy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(MuscleGroup.regions, id: \.name) { region in
                    Section(region.name) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(region.muscles) { muscle in
                                MuscleChip(muscle: muscle, level: muscleLevels[muscle] ?? HeatLevel.none) {
                                    cycle(muscle)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { keyboardFocused = false }
                }
            }
            .onChange(of: category) { _, newValue in
                // Suggest muscles for the category until the user picks their own.
                if !musclesEdited {
                    muscleLevels = newValue.suggestedMuscles
                }
            }
            .navigationDestination(item: $savedWorkout) { workout in
                WorkoutResultView(workout: workout, isNew: true) {
                    dismiss()
                }
            }
        }
    }

    private func cycle(_ muscle: MuscleGroup) {
        musclesEdited = true
        let next = (muscleLevels[muscle] ?? HeatLevel.none).next
        if next == .none {
            muscleLevels.removeValue(forKey: muscle)
        } else {
            muscleLevels[muscle] = next
        }
    }

    private func save() {
        keyboardFocused = false
        var workout = Workout(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            duration: minutes,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date
        )
        workout.heat = muscleLevels
        store.add(workout)
        savedWorkout = workout
    }
}

private struct MuscleChip: View {
    let muscle: MuscleGroup
    let level: HeatLevel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(level.color)
                    .frame(width: 10, height: 10)
                Text(muscle.title)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(level == .none ? Color(.tertiarySystemFill) : level.color.opacity(0.22))
            .overlay(
                Capsule().stroke(level == .none ? Color.clear : level.color, lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        // Needed so each chip is its own tap target inside a Form row.
        .buttonStyle(.plain)
        .accessibilityLabel(muscle.title)
        .accessibilityValue(level.title)
        .accessibilityHint("Double tap to change intensity")
    }
}
