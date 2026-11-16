//
//  SettingsView.swift
//  WorkoutTracker
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WorkoutStore

    @AppStorage(StorageKey.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(StorageKey.bodyType) private var bodyType = BodyType.male.rawValue
    @AppStorage(StorageKey.weightUnit) private var weightUnit = WeightUnit.kg.rawValue
    @AppStorage(StorageKey.userName) private var userName = ""
    @AppStorage(StorageKey.isLoggedIn) private var isLoggedIn = false

    @State private var confirmingDelete = false

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

                Section("Body model") {
                    Picker("Body model", selection: $bodyType) {
                        ForEach(BodyType.allCases) { type in
                            Text(type.title).tag(type.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Units") {
                    Picker("Weight", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
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
                    Text("Your workouts are stored only on this device.")
                }
            }
            .navigationTitle("Settings")
            .alert("Delete account and data?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    store.removeAll()
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
