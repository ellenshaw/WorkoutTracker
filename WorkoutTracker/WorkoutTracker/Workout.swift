//
//  Workout.swift
//  WorkoutTracker
//
//  Created by ellen hsiao on 5/6/26.
//

import Foundation

struct Workout: Identifiable {
    let id = UUID()
    var name: String
    var category: String
    var duration: Int
    var notes: String
    var date: Date
}
