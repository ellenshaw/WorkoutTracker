//
//  ContentView.swift
//  WorkoutTracker
//

import SwiftUI

struct ContentView: View {
    @AppStorage(StorageKey.hasOnboarded) private var hasOnboarded = false

    var body: some View {
        if hasOnboarded {
            MainTabView()
        } else {
            WelcomeView { hasOnboarded = true }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutStore())
        .environmentObject(PlanStore())
        .environmentObject(CoachModel())
        .environmentObject(CycleStore())
}
