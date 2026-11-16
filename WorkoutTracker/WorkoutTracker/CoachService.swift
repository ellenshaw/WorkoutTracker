//
//  CoachService.swift
//  WorkoutTracker
//
//  Talks to the coach backend (which holds the Anthropic API key; the app never does), builds
//  the context the coach gets about the user, and keeps the chat history.
//

import Foundation

// MARK: - Configuration

enum CoachConfig {
    /// A server URL typed into Settings wins; otherwise `CoachBaseURL` from Info.plist (for release builds).
    static var baseURL: URL? {
        let typed = UserDefaults.standard.string(forKey: StorageKey.coachBaseURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let configured = (typed?.isEmpty == false ? typed : nil) ?? Bundle.main.object(forInfoDictionaryKey: "CoachBaseURL") as? String
        guard let configured, !configured.isEmpty, let url = URL(string: configured), url.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return url
    }

    static var appKey: String? {
        let typed = UserDefaults.standard.string(forKey: StorageKey.coachAppKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (typed?.isEmpty == false ? typed : nil) ?? Bundle.main.object(forInfoDictionaryKey: "CoachAppKey") as? String
        return (key?.isEmpty == false) ? key : nil
    }

    /// A random ID for this install, used by the server for fair usage limits. Not tied to the user.
    static var installID: String {
        if let existing = UserDefaults.standard.string(forKey: StorageKey.coachInstallID) { return existing }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: StorageKey.coachInstallID)
        return created
    }
}

// MARK: - Wire format

struct CoachAPIMessage: Codable, Equatable {
    var role: String        // "user" or "assistant"
    var content: String
}

struct CoachReply: Decodable {
    var text: String
    var plan: PlanDraft?
    var refused: Bool?
}

enum CoachError: LocalizedError, Equatable {
    case notConfigured
    case offline
    case limited(String)
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The coach isn't connected to a server yet. Add the server address in Settings → AI coach."
        case .offline:
            return "Couldn't reach the coach. Check your connection and try again."
        case .limited(let message), .server(let message):
            return message
        case .badResponse:
            return "The coach sent a reply the app couldn't read. Please try again."
        }
    }
}

/// What the chat model needs from the network. A protocol so tests can stand in for the server.
protocol CoachTransport {
    func send(messages: [CoachAPIMessage], context: CoachContext) async throws -> CoachReply
}

struct CoachClient: CoachTransport {
    var session: URLSession = .shared

    private struct Body: Encodable {
        var messages: [CoachAPIMessage]
        var context: CoachContext
    }

    private struct ServerError: Decodable {
        var error: String
    }

    func send(messages: [CoachAPIMessage], context: CoachContext) async throws -> CoachReply {
        guard let base = CoachConfig.baseURL else { throw CoachError.notConfigured }

        var request = URLRequest(url: base.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 150   // building a plan can take a while
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(CoachConfig.installID, forHTTPHeaderField: "x-install-id")
        if let key = CoachConfig.appKey { request.setValue(key, forHTTPHeaderField: "x-app-key") }
        request.httpBody = try JSONEncoder().encode(Body(messages: messages, context: context))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CoachError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw CoachError.badResponse }

        switch http.statusCode {
        case 200:
            guard let reply = try? JSONDecoder().decode(CoachReply.self, from: data) else { throw CoachError.badResponse }
            return reply
        case 429:
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
            throw CoachError.limited(message ?? "You've reached the coach's usage limit for now. Please try again later.")
        default:
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
            throw CoachError.server(message ?? "The coach had a problem (\(http.statusCode)). Please try again.")
        }
    }
}

// MARK: - Context about the user

/// What the coach is told about the user. Contains no name, email or account details. Body stats,
/// records and recent workouts are included only when the user allows sharing their history.
struct CoachContext: Encodable, Equatable {
    struct Units: Encodable, Equatable {
        var weight: String
        var height: String
    }
    struct Body: Encodable, Equatable {
        var age: Int
        var weightKg: Double
        var heightCm: Double
    }
    struct Record: Encodable, Equatable {
        var exercise: String
        var weightKg: Double
        var reps: Int
        var estimatedOneRepMaxKg: Double
    }
    struct RecentWorkout: Encodable, Equatable {
        var date: String
        var name: String
        var category: String
        var minutes: Int
        var highlights: [String]
    }
    struct ActivePlan: Encodable, Equatable {
        var title: String
        var week: Int?
        var completedSessions: Int
        var totalSessions: Int
    }

    var today: String
    var weekday: String
    var units: Units
    var body: Body?
    var records: [Record]
    var recentWorkouts: [RecentWorkout]
    var activePlan: ActivePlan?
    var knownExercises: [String]
}

