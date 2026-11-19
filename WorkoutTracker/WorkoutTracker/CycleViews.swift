//
//  CycleViews.swift
//  WorkoutTracker
//
//  Cycle tracking screens, the card on the Workouts tab and the note shown while logging.
//

import SwiftUI

/// A short supportive message shown while logging a strength workout during a period.
struct CycleBanner: View {
    let note: CycleNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "drop.fill")
                .foregroundStyle(.pink)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                Text(note.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.pink.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Today's cycle note on the Workouts tab. Appears only when cycle tracking is turned on.
struct CycleCard: View {
    @EnvironmentObject private var cycle: CycleStore

    var body: some View {
        if cycle.isEnabled {
            NavigationLink {
                CycleSettingsView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Cycle", systemImage: "drop.fill")
                            .font(.headline)
                            .foregroundStyle(.pink)
                        Spacer()
                        if let days = cycle.daysUntilNextPeriod() {
                            Text(nextText(days))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let note = cycle.note() {
                        Text(note.title)
                            .font(.subheadline.weight(.semibold))
                        Text(note.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Log your last period to get cycle notes and an estimate for the next one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .buttonStyle(.plain)
        }
    }

    private func nextText(_ days: Int) -> String {
        switch days {
        case ..<0: return "Period may be late"
        case 0: return "Period expected today"
        case 1: return "Period expected tomorrow"
        default: return "Next period in about \(days) days"
        }
    }
}

struct CycleSettingsView: View {
    @EnvironmentObject private var cycle: CycleStore

    @State private var startDate = Date()

    var body: some View {
        Form {
            Section {
                Toggle("Track my cycle", isOn: $cycle.isEnabled)
            } footer: {
                Text("For people who have periods. Everything stays on this device. It is never shared with the AI coach or anyone else. This is a simple log with estimates from your own dates, not medical advice and not contraception.")
            }

            if cycle.isEnabled {
                Section("Right now") {
                    if let note = cycle.note() {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title).font(.subheadline.weight(.semibold))
                            Text(note.message).font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Log your last period below to get started.")
                            .foregroundStyle(.secondary)
                    }
                    if let next = cycle.predictedNextStart() {
                        LabeledContent("Next period (estimate)", value: next.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent("Average cycle", value: "\(cycle.averageCycleLength()) days")
                }

                Section("Log") {
                    Button("My period started today") { cycle.logPeriodStart(Date()) }

                    DatePicker("Start date", selection: $startDate, in: ...Date(), displayedComponents: .date)
                    Button("Log this start date") { cycle.logPeriodStart(startDate) }

                    if cycle.hasOpenPeriod {
                        Button("My period ended today") { cycle.endPeriod(on: Date()) }
                    }
                }

                Section {
                    Stepper(value: $cycle.typicalCycleDays, in: 21...40) {
                        LabeledContent("Typical cycle", value: "\(cycle.typicalCycleDays) days")
                    }
                    Stepper(value: $cycle.typicalPeriodDays, in: 2...10) {
                        LabeledContent("Typical period", value: "\(cycle.typicalPeriodDays) days")
                    }
                } header: {
                    Text("Typical lengths")
                } footer: {
                    Text("Used until you've logged a few cycles. After that your own average takes over.")
                }

                Section {
                    Toggle("Remind me before my period", isOn: Binding(
                        get: { cycle.remindersEnabled },
                        set: { enabled in
                            if enabled {
                                Task { cycle.remindersEnabled = await cycle.requestReminderPermission() }
                            } else {
                                cycle.remindersEnabled = false
                            }
                        }
                    ))
                } footer: {
                    Text("One quiet reminder the day before. It doesn't mention your cycle on the lock screen.")
                }

                if !cycle.entries.isEmpty {
                    Section("History") {
                        ForEach(cycle.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.start.formatted(date: .abbreviated, time: .omitted))
                                Text(entry.end.map { "Ended \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Still going")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { cycle.entries[$0].id }
                            ids.forEach { cycle.delete($0) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Cycle tracking")
        .navigationBarTitleDisplayMode(.inline)
    }
}
