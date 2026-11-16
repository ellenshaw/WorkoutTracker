//
//  BodyProfile.swift
//  WorkoutTracker
//
//  The user's body settings. They drive the shape of the 3D model.
//

import Foundation

enum BodyGender: String, CaseIterable, Identifiable {
    case male, female, neutral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .neutral: return "Neutral"
        }
    }

    /// How much of the male shape to use: 1 is fully male, 0 fully female, in between is a blend.
    var maleShare: Float {
        switch self {
        case .male: return 1
        case .female: return 0
        case .neutral: return 0.5
        }
    }
}

struct BodyProfile: Equatable {
    var gender: BodyGender = .neutral
    var age: Int = 28
    var weightKg: Double = 70
    var heightCm: Double = 172

    static let ageRange = 16...90
    /// Weight has no upper limit; the 3D model just stops getting wider past a very high BMI.
    static let minimumWeightKg = 1.0
    static let heightRangeCm = 90.0...250.0

    init(gender: BodyGender = .neutral, age: Int = 28, weightKg: Double = 70, heightCm: Double = 172) {
        self.gender = gender
        self.age = age
        self.weightKg = weightKg
        self.heightCm = heightCm
    }

    /// Builds a profile from the raw values kept in `@AppStorage`, clamping anything out of range.
    init(genderRaw: String, age: Int, weightKg: Double, heightCm: Double) {
        self.init(
            gender: BodyGender(rawValue: genderRaw) ?? .neutral,
            age: min(max(age, BodyProfile.ageRange.lowerBound), BodyProfile.ageRange.upperBound),
            weightKg: max(weightKg, BodyProfile.minimumWeightKg),
            heightCm: min(max(heightCm, BodyProfile.heightRangeCm.lowerBound), BodyProfile.heightRangeCm.upperBound)
        )
    }

    var bmi: Double {
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    /// -1 (very slim) … 0 (average) … +1 (heavy), from BMI.
    var weightFactor: Float {
        let bmi = self.bmi
        if bmi <= 21.5 {
            return Float(max((bmi - 21.5) / (21.5 - 17.0), -1))
        }
        return Float(min((bmi - 21.5) / (32.0 - 21.5), 1))
    }

    /// 0 for a young adult, rising to 1 at age 90.
    var ageFactor: Float {
        Float(min(max(Double(age - 25) / 65.0, 0), 1))
    }

    /// Muscle definition shown on the model, a little higher toward the male end.
    var muscleFactor: Float {
        0.35 + 0.45 * gender.maleShare
    }
}
