//
//  BodyProfileView.swift
//  WorkoutTracker
//
//  Gender, age, weight and height. The 3D body reshapes live as you change them.
//

import SwiftUI

struct BodyProfileView: View {
    @AppStorage(StorageKey.bodyGender) private var genderRaw = BodyGender.neutral.rawValue
    @AppStorage(StorageKey.bodyAge) private var age = 28
    @AppStorage(StorageKey.bodyWeightKg) private var weightKg = 70.0
    @AppStorage(StorageKey.bodyHeightCm) private var heightCm = 172.0
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue

    @State private var weightText = ""
    @FocusState private var weightFocused: Bool

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var profile: BodyProfile {
        BodyProfile(genderRaw: genderRaw, age: age, weightKg: weightKg, heightCm: heightCm)
    }

    var body: some View {
        Form {
            Section {
                BodyModelView(heat: [:], profile: profile, flipToken: 0)
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
                Text("Neutral blends the male and female shapes. Pick whichever looks most like you; it only changes the 3D model.")
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

                Stepper(value: $heightCm, in: BodyProfile.heightRangeCm, step: 1) {
                    LabeledContent("Height", value: "\(Int(heightCm)) cm")
                }
            }
        }
        .navigationTitle("My Body")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { weightText = unit.format(kg: weightKg) }
        .onChange(of: weightText) { _, text in
            // Update the model as the number is typed, ignoring anything that isn't a sensible weight.
            guard weightFocused,
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
            let kg = unit.toKg(value)
            if BodyProfile.weightRangeKg.contains(kg) { weightKg = kg }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
        .onChange(of: weightFocused) { _, focused in
            // Tidy the field once editing ends (and snap invalid input back to the saved weight).
            if !focused { weightText = unit.format(kg: weightKg) }
        }
    }
}
