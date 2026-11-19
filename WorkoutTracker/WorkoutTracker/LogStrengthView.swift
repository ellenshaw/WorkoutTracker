//
//  LogStrengthView.swift
//  WorkoutTracker
//
//  Hevy-style strength logging: add exercises from the directory, log sets of weight × reps,
//  tick them off, and finish. Muscle heat for the 3D model is worked out from the sets.
//

import SwiftUI

/// What a new set starts with. Only the weight is remembered from last time (reps are yours to
/// decide); last time's numbers are still shown in the "Previous" column for reference.
enum StrengthPrefill {
    /// Last time's weight for this set number, or for the last set if you did fewer before.
    /// Empty when there is no history or the sets used no weight.
    static func weightText(previous: [LoggedSet], index: Int, unit: WeightUnit) -> String {
        guard let last = previous.last else { return "" }
        let set = previous.indices.contains(index) ? previous[index] : last
        return set.weightKg > 0 ? unit.format(kg: set.weightKg) : ""
    }
}

private struct DraftSet: Identifiable, Hashable {
    let id = UUID()
    var weight = ""
    var reps = ""
    var done = false
}

private struct DraftExercise: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var sets: [DraftSet]
    /// What the user did last time, shown as a hint and used to autofill on check-off.
    var previous: [LoggedSet]

    func previousSet(at index: Int) -> LoggedSet? {
        previous.indices.contains(index) ? previous[index] : previous.last
    }
}

struct LogStrengthView: View {
    var template: Workout?
    let onCancel: () -> Void
    let onSave: (Workout) -> Void

    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var cycle: CycleStore
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue

    @State private var title: String
    @State private var exercises: [DraftExercise] = []
    @State private var notes: String
    @State private var date = Date()
    @State private var durationOverride = ""
    @State private var showingPicker = false
    @State private var confirmingDiscard = false
    @State private var loadedTemplate = false
    @State private var chartExercise: Exercise?

    @FocusState private var keyboardFocused: Bool

    private let startedAt = Date()

