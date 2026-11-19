//
//  CycleStore.swift
//  WorkoutTracker
//
//  Optional period tracking for people who have periods. Everything stays on the device: it is
//  never sent to the AI coach, shared or uploaded. It is a simple log of period start and end
//  dates, with estimates built from those dates. Not for contraception or medical use.
//

import Foundation
import UserNotifications

enum CyclePhase: String, Codable {
    case menstrual, follicular, ovulation, luteal

    var title: String {
        switch self {
        case .menstrual: return "Period"
        case .follicular: return "Follicular phase"
        case .ovulation: return "Mid-cycle"
        case .luteal: return "Luteal phase"
        }
    }
}

struct PeriodEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Date
    /// Nil while the period is still going.
    var end: Date?
}

/// A short, supportive message about training for where the person is in their cycle.
struct CycleNote: Equatable {
    enum Kind { case period, expectedSoon, general }

    var kind: Kind
    var title: String
    var message: String
}

@MainActor
final class CycleStore: ObservableObject {
    /// Newest first.
    @Published private(set) var entries: [PeriodEntry] = []

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled); rescheduleReminder() }
    }
    @Published var typicalCycleDays: Int {
        didSet { defaults.set(typicalCycleDays, forKey: Keys.cycleDays); rescheduleReminder() }
    }
    @Published var typicalPeriodDays: Int {
        didSet { defaults.set(typicalPeriodDays, forKey: Keys.periodDays) }
    }
    @Published var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Keys.reminders); rescheduleReminder() }
    }

    enum Keys {
        static let enabled = "cycleTrackingEnabled"
        static let cycleDays = "cycleTypicalDays"
        static let periodDays = "cyclePeriodDays"
        static let reminders = "cycleRemindersEnabled"
    }

    private let fileURL: URL
    private let defaults: UserDefaults
    private let notifications: Bool

    /// - Parameter notifications: tests turn this off so nothing is scheduled on the real device.
    init(fileURL: URL? = nil, defaults: UserDefaults = .standard, notifications: Bool = true) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cycle.json")
        self.defaults = defaults
        self.notifications = notifications

        isEnabled = defaults.bool(forKey: Keys.enabled)
        typicalCycleDays = defaults.object(forKey: Keys.cycleDays) as? Int ?? 28
        typicalPeriodDays = defaults.object(forKey: Keys.periodDays) as? Int ?? 5
        remindersEnabled = defaults.bool(forKey: Keys.reminders)
        load()
    }

    // MARK: Logging

    /// Records that a period started. Replaces an entry that starts on the same day.
    func logPeriodStart(_ date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        entries.removeAll { calendar.isDate($0.start, inSameDayAs: day) }
        entries.append(PeriodEntry(start: day))
        sortAndSave()
    }

    /// Marks the most recent period as ended on a date.
    func endPeriod(on date: Date, calendar: Calendar = .current) {
        guard let index = entries.firstIndex(where: { $0.end == nil }) else { return }
        let day = calendar.startOfDay(for: date)
        guard day >= entries[index].start else { return }
        entries[index].end = day
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        sortAndSave()
    }

    func removeAll() {
        entries = []
        isEnabled = false
        remindersEnabled = false
        save()
    }

    var hasOpenPeriod: Bool { entries.first?.end == nil && !entries.isEmpty }

    // MARK: Estimates

    /// Average days from one period start to the next, from the last few cycles. Falls back to the
    /// typical length when there isn't enough history, and ignores gaps that look like missed logs.
    func averageCycleLength() -> Int {
        let starts = entries.map(\.start)
        guard starts.count >= 2 else { return typicalCycleDays }
        let calendar = Calendar.current
        var gaps: [Int] = []
        for i in 0..<min(starts.count - 1, 6) {
            let gap = calendar.dateComponents([.day], from: starts[i + 1], to: starts[i]).day ?? 0
            if (18...60).contains(gap) { gaps.append(gap) }
        }
        guard !gaps.isEmpty else { return typicalCycleDays }
        return Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
    }

    /// Average length of logged periods, or the typical length.
    func averagePeriodLength() -> Int {
        let calendar = Calendar.current
        let lengths = entries.compactMap { entry -> Int? in
            guard let end = entry.end else { return nil }
            let days = (calendar.dateComponents([.day], from: entry.start, to: end).day ?? 0) + 1
            return (1...14).contains(days) ? days : nil
        }.prefix(6)
        guard !lengths.isEmpty else { return typicalPeriodDays }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    private func latestEntry(onOrBefore date: Date, calendar: Calendar) -> PeriodEntry? {
        let day = calendar.startOfDay(for: date)
        return entries.first { $0.start <= day }
    }

    /// Day 1 is the first day of the most recent period.
    func cycleDay(on date: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard isEnabled, let entry = latestEntry(onOrBefore: date, calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: entry.start, to: calendar.startOfDay(for: date)).day ?? 0
        return days + 1
    }

    func phase(on date: Date = Date(), calendar: Calendar = .current) -> CyclePhase? {
        guard let day = cycleDay(on: date, calendar: calendar),
              let entry = latestEntry(onOrBefore: date, calendar: calendar) else { return nil }

        let length = averageCycleLength()
        // Far past when the next period should have started: the data is probably out of date.
        if day > length + 14 { return nil }

        let periodDays: Int
        if let end = entry.end {
            periodDays = (calendar.dateComponents([.day], from: entry.start, to: end).day ?? 0) + 1
        } else {
            periodDays = averagePeriodLength()
        }
        if day <= periodDays { return .menstrual }

        let ovulationDay = max(length - 14, periodDays + 2)
        if day < ovulationDay - 1 { return .follicular }
        if day <= ovulationDay + 1 { return .ovulation }
        return .luteal
    }

    /// When the next period is expected, based on the last start and the average cycle length.
    func predictedNextStart(calendar: Calendar = .current) -> Date? {
        guard isEnabled, let last = entries.first else { return nil }
        return calendar.date(byAdding: .day, value: averageCycleLength(), to: last.start)
    }

    /// Whole days until the expected next period (negative when it's late).
    func daysUntilNextPeriod(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let next = predictedNextStart(calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: next).day
    }

    // MARK: Messages

    /// A note worth showing today, or nil when there's nothing useful to say.
    func note(on date: Date = Date(), calendar: Calendar = .current) -> CycleNote? {
        guard let phase = phase(on: date, calendar: calendar), let day = cycleDay(on: date, calendar: calendar) else { return nil }

        switch phase {
        case .menstrual:
            return CycleNote(
                kind: .period,
                title: "Period · day \(day)",
                message: "It's okay to lift lighter, do fewer sets, or take a rest day. Strength and energy often dip, and that's normal. Listen to your body."
            )
        case .luteal:
            if let until = daysUntilNextPeriod(now: date, calendar: calendar), until <= 2 {
                return CycleNote(
                    kind: .expectedSoon,
                    title: "Period expected soon",
                    message: "Some people feel more tired or find training harder just before their period. If that's you, easing off is fine."
                )
            }
            return CycleNote(kind: .general, title: "Day \(day) · luteal phase",
                             message: "Energy can vary at this point in the cycle. Train by feel; heavier or lighter are both fine.")
        case .follicular:
            return CycleNote(kind: .general, title: "Day \(day) · follicular phase",
                             message: "Many people feel their energy building now. If you feel good, it can be a good time to push.")
        case .ovulation:
            return CycleNote(kind: .general, title: "Day \(day) · mid-cycle",
                             message: "Plenty of people feel strong around now, and some don't. Warm up well and go by how you feel.")
        }
    }

    // MARK: Reminders

    /// One quiet reminder the day before the expected period. The wording is generic on purpose
    /// so nothing personal shows on a lock screen.
    func rescheduleReminder() {
        guard notifications else { return }
        let center = UNUserNotificationCenter.current()
        let identifier = "cycle.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled, remindersEnabled, let next = predictedNextStart() else { return }

        let calendar = Calendar.current
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: next) else { return }
        var components = calendar.dateComponents([.year, .month, .day], from: dayBefore)
        components.hour = 9
        guard let fireDate = calendar.date(from: components), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Workout Tracker"
        content.body = "A heads-up for the next few days: it's fine to train lighter if you want to. Tap for details."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// Asks permission the first time reminders are turned on. Returns whether they're allowed.
    func requestReminderPermission() async -> Bool {
        guard notifications else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: Persistence

    private func sortAndSave() {
        entries.sort { $0.start > $1.start }
        save()
        rescheduleReminder()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([PeriodEntry].self, from: data) {
            entries = decoded.sorted { $0.start > $1.start }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
