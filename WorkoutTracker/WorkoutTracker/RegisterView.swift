//
//  RegisterView.swift
//  WorkoutTracker
//
//  Created by ellen hsiao on 5/6/26.
//

import Foundation
import SwiftUI

struct RegisterView: View {
    @Binding var isLoggedIn: Bool
    @Binding var showingRegister: Bool

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var formIsValid: Bool {
        !name.isEmpty && !email.isEmpty && passwordsMatch
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 70))
                .foregroundStyle(.blue)

            Text("Create Account")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }

            if !confirmPassword.isEmpty && !passwordsMatch {
                Text("Passwords do not match")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                isLoggedIn = true
            } label: {
                Text("Create Account")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(formIsValid ? .blue : .gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!formIsValid)

            Button("Already have an account? Log in") {
                showingRegister = false
            }

            Spacer()
        }
        .padding()
    }
}
