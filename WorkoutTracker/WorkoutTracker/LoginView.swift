//
//  LoginView.swift
//  WorkoutTracker
//
//  Created by ellen hsiao on 5/6/26.
//

import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @Binding var showingRegister: Bool

    @AppStorage(StorageKey.userName) private var userName = ""

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 70))
                .foregroundStyle(Theme.accent)

            Text("Workout Tracker")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Track workouts. Build consistency.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                if userName.isEmpty {
                    userName = username
                }
                isLoggedIn = true
            } label: {
                Text("Log In")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(username.isEmpty || password.isEmpty)

            Button("Create an account") {
                showingRegister = true
            }
            .fontWeight(.semibold)

            Spacer()
        }
        .padding()
    }
}
