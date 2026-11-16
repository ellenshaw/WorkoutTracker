//
//  BodyProfileView.swift
//  WorkoutTracker
//
//  Gender, age, weight and height, plus personal records for the big three lifts.
//  The 3D body reshapes live as you change the body settings.
//

import SwiftUI

struct BodyProfileView: View {
    @EnvironmentObject private var store: WorkoutStore

    @AppStorage(StorageKey.bodyGender) private var genderRaw = BodyGender.neutral.rawValue
    @AppStorage(StorageKey.bodyAge) private var age = 28
    @AppStorage(StorageKey.bodyWeightKg) private var weightKg = 70.0
    @AppStorage(StorageKey.bodyHeightCm) private var heightCm = 172.0
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(StorageKey.heightUnit) private var heightUnitRaw = HeightUnit.cm.rawValue
    @AppStorage(StorageKey.hologramStyle) private var styleRaw = HologramStyle.lines.rawValue

    @State private var weightText = ""
    @State private var editingLift: BigLift?
    @FocusState private var weightFocused: Bool

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var heightUnit: HeightUnit { HeightUnit(rawValue: heightUnitRaw) ?? .cm }

    private var profile: BodyProfile {
        BodyProfile(genderRaw: genderRaw, age: age, weightKg: weightKg, heightCm: heightCm)
    }

    var body: some View {
        Form {
            Section {
                BodyModelView(heat: [:], profile: profile,
                              style: HologramStyle(rawValue: styleRaw) ?? .lines)
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color(Hologram.background))
                    .accessibilityHidden(true)
            }

            Section {
                Picker("Body shape", selection: $genderRaw) {
                    ForEach(BodyGender.allCases) { gender in
                        Text(gender.title).tag(gender.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Body shape")
            } footer: {
                Text("Neutral sits halfway between the male and female shapes. Pick whichever looks most like you; it only changes the 3D model.")
            }

            Section("About you") {
                Stepper(value: $age, in: BodyProfile.ageRange) {
                    LabeledContent("Age", value: "\(age)")
                }

                LabeledContent("Weight (\(unit.symbol))") {
                    TextField("Weight", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($weightFocused)
                        .frame(maxWidth: 100)
                }

                Stepper(value: $heightCm, in: BodyProfile.heightRangeCm, step: heightUnit.stepCm) {
                    LabeledContent("Height", value: heightUnit.format(cm: heightCm))
                }
            }

            Section("Units") {
                Picker("Weight", selection: $unitRaw) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Height", selection: $heightUnitRaw) {
                    ForEach(HeightUnit.allCases) { unit in
                        Text(unit.title).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Hologram style", selection: $styleRaw) {
                    ForEach(HologramStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Hologram")
            } footer: {
                Text("Lines draws scan-lines across the body. Grid adds a crossing set of lines.")
            }

            recordsSection
        }
        .navigationTitle("My Body")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { weightText = unit.format(kg: weightKg) }
        .onChange(of: unitRaw) { _, _ in
            weightText = unit.format(kg: weightKg)
        }
        .onChange(of: weightText) { _, text in
            // Update the model as the number is typed, ignoring anything that isn't a sensible weight.
            guard weightFocused,
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
            let kg = unit.toKg(value)
            if BodyProfile.weightRangeKg.contains(kg) { weightKg = kg }
        }
        .onChange(of: weightFocused) { _, focused in
            // Tidy the field once editing ends (and snap invalid input back to the saved weight).
            if !focused { weightText = unit.format(kg: weightKg) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
        .sheet(item: $editingLift) { lift in
            RecordEditorView(lift: lift)
        }
    }

    // MARK: Personal records

    private var recordsSection: some View {
        Section {
            ForEach(BigLift.allCases) { lift in
                Button {
                    editingLift = lift
                } label: {
                    RecordRow(lift: lift, record: store.bestRecord(for: lift.exerciseID), unit: unit)
                }
                .buttonStyle(.plain)
            }

            LabeledContent("Total (est. 1RM)") {
                Text("\(unit.format(kg: store.bigThreeTotalKg)) \(unit.symbol)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            NavigationLink("All records") {
                AllRecordsView()
            }
        } header: {
            Text("Personal records")
        } footer: {
            Text("Sets you log count automatically. Tap a lift to enter a record you set elsewhere.")
        }
    }
}

private struct RecordRow: View {
    let lift: BigLift
    let record: PersonalRecord?
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: lift.icon)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.18))
                .foregroundStyle(Theme.accent)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(lift.title)
                    .font(.body.weight(.medium))
                if let record {
                    Text(detail(record))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not set")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let record {
                Text("\(unit.format(kg: record.weightKg)) \(unit.symbol)")
                    .font(.headline)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ record: PersonalRecord) -> String {
        let date = record.date.formatted(date: .abbreviated, time: .omitted)
        let reps = record.reps > 1 ? "× \(record.reps) · est. 1RM \(unit.format(kg: record.estimatedOneRepMaxKg)) · " : ""
        return "\(reps)\(date)"
    }
}

// MARK: - Editing a record

struct RecordEditorView: View {
    let lift: BigLift

    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue

    @State private var weightText = ""
    @State private var reps = 1
    @State private var date = Date()

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var weightKg: Double? {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return unit.toKg(value)
    }

    private var hasManualRecord: Bool {
        store.manualRecords.contains { $0.exerciseID == lift.exerciseID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Weight (\(unit.symbol))") {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    Stepper(value: $reps, in: 1...30) {
                        LabeledContent("Reps", value: "\(reps)")
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    if let kg = weightKg {
                        let estimate = PersonalRecord.estimateOneRepMax(weightKg: kg, reps: reps)
                        Text("Estimated one-rep max: \(unit.format(kg: estimate)) \(unit.symbol)")
                    }
                }

                if hasManualRecord {
                    Section {
                        Button("Remove entered record", role: .destructive) {
                            store.clearManualRecord(exerciseID: lift.exerciseID)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(lift.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(weightKg == nil)
                }
            }
            .onAppear {
                if let best = store.bestRecord(for: lift.exerciseID) {
                    weightText = unit.format(kg: best.weightKg)
                    reps = min(max(best.reps, 1), 30)
                    date = best.date
                }
            }
        }
    }

    private func save() {
        guard let kg = weightKg else { return }
        store.setManualRecord(PersonalRecord(exerciseID: lift.exerciseID, name: lift.exerciseName,
                                             weightKg: kg, reps: reps, date: date, isManual: true))
        dismiss()
    }
}

// MARK: - All records

struct AllRecordsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        let records = store.allRecords()

        List {
            if records.isEmpty {
                ContentUnavailableView("No records yet", systemImage: "trophy",
                                       description: Text("Log a strength workout and your best sets show up here."))
                    .listRowBackground(Color.clear)
            }
            ForEach(records) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.name)
                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(unit.format(kg: record.weightKg)) \(unit.symbol) × \(record.reps)")
                            .monospacedDigit()
                        Text("est. 1RM \(unit.format(kg: record.estimatedOneRepMaxKg))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("All Records")
        .navigationBarTitleDisplayMode(.inline)
    }
}
