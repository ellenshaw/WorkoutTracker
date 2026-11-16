//
//  AddWorkoutView.swift
//  WorkoutTracker
//
//  The "new workout" flow: pick a category tile, log it, then see the 3D muscle map.
//

import SwiftUI

/// Identifies one presentation of the logging sheet (optionally started from a pinned workout).
struct LogSession: Identifiable {
    let id = UUID()
    var template: Workout?
}

enum LogRoute: Hashable {
    case strength(Workout?)
    case activity(WorkoutCategory, Workout?)
    case result(Workout)
}

struct AddWorkoutView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var path: [LogRoute]

    init(template: Workout? = nil) {
        var initial: [LogRoute] = []
        if let template {
            initial = [template.category == .strength
                       ? .strength(template)
                       : .activity(template.category, template)]
        }
        _path = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack(path: $path) {
            CategoryPickerView(onCancel: { dismiss() })
                .navigationDestination(for: LogRoute.self) { route in
                    destination(for: route)
                }
        }
        // Swiping the sheet away would silently throw away a half-logged workout.
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func destination(for route: LogRoute) -> some View {
        switch route {
        case .strength(let template):
            LogStrengthView(template: template, onCancel: { dismiss() }, onSave: finish)
        case .activity(let category, let template):
            LogActivityView(category: category, template: template, onCancel: { dismiss() }, onSave: finish)
        case .result(let workout):
            WorkoutResultView(workout: workout, isNew: true) { dismiss() }
        }
    }

    private func finish(_ workout: Workout) {
        store.add(workout)
        path = [.result(workout)]
    }
}

// MARK: - Category tiles

struct CategoryPickerView: View {
    let onCancel: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What did you do?")
                    .font(.title2.bold())

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(WorkoutCategory.allCases) { category in
                        NavigationLink(value: route(for: category)) {
                            CategoryTile(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("New Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    private func route(for category: WorkoutCategory) -> LogRoute {
        category == .strength ? .strength(nil) : .activity(category, nil)
    }
}

private struct CategoryTile: View {
    let category: WorkoutCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: category.icon)
                .font(.title2)
                .foregroundStyle(category.tint)
                .frame(width: 46, height: 46)
                .background(category.tint.opacity(0.18))
                .clipShape(Circle())
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text(category.rawValue)
                .font(.headline)
            Text(category.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
