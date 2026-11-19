//
//  WorkoutResultView.swift
//  WorkoutTracker
//
//  Shown right after logging a workout (isNew) and when opening one from history.
//

import SwiftUI

struct WorkoutResultView: View {
    let workout: Workout
    var isNew = false
    var onDone: () -> Void = {}

    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(StorageKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.km.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var isPinned: Bool {
        store.workouts.first(where: { $0.id == workout.id })?.isPinned ?? false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                HeatBodyCard(heat: workout.heat)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Muscles worked")
                        .font(.headline)
                    MuscleBreakdownList(heat: workout.heat)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                if (workout.distanceKm ?? 0) > 0 {
                    cardioCard
                }

                if !workout.exercises.isEmpty {
                    exercisesCard
                }

                if !workout.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.headline)
                        Text(workout.notes)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isNew ? "Workout logged" : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isNew)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.togglePin(workout.id)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(isPinned ? "Unpin workout" : "Pin workout")
            }
            if isNew {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .km }

    private var cardioCard: some View {
        let km = workout.distanceKm ?? 0
        let style = ActivityMetrics.paceStyle(for: workout.activityName)
        let distanceText = ActivityMetrics.usesShortDistance(workout.activityName)
            ? "\(Int(distanceUnit.fromKmShort(km).rounded())) \(distanceUnit.shortSymbol)"
            : "\(distanceUnit.format(km: km)) \(distanceUnit.symbol)"
        let pace = workout.paceSecondsPerKm.map { PaceFormat.format(secondsPerKm: $0, style: style, unit: distanceUnit) } ?? "–"
        let badges = CardioRecords.badges(for: workout, among: store.workouts)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                cardioStat(distanceText, "Distance")
                Divider().frame(height: 34)
                cardioStat(PaceFormat.clock(Double(workout.elapsedSeconds)), "Time")
                Divider().frame(height: 34)
                cardioStat(pace, style == .speed ? "Speed" : "Pace")
            }

            if !badges.isEmpty {
                HStack(spacing: 8) {
                    ForEach(badges, id: \.rawValue) { kind in
                        Label(kind.title, systemImage: "trophy.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.25))
                            .foregroundStyle(Color.yellow)
                            .clipShape(Capsule())
                    }
                }
            }

            if !workout.route.isEmpty {
                RouteMapView(route: workout.route)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func cardioStat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Exercises")
                    .font(.headline)
                Spacer()
                Text("\(unit.format(kg: workout.totalVolumeKg)) \(unit.symbol) total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(workout.exercises) { exercise in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        if store.isPersonalRecord(exercise, in: workout) {
                            Label("PR", systemImage: "trophy.fill")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.25))
                                .foregroundStyle(Color.yellow)
                                .clipShape(Capsule())
                                .accessibilityLabel("New personal record")
                        }
                    }

                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(unit.format(kg: set.weightKg)) \(unit.symbol) × \(set.reps)")
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.category.icon)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.18))
                .foregroundStyle(Theme.accent)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.title3.weight(.semibold))
                Text("\(workout.category.rawValue) · \(workout.duration) min")
                    .foregroundStyle(.secondary)
                if !workout.variantText.isEmpty {
                    Text(workout.variantText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
