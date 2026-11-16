//
//  SummaryCard.swift
//  WorkoutTracker
//
//  Created by ellen hsiao on 5/6/26.
//

import Foundation
import SwiftUI

struct SummaryCard: View {
    let workoutCount: Int
    let totalMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("\(workoutCount)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("workouts")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("\(totalMinutes)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("minutes")
                        .foregroundStyle(.secondary)
                }
            }

            Text(workoutCount >= 3 ? "🔥 Strong week. Keep it going." : "💪 Add more workouts to build your streak.")
                .font(.subheadline)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}