    init(template: Workout?, onCancel: @escaping () -> Void, onSave: @escaping (Workout) -> Void) {
        self.template = template
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: template?.name ?? LogStrengthView.defaultTitle())
        _notes = State(initialValue: template?.notes ?? "")
    }

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private static func defaultTitle() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        case 17..<22: return "Evening Workout"
        default: return "Night Workout"
        }
    }

    // MARK: Derived values

    private func parsedWeight(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var doneSets: [(DraftExercise, DraftSet)] {
        exercises.flatMap { exercise in
            exercise.sets.filter { $0.done && (Int($0.reps) ?? 0) > 0 }.map { (exercise, $0) }
        }
    }

    private var volumeText: String {
        let kg = doneSets.reduce(0.0) { total, pair in
            total + unit.toKg(parsedWeight(pair.1.weight) ?? 0) * Double(Int(pair.1.reps) ?? 0)
        }
        return "\(unit.format(kg: kg)) \(unit.symbol)"
    }

    private var canFinish: Bool { !doneSets.isEmpty }

    // MARK: Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TextField("Workout name", text: $title)
                    .font(.title2.bold())
                    .focused($keyboardFocused)

                statsBar

                if let note = cycle.note(), note.kind != .general {
                    CycleBanner(note: note)
                }

                ForEach($exercises) { $draft in
                    exerciseCard($draft)
                }

                Button {
                    keyboardFocused = false
                    showingPicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                if !exercises.isEmpty {
                    optionsCard
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if exercises.isEmpty { onCancel() } else { confirmingDiscard = true }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish", action: finish)
                    .fontWeight(.semibold)
                    .disabled(!canFinish)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardFocused = false }
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Workout", role: .destructive, action: onCancel)
            Button("Keep Logging", role: .cancel) {}
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { picked in
                for exercise in picked {
                    let previous = store.lastSets(for: exercise.id)
                    let first = DraftSet(weight: StrengthPrefill.weightText(previous: previous, index: 0, unit: unit))
                    exercises.append(DraftExercise(exercise: exercise, sets: [first], previous: previous))
                }
            }
        }
        .sheet(item: $chartExercise) { exercise in
            // Opens over the logger, so nothing you've typed is lost.
            NavigationStack {
                ExerciseProgressView(exerciseID: exercise.id, title: exercise.name)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { chartExercise = nil }
                        }
                    }
            }
        }
        .onAppear(perform: loadTemplateIfNeeded)
    }

    // MARK: Pieces

    private var statsBar: some View {
        HStack {
            stat(title: "Duration") {
                Text(startedAt, style: .timer)
                    .monospacedDigit()
            }
            Divider().frame(height: 30)
            stat(title: "Volume") { Text(volumeText) }
            Divider().frame(height: 30)
            stat(title: "Sets") { Text("\(doneSets.count)") }
            Divider().frame(height: 30)
            stat(title: "Top weight") { Text(maxWeightText) }
        }
        .cardStyle()
    }

    /// The heaviest weight among the sets you've ticked off so far.
    private var maxWeightText: String {
        let kg = doneSets.map { unit.toKg(parsedWeight($0.1.weight) ?? 0) }.max() ?? 0
        return kg > 0 ? "\(unit.format(kg: kg)) \(unit.symbol)" : "–"
    }

    private func stat<Content: View>(title: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(spacing: 2) {
            value()
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func exerciseCard(_ draft: Binding<DraftExercise>) -> some View {
        let value = draft.wrappedValue

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.exercise.name)
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                    Text(value.exercise.muscleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("View Progress") { chartExercise = value.exercise }
                    Button("Add Set") { addSet(to: value.id) }
                    Button("Remove Last Set") { removeLastSet(from: value.id) }
                        .disabled(value.sets.count <= 1)
                    Button("Remove Exercise", role: .destructive) {
                        exercises.removeAll { $0.id == value.id }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .padding(4)
                }
                .accessibilityLabel("Options for \(value.exercise.name)")
            }

            ExerciseSparkline(exerciseID: value.exercise.id) { chartExercise = value.exercise }

            HStack(spacing: 8) {
                Text("SET").frame(width: 28)
                Text("PREVIOUS").frame(maxWidth: .infinity)
                Text(unit.symbol.uppercased()).frame(width: 70)
                Text("REPS").frame(width: 56)
                Image(systemName: "checkmark").frame(width: 34)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(draft.sets) { $entry in
                let index = value.sets.firstIndex(where: { $0.id == entry.id }) ?? 0
                setRow(index: index, entry: $entry, previous: value.previousSet(at: index))
            }

            Button {
                addSet(to: value.id)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    private func setRow(index: Int, entry: Binding<DraftSet>, previous: LoggedSet?) -> some View {
        let prevText = previous.map { "\(unit.format(kg: $0.weightKg)) × \($0.reps)" } ?? "–"
        let weightHint = previous.map { unit.format(kg: $0.weightKg) } ?? "0"
        let repsHint = "reps"

        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())

            Text(prevText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            TextField(weightHint, text: entry.weight)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .focused($keyboardFocused)
                .fieldStyle()
                .frame(width: 70)

            TextField(repsHint, text: entry.reps)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($keyboardFocused)
                .fieldStyle()
                .frame(width: 56)

            Button {
                toggleDone(entry, previous: previous)
            } label: {
                Image(systemName: entry.wrappedValue.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(entry.wrappedValue.done ? Color.green : Color.secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.wrappedValue.done ? "Set \(index + 1) done" : "Mark set \(index + 1) done")
        }
        .padding(.vertical, 2)
        .background(entry.wrappedValue.done ? Color.green.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("When", selection: $date, in: ...Date())

            TextField("Duration in minutes (auto from timer)", text: $durationOverride)
                .keyboardType(.numberPad)
                .focused($keyboardFocused)
                .fieldStyle()

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(1...4)
                .focused($keyboardFocused)
                .fieldStyle()
        }
        .cardStyle()
    }

    // MARK: Actions

    private func addSet(to id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        // The weight comes from last time (or, with no history, repeats the set above); reps stay empty.
        var weight = StrengthPrefill.weightText(previous: exercises[index].previous,
                                                index: exercises[index].sets.count, unit: unit)
        if weight.isEmpty, let above = exercises[index].sets.last?.weight { weight = above }
        exercises[index].sets.append(DraftSet(weight: weight))
    }

    private func removeLastSet(from id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              exercises[index].sets.count > 1 else { return }
        exercises[index].sets.removeLast()
    }

    private func toggleDone(_ set: Binding<DraftSet>, previous: LoggedSet?) {
        keyboardFocused = false
        if set.wrappedValue.done {
            set.wrappedValue.done = false
            return
        }
        // An empty weight falls back to last time's. Reps are never filled in for you.
        if set.wrappedValue.weight.isEmpty, let previous, previous.weightKg > 0 {
            set.wrappedValue.weight = unit.format(kg: previous.weightKg)
        }
        if (Int(set.wrappedValue.reps) ?? 0) > 0 {
            set.wrappedValue.done = true
        }
    }

    private func loadTemplateIfNeeded() {
        guard !loadedTemplate else { return }
        loadedTemplate = true
        guard let template else { return }

        exercises = template.exercises.map { logged in
            let exercise = Exercise(id: logged.exerciseID, name: logged.name,
                                    primary: logged.primary, secondary: logged.secondary)
            // Unknown weights or reps (for example "AMRAP" in a plan) stay blank for the user to fill in.
            let sets = logged.sets.map {
                DraftSet(weight: $0.weightKg > 0 ? unit.format(kg: $0.weightKg) : "",
                         reps: $0.reps > 0 ? String($0.reps) : "",
                         done: false)
            }
            return DraftExercise(exercise: exercise,
                                 sets: sets.isEmpty ? [DraftSet()] : sets,
                                 previous: store.lastSets(for: logged.exerciseID))
        }
    }

    private func finish() {
        keyboardFocused = false

        let logged: [LoggedExercise] = exercises.compactMap { draft in
            let sets: [LoggedSet] = draft.sets.compactMap { set in
                guard set.done, let reps = Int(set.reps), reps > 0 else { return nil }
                return LoggedSet(weightKg: unit.toKg(parsedWeight(set.weight) ?? 0), reps: reps)
            }
            guard !sets.isEmpty else { return nil }
            return LoggedExercise(exerciseID: draft.exercise.id, name: draft.exercise.name,
                                  primary: draft.exercise.primary, secondary: draft.exercise.secondary,
                                  sets: sets)
        }

        let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        var minutes = min(elapsed, 1440)
        if let manual = Int(durationOverride), (1...1440).contains(manual) {
            minutes = manual
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        var workout = Workout(
            name: trimmedTitle.isEmpty ? LogStrengthView.defaultTitle() : trimmedTitle,
            category: .strength,
            duration: minutes,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            exercises: logged
        )
        workout.heat = HeatCalculator.strengthHeat(exercises: logged)
        onSave(workout)
    }
}
