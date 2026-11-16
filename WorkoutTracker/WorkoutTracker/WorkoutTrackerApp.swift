//
//  WorkoutTrackerApp.swift
//  WorkoutTracker
//

import SwiftUI

@main
struct WorkoutTrackerApp: App {
    @StateObject private var store = WorkoutStore()
    @StateObject private var plans = PlanStore()
    @StateObject private var coach = CoachModel()
    @AppStorage(StorageKey.appearance) private var appearance = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(plans)
                .environmentObject(coach)
                .tint(Theme.accent)
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
        }
    }
}
