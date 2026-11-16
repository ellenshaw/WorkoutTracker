//
//  SettingsView.swift
//  WorkoutTracker
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var plans: PlanStore
    @EnvironmentObject private var coach: CoachModel

    @AppStorage(StorageKey.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(StorageKey.heightUnit) private var heightUnit = HeightUnit.cm.rawValue
    @AppStorage(StorageKey.fadeHalfLifeDays) private var fadeHalfLife = 3.5
    @AppStorage(StorageKey.weightUnit) private var weightUnit = WeightUnit.kg.rawValue
    @AppStorage(StorageKey.userName) private var userName = ""
    @AppStorage(StorageKey.isLoggedIn) private var isLoggedIn = false

    @AppStorage(StorageKey.coachShareHistory) private var coachShare = true
    @AppStorage(StorageKey.coachConsent) private var coachConsent = false
    @AppStorage(StorageKey.coachBaseURL) private var coachURL = ""
    @AppStorage(StorageKey.coachAppKey) private var coachKey = ""

    @State private var confirmingDelete = false

    /// Release builds carry the server address in Info.plist; only development builds show the fields.
    private var coachIsPreconfigured: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CoachBaseURL") != nil
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("3D body") {
                    NavigationLink {
                        BodyProfileView()
                    } label: {
                        Label("My body", systemImage: "person.crop.circle")
                    }
                }

                Section {
                    Picker("Colors fade", selection: $fadeHalfLife) {
                        Text("Fast").tag(2.0)
                        Text("Normal").tag(3.5)
                        Text("Slow").tag(6.0)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Recovery")
                } footer: {
                    Text("How quickly a worked muscle's color cools back to blue on the Body tab.")
                }

                Section("Units") {
                    Picker("Weight", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Height", selection: $heightUnit) {
                        ForEach(HeightUnit.allCases) { unit in
                            Text(unit.title).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Share training info with coach", isOn: $coachShare)

                    if !coachIsPreconfigured {
                        TextField("Server address", text: $coachURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("App key", text: $coachKey)
                    }

                    Button("Clear coach conversation") { coach.clear() }
                } header: {
                    Text("AI coach")
                } footer: {
                    Text(coachIsPreconfigured
                         ? "When on, the coach sees your age, weight, height, records and recent workouts so plans fit you. Messages are processed by an AI service."
                         : "Development build: enter the address of your coach server (see backend/README.md). The AI key lives on the server, never in the app.")
                }

                Section("Account") {
                    if !userName.isEmpty {
                        LabeledContent("Signed in as", value: userName)
                    }

                    Button("Log out") {
                        isLoggedIn = false
                    }

                    Button("Delete account and data", role: .destructive) {
                        confirmingDelete = true
                    }
                }

                Section {
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("Your workouts are stored only on this device. The 3D body is based on the MakeHuman base mesh (CC0).")
                }
            }
            .navigationTitle("Settings")
            .alert("Delete account and data?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    store.removeAll()
                    plans.removeAll()
                    coach.clear()
                    coachConsent = false
                    userName = ""
                    isLoggedIn = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes all your workouts from this device.")
            }
        }
    }
}
