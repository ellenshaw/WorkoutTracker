//
//  ProgressViews.swift
//  WorkoutTracker
//
//  Progress charts: for each exercise, your estimated one-rep max, heaviest weight and total
//  volume workout by workout, plus total volume across all strength workouts.
//

import SwiftUI
import Charts

/// One exercise in one workout.
struct ExercisePoint: Identifiable, Hashable {
    let id: UUID                 // the workout
    let date: Date
    /// Best estimated one-rep max among the sets (0 when no weight was used).
    let oneRepMaxKg: Double
    /// Heaviest weight lifted in the workout.
    let maxWeightKg: Double
    /// Sets × reps × weight, added up.
    let volumeKg: Double
    let sets: Int
    let topSetReps: Int
    let cyclePhase: String

    var onPeriod: Bool { cyclePhase == CyclePhase.menstrual.rawValue }
}

struct WorkoutVolumePoint: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let name: String
    let volumeKg: Double
    let cyclePhase: String

    var onPeriod: Bool { cyclePhase == CyclePhase.menstrual.rawValue }
}

extension WorkoutStore {
    /// Every workout that included this exercise, oldest first.
    func history(for exerciseID: String) -> [ExercisePoint] {
        workouts.reversed().compactMap { workout -> ExercisePoint? in
            let matches = workout.exercises.filter { $0.exerciseID == exerciseID }
            guard !matches.isEmpty else { return nil }
            let sets = matches.flatMap(\.sets).filter { $0.reps > 0 }
            guard !sets.isEmpty else { return nil }

            let best = sets.max {
                PersonalRecord.estimateOneRepMax(weightKg: $0.weightKg, reps: $0.reps)
                    < PersonalRecord.estimateOneRepMax(weightKg: $1.weightKg, reps: $1.reps)
            }
            return ExercisePoint(
                id: workout.id,
                date: workout.date,
                oneRepMaxKg: sets.map { $0.weightKg > 0 ? PersonalRecord.estimateOneRepMax(weightKg: $0.weightKg, reps: $0.reps) : 0 }.max() ?? 0,
                maxWeightKg: sets.map(\.weightKg).max() ?? 0,
                volumeKg: sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) },
                sets: sets.count,
                topSetReps: best?.reps ?? 0,
                cyclePhase: workout.cyclePhase
            )
        }
    }

    /// Exercises that have been logged, with how often and the best estimated one-rep max.
    func loggedExercises() -> [(id: String, name: String, workouts: Int, best1RMKg: Double)] {
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        for workout in workouts {
            for exercise in workout.exercises {
                names[exercise.exerciseID] = exercise.name
                counts[exercise.exerciseID, default: 0] += 1
            }
        }
        return counts.keys.map { id in
            (id: id, name: names[id] ?? id, workouts: counts[id] ?? 0,
             best1RMKg: history(for: id).map(\.oneRepMaxKg).max() ?? 0)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Total volume of each strength workout, oldest first.
    func workoutVolumes() -> [WorkoutVolumePoint] {
        workouts.reversed().compactMap { workout in
            guard !workout.exercises.isEmpty else { return nil }
            return WorkoutVolumePoint(id: workout.id, date: workout.date, name: workout.name,
                                      volumeKg: workout.totalVolumeKg, cyclePhase: workout.cyclePhase)
        }
    }
}

// MARK: - Overview

struct ProgressListView: View {
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        let volumes = store.workoutVolumes()
        let exercises = store.loggedExercises()

        List {
            if volumes.isEmpty {
                ContentUnavailableView("No progress yet", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Log a strength workout and your charts show up here."))
                    .listRowBackground(Color.clear)
            } else {
                Section("Total volume per workout") {
                    VolumeChart(points: volumes, unit: unit)
                        .frame(height: 190)
                        .padding(.vertical, 6)
                }

                Section("Exercises") {
                    ForEach(exercises, id: \.id) { item in
                        NavigationLink {
                            ExerciseProgressView(exerciseID: item.id, title: item.name)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text("\(item.workouts) workout\(item.workouts == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.best1RMKg > 0 {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(unit.format(kg: item.best1RMKg)) \(unit.symbol)")
                                            .font(.subheadline.weight(.semibold))
                                            .monospacedDigit()
                                        Text("best est. 1RM")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VolumeChart: View {
    let points: [WorkoutVolumePoint]
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart(points) { point in
                BarMark(x: .value("Date", point.date, unit: .day),
                        y: .value("Volume", unit.fromKg(point.volumeKg)))
                    .foregroundStyle(point.onPeriod ? Color.pink : Theme.accent)
            }
            .chartYAxisLabel(unit.symbol)

            if points.contains(where: \.onPeriod) {
                PeriodLegend()
            }
        }
    }
}

/// Explains pink marks on a chart: workouts logged during a period.
struct PeriodLegend: View {
    var body: some View {
        Label("Pink: logged during your period", systemImage: "circle.fill")
            .font(.caption2)
            .foregroundStyle(.pink)
    }
}

// MARK: - One exercise

struct ExerciseProgressView: View {
    let exerciseID: String
    let title: String

    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue
    @State private var metric = Metric.oneRepMax

    enum Metric: String, CaseIterable, Identifiable {
        case oneRepMax = "Est. 1RM"
        case maxWeight = "Max weight"
        case volume = "Volume"

        var id: String { rawValue }
    }

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private func value(_ point: ExercisePoint) -> Double {
        switch metric {
        case .oneRepMax: return point.oneRepMaxKg
        case .maxWeight: return point.maxWeightKg
        case .volume: return point.volumeKg
        }
    }

    var body: some View {
        let all = store.history(for: exerciseID)
        // Bodyweight sets have no weight to chart, so leave out points with nothing to show.
        let points = all.filter { value($0) > 0 }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                if points.isEmpty {
                    ContentUnavailableView("Nothing to chart yet", systemImage: "chart.xyaxis.line",
                                           description: Text("Log this exercise with a weight and it shows up here."))
                } else {
                    summary(points)

                    VStack(alignment: .leading, spacing: 8) {
                        Chart(points) { point in
                            LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, unit.fromKg(value(point))))
                                .foregroundStyle(Theme.accent)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, unit.fromKg(value(point))))
                                .foregroundStyle(point.onPeriod ? Color.pink : Theme.accent)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxisLabel(unit.symbol)
                        .frame(height: 230)

                        if points.contains(where: \.onPeriod) {
                            PeriodLegend()
                        }
                    }
                    .cardStyle()

                    sessions(all.reversed())
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(_ points: [ExercisePoint]) -> some View {
        let values = points.map(value)
        let best = values.max() ?? 0
        let latest = values.last ?? 0
        let first = values.first ?? 0
        let change = first > 0 ? (latest - first) / first * 100 : 0

        return HStack(spacing: 12) {
            statCard("Best", "\(unit.format(kg: best)) \(unit.symbol)")
            statCard("Latest", "\(unit.format(kg: latest)) \(unit.symbol)")
            statCard("Change", points.count > 1 ? String(format: "%+.0f%%", change) : "–",
                     color: change > 0 ? .green : (change < 0 ? .secondary : .primary))
        }
    }

    private func statCard(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func sessions(_ points: [ExercisePoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workouts")
                .font(.headline)
            ForEach(points) { point in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                        Text("\(point.sets) sets · top \(unit.format(kg: point.maxWeightKg)) \(unit.symbol) × \(point.topSetReps)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("1RM \(unit.format(kg: point.oneRepMaxKg))")
                            .font(.caption)
                        Text("Vol \(unit.format(kg: point.volumeKg))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                if point.id != points.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
