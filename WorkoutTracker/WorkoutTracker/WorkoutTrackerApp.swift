//
//  WorkoutTrackerApp.swift
//  WorkoutTracker
//

import SwiftUI

@main
struct WorkoutTrackerApp: App {
    @StateObject private var store = WorkoutStore()
    @AppStorage(StorageKey.appearance) private var appearance = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Theme.accent)
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
        }
    }
}
