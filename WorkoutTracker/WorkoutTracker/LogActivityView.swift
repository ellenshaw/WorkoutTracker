//
//  LogActivityView.swift
//  WorkoutTracker
//
//  Logging for cardio, climbing, sport and mobility: tap an activity block, set the time.
//

import SwiftUI

struct LogActivityView: View {
    let category: WorkoutCategory
    var template: Workout?
    let onCancel: () -> Void
    let onSave: (Workout) -> Void

    @State private var selectedActivity: String?
    @State private var name: String
    @State private var duration: String
    @State private var date = Date()
    @State private var notes: String
    @State private var levels: [MuscleGroup: HeatLevel]
    @State private var musclesEdited: Bool

    @FocusState private var keyboardFocused: Bool

    private static let customTile = "Custom"
    private let quickDurations = [15, 30, 45, 60, 90]

    init(category: WorkoutCategory, template: Workout?, onCancel: @escaping () -> Void, onSave: @escaping (Workout) -> Void) {
        self.category = category
        self.template = template
        self.onCancel = onCancel
        self.onSave = onSave

        let isKnown = category.activities.contains { $0.name == template?.name }
        _selectedActivity = State(initialValue: template.map { isKnown ? $0.name : LogActivityView.customTile })
        _name = State(initialValue: template?.name ?? "")
        _duration = State(initialValue: template.map { String($0.duration) } ?? "")
        _notes = State(initialValue: template?.notes ?? "")
        _levels = State(initialValue: template?.heat.mapValues { HeatLevel(nearest: $0) } ?? [:])
        _musclesEdited = State(initialValue: template != nil)
    }

    private var minutes: Int { Int(duration) ?? 0 }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...1440).contains(minutes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                activityCard
                if selectedActivity != nil {
                    detailsCard
                    musclesCard
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
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
    }

    // MARK: Cards

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick an activity")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(category.activities) { preset in
                    ActivityTile(title: preset.name, icon: preset.symbol, tint: category.tint,
                                 selected: selectedActivity == preset.name) {
                        choose(preset)
                    }
                }
                ActivityTile(title: LogActivityView.customTile, icon: "plus", tint: category.tint,
                             selected: selectedActivity == LogActivityView.customTile) {
                    chooseCustom()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.headline)

            TextField("Workout name", text: $name)
                .focused($keyboardFocused)
                .fieldStyle()

            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickDurations, id: \.self) { value in
                            Button("\(value) min") {
                                duration = String(value)
                                keyboardFocused = false
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(minutes == value ? category.tint.opacity(0.25) : Color(.tertiarySystemFill))
                            .overlay(Capsule().stroke(minutes == value ? category.tint : .clear, lineWidth: 1.5))
                            .clipShape(Capsule())
                        }
                    }
                }

                TextField("Minutes", text: $duration)
                    .keyboardType(.numberPad)
                    .focused($keyboardFocused)
                    .fieldStyle()
            }

            DatePicker("When", selection: $date, in: ...Date())

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(1...4)
                .focused($keyboardFocused)
                .fieldStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var musclesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Muscles worked")
                .font(.headline)
            Text("Tap a muscle to set how hard you worked it: yellow is light, orange is moderate, red is heavy.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            MuscleChipPicker(levels: $levels) { musclesEdited = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Actions

    private func choose(_ preset: ActivityPreset) {
        selectedActivity = preset.name
        name = preset.name
        if !musclesEdited {
            levels = preset.muscles
        }
    }

    private func chooseCustom() {
        selectedActivity = LogActivityView.customTile
        name = ""
        keyboardFocused = true
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
        workout.heat = levels.mapValues { $0.intensity }
        onSave(workout)
    }
}

private struct ActivityTile: View {
    let title: String
    let icon: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(height: 24)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected ? tint : .primary)
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.horizontal, 6)
            .background(selected ? tint.opacity(0.2) : Color(.tertiarySystemFill))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? tint : .clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Muscle chips

/// Tap-to-cycle chips (none → light → moderate → heavy), grouped by body region.
struct MuscleChipPicker: View {
    @Binding var levels: [MuscleGroup: HeatLevel]
    var onEdit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(MuscleGroup.regions, id: \.name) { region in
                VStack(alignment: .leading, spacing: 8) {
                    Text(region.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(region.muscles) { muscle in
                            MuscleChip(muscle: muscle, level: levels[muscle] ?? HeatLevel.none) {
                                cycle(muscle)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cycle(_ muscle: MuscleGroup) {
        onEdit()
        let next = (levels[muscle] ?? HeatLevel.none).next
        if next == HeatLevel.none {
            levels.removeValue(forKey: muscle)
        } else {
            levels[muscle] = next
        }
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
            .background(level == HeatLevel.none ? Color(.tertiarySystemFill) : level.color.opacity(0.22))
            .overlay(
                Capsule().stroke(level == HeatLevel.none ? Color.clear : level.color, lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(muscle.title)
        .accessibilityValue(level.title)
        .accessibilityHint("Double tap to change intensity")
    }
}
