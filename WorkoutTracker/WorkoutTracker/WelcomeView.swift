//
//  WelcomeView.swift
//  WorkoutTracker
//
//  Shown on first launch. There are no accounts: everything stays on the device, so this is just
//  a short introduction and an optional first name.
//

import SwiftUI

struct WelcomeView: View {
    let onStart: () -> Void

    @AppStorage(StorageKey.userName) private var userName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Workout Tracker")
                        .font(.largeTitle.bold())
                    Text("Log your training and see exactly which muscles you worked.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    feature("figure.arms.open", "Muscle heat map",
                            "A 3D body lights up in blue to red for what you trained and fades as you recover.")
                    feature("chart.line.uptrend.xyaxis", "Track progress",
                            "Strength records, one-rep max, pace and distance charts.")
                    feature("sparkles", "AI coach",
                            "Ask for a plan, then follow it and tick off sessions.")
                    feature("lock.fill", "Private by default",
                            "Your workouts stay on this iPhone. No account needed.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("What should we call you? (optional)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("First name", text: $userName)
                        .textContentType(.givenName)
                        .focused($nameFocused)
                        .fieldStyle()
                }

                Button("Get started") {
                    nameFocused = false
                    userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                    onStart()
                }
                .buttonStyle(PrimaryButtonStyle())

                Spacer(minLength: 12)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