enum CoachContextBuilder {
    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @MainActor
    static func make(workouts store: WorkoutStore,
                     plans: PlanStore,
                     profile: BodyProfile,
                     weightUnit: WeightUnit,
                     heightUnit: HeightUnit,
                     shareHistory: Bool,
                     now: Date = Date()) -> CoachContext {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"

        var context = CoachContext(
            today: dayString(now),
            weekday: weekdayFormatter.string(from: now),
            units: .init(weight: weightUnit.symbol, height: heightUnit.rawValue),
            body: nil,
            records: [],
            recentWorkouts: [],
            activePlan: nil,
            knownExercises: ExerciseLibrary.all.map(\.name)
        )
        guard shareHistory else { return context }

        context.body = .init(age: profile.age,
                             weightKg: (profile.weightKg * 10).rounded() / 10,
                             heightCm: profile.heightCm.rounded())

        context.records = store.allRecords().prefix(15).map {
            .init(exercise: $0.name, weightKg: $0.weightKg, reps: $0.reps,
                  estimatedOneRepMaxKg: (($0.estimatedOneRepMaxKg) * 10).rounded() / 10)
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? .distantPast
        context.recentWorkouts = store.workouts.filter { $0.date >= cutoff }.prefix(12).map { workout -> CoachContext.RecentWorkout in
            let highlights = workout.exercises.prefix(4).map { exercise -> String in
                let top = exercise.sets.max { $0.weightKg < $1.weightKg }
                guard let top else { return exercise.name }
                return "\(exercise.name): \(exercise.sets.count) sets, top \(top.weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg × \(top.reps)"
            }
            return .init(date: dayString(workout.date), name: workout.name, category: workout.category.rawValue,
                         minutes: workout.duration, highlights: highlights)
        }

        if let active = plans.activePlan {
            context.activePlan = .init(title: active.title, week: active.currentWeek(now: now),
                                       completedSessions: active.completedSessions, totalSessions: active.totalSessions)
        }
        return context
    }
}

// MARK: - Chat

struct CoachMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case user, coach }

    var id = UUID()
    var role: Role
    var text: String
    /// Set when the coach created a plan with this message.
    var planID: UUID?
    var date = Date()
}

@MainActor
final class CoachModel: ObservableObject {
    @Published private(set) var messages: [CoachMessage] = []
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private let transport: CoachTransport
    private let fileURL: URL

    init(transport: CoachTransport = CoachClient(), fileURL: URL? = nil) {
        self.transport = transport
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("coach-chat.json")
        load()
    }

    /// Sends a message and waits for the reply. Any plan in the reply is saved to the plan store.
    func send(_ text: String, context: @MainActor () -> CoachContext, plans: PlanStore) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        messages.append(CoachMessage(role: .user, text: String(trimmed.prefix(4000))))
        save()
        await request(context: context, plans: plans)
    }

    /// Tries again after a failure, without repeating the user's message.
    func retry(context: @MainActor () -> CoachContext, plans: PlanStore) async {
        guard !isSending, messages.last?.role == .user else { return }
        await request(context: context, plans: plans)
    }

    func clear() {
        messages = []
        errorMessage = nil
        save()
    }

    // MARK: Internals

    /// The conversation as the server expects it. A plan the coach made is mentioned in a short note
    /// so later answers can refer to it without the whole plan being resent.
    func apiMessages(plans: PlanStore) -> [CoachAPIMessage] {
        messages.suffix(24).map { message in
            switch message.role {
            case .user:
                return CoachAPIMessage(role: "user", content: message.text)
            case .coach:
                var content = message.text
                if let id = message.planID {
                    if let plan = plans.plan(id: id) {
                        content += "\n\n[Plan created: \"\(plan.title)\", \(plan.weeks) weeks, \(plan.totalSessions) sessions]"
                    } else {
                        content += "\n\n[A plan was created here and later removed by the user.]"
                    }
                }
                return CoachAPIMessage(role: "assistant", content: content)
            }
        }
    }

    private func request(context: @MainActor () -> CoachContext, plans: PlanStore) async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let reply = try await transport.send(messages: apiMessages(plans: plans), context: context())
            var planID: UUID?
            if let draft = reply.plan {
                planID = plans.add(draft.makePlan()).id
            }
            messages.append(CoachMessage(role: .coach, text: reply.text, planID: planID))
            save()
        } catch let error as CoachError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = CoachError.offline.errorDescription
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([CoachMessage].self, from: data) {
            messages = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(messages) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
