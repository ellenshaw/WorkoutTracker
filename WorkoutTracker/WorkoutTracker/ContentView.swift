//
//  ContentView.swift
//  WorkoutTracker
//
//  Created by ellen hsiao on 5/5/26.
//

import SwiftUI

struct ContentView: View {
    @State private var isLoggedIn = false
    @State private var showingRegister = false

    var body: some View {
        if isLoggedIn {
            WorkoutHomeView()
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
}
