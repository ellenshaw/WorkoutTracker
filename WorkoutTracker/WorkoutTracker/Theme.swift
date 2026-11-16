//
//  Theme.swift
//  WorkoutTracker
//

import SwiftUI

enum StorageKey {
    static let isLoggedIn = "isLoggedIn"
    static let userName = "userName"
    static let appearance = "appearance"
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Theme {
    /// Electric blue: reads well in light and dark and stays out of the yellow/orange/red heat palette.
    static let accent = Color(red: 0.30, green: 0.56, blue: 1.0)
}

extension View {
    /// Rounded card that adapts to light / dark mode.
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.accent.opacity(isEnabled ? 1 : 0.35))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
