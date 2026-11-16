//
//  SummaryCard.swift
//  WorkoutTracker
//

import SwiftUI

struct SummaryCard: View {
    let workoutCount: Int
    let totalMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("\(workoutCount)")
                        .font(.largeTitle.bold())
                    Text(workoutCount == 1 ? "workout" : "workouts")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("\(totalMinutes)")
                        .font(.largeTitle.bold())
                    Text("minutes")
                        .foregroundStyle(.secondary)
                }
            }

            Text(workoutCount >= 3 ? "🔥 Strong week. Keep it going." : "💪 Add more workouts to build your streak.")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
