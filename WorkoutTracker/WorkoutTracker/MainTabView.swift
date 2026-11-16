//
//  MainTabView.swift
//  WorkoutTracker
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            WorkoutHomeView()
                .tabItem { Label("Workouts", systemImage: "list.bullet.rectangle.fill") }

            WeeklyBodyView()
                .tabItem { Label("Body", systemImage: "figure.arms.open") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

/// Combined heat map of the last 7 days.
struct WeeklyBodyView: View {
    @EnvironmentObject private var store: WorkoutStore

    var body: some View {
        let heat = store.weeklyHeat()

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Muscles you've worked over the last 7 days. More sessions and harder effort push a muscle toward red.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HeatBodyCard(heat: heat)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Breakdown")
                            .font(.headline)
                        MuscleBreakdownList(heat: heat)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Body")
        }
    }
}
