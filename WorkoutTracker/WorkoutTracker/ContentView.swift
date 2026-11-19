//
//  ContentView.swift
//  WorkoutTracker
//

import SwiftUI

struct ContentView: View {
    @AppStorage(StorageKey.isLoggedIn) private var isLoggedIn = false
    @State private var showingRegister = false

    var body: some View {
        if isLoggedIn {
            MainTabView()
        } else if showingRegister {
            RegisterView(
                isLoggedIn: $isLoggedIn,
                showingRegister: $showingRegister
            )
        } else {
            LoginView(
                isLoggedIn: $isLoggedIn,
                showingRegister: $showingRegister
            )
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
