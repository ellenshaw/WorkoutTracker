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

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 70))
                .foregroundStyle(.blue)

            Text("Workout Tracker")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Track workouts. Build consistency.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                isLoggedIn = true
            } label: {
                Text("Log In")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
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
