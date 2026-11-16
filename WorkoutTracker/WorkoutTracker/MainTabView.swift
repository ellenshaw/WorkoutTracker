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

            PlansView()
                .tabItem { Label("Plans", systemImage: "calendar") }

            WeeklyBodyView()
                .tabItem { Label("Body", systemImage: "figure.arms.open") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

/// Combined heat map of recent workouts, fading over time.
struct WeeklyBodyView: View {
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(StorageKey.fadeHalfLifeDays) private var fadeHalfLife = 3.5

    var body: some View {
        let heat = store.currentHeat(halfLifeDays: fadeHalfLife)

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Recent workouts glow, then fade from red back toward blue as your muscles recover. More sessions and harder effort push a muscle toward red.")
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
