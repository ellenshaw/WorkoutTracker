//
//  ExercisePickerView.swift
//  WorkoutTracker
//
//  The exercise directory: search, filter by muscle, tick several, add them all at once.
//

import SwiftUI

struct ExercisePickerView: View {
    let onAdd: ([Exercise]) -> Void

    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var filter: MuscleGroup?
    @State private var selectedIDs: [String] = []
    @State private var showingCreate = false

    private var filtered: [Exercise] {
        store.allExercises.filter { exercise in
            let matchesMuscle = filter.map { exercise.primary.contains($0) } ?? true
            let matchesSearch = search.isEmpty || exercise.name.localizedCaseInsensitiveContains(search)
            return matchesMuscle && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                List {
                    ForEach(filtered) { exercise in
                        Button {
                            toggle(exercise)
                        } label: {
                            row(exercise)
                        }
                        .buttonStyle(.plain)
                    }

                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: search)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("Create exercise", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedIDs.isEmpty {
                    Button {
                        addSelected()
                    } label: {
                        Text("Add \(selectedIDs.count) exercise\(selectedIDs.count == 1 ? "" : "s")")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding()
                    .background(.bar)
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateExerciseView { created in
                    selectedIDs.append(created.id)
                }
            }
        }
    }

    // MARK: Pieces

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", muscle: nil)
                ForEach(MuscleGroup.allCases) { muscle in
                    filterChip(title: muscle.title, muscle: muscle)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(title: String, muscle: MuscleGroup?) -> some View {
        let selected = filter == muscle
        return Button {
            filter = muscle
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Color(.tertiarySystemFill))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func row(_ exercise: Exercise) -> some View {
        let selected = selectedIDs.contains(exercise.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(.body.weight(.medium))
                    if exercise.isCustom {
                        Text("Custom")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                Text(exercise.muscleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Actions

    private func toggle(_ exercise: Exercise) {
        if let index = selectedIDs.firstIndex(of: exercise.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(exercise.id)
        }
    }

    private func addSelected() {
        let byID = Dictionary(uniqueKeysWithValues: store.allExercises.map { ($0.id, $0) })
        onAdd(selectedIDs.compactMap { byID[$0] })
        dismiss()
    }
}

// MARK: - Create custom exercise

struct CreateExerciseView: View {
    let onCreate: (Exercise) -> Void

    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var primary: MuscleGroup = .chest
    @State private var secondary: Set<MuscleGroup> = []

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Landmine Press", text: $name)
                }

                Section("Primary muscle") {
                    Picker("Primary muscle", selection: $primary) {
                        ForEach(MuscleGroup.allCases) { muscle in
                            Text(muscle.title).tag(muscle)
                        }
                    }
                }

                Section("Also works (optional)") {
                    ForEach(MuscleGroup.allCases.filter { $0 != primary }) { muscle in
                        Toggle(muscle.title, isOn: Binding(
                            get: { secondary.contains(muscle) },
                            set: { isOn in
                                if isOn { secondary.insert(muscle) } else { secondary.remove(muscle) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("New Exercise")
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
            }
        }
    }

    private func save() {
        let ordered = MuscleGroup.allCases.filter { secondary.contains($0) && $0 != primary }
        let exercise = store.addCustomExercise(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            primary: [primary],
            secondary: ordered
        )
        onCreate(exercise)
        dismiss()
    }
}
