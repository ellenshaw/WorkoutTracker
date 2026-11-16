//
//  CoachChatView.swift
//  WorkoutTracker
//
//  The AI coach chat. Plans the coach creates show up as cards here and in the Plans tab.
//

import SwiftUI

struct CoachChatView: View {
    @EnvironmentObject private var coach: CoachModel
    @EnvironmentObject private var plans: PlanStore
    @EnvironmentObject private var store: WorkoutStore

    @AppStorage(StorageKey.coachConsent) private var consented = false
    @AppStorage(StorageKey.coachShareHistory) private var shareHistory = true
    @AppStorage(StorageKey.weightUnit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(StorageKey.heightUnit) private var heightUnitRaw = HeightUnit.cm.rawValue
    @AppStorage(StorageKey.bodyGender) private var genderRaw = BodyGender.neutral.rawValue
    @AppStorage(StorageKey.bodyAge) private var age = 28
    @AppStorage(StorageKey.bodyWeightKg) private var weightKg = 70.0
    @AppStorage(StorageKey.bodyHeightCm) private var heightCm = 172.0

    @State private var input = ""
    @State private var confirmingClear = false
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Help me add 10 kg to my bench press",
        "Train me for a half marathon in 12 weeks",
        "I want a faster 5K in 8 weeks",
        "Build me a 3-day full-body routine",
        "Plan to improve my deadlift"
    ]

    var body: some View {
        Group {
            if consented {
                chat
            } else {
                ConsentView { consented = true }
            }
        }
        .navigationTitle("AI Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if consented && !coach.messages.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        confirmingClear = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                }
            }
        }
        .confirmationDialog("Start a new conversation?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear conversation", role: .destructive) { coach.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your plans stay in the Plans tab.")
        }
    }

    // MARK: Chat

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if coach.messages.isEmpty {
                        intro
                    }

                    ForEach(coach.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }

                    if coach.isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(thinkingText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .id("thinking")
                    }

                    if let error = coach.errorMessage {
                        errorBanner(error)
                            .id("error")
                    }

                    Text("The coach can make mistakes and isn't a doctor. Check with a professional about injuries or health conditions.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .onChange(of: coach.messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: coach.isSending) { _, _ in scrollToEnd(proxy) }
            .onChange(of: coach.errorMessage) { _, _ in scrollToEnd(proxy) }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var thinkingText: String {
        coach.messages.last?.role == .user && coach.messages.count > 1
            ? "Coach is thinking… building a plan can take up to a minute"
            : "Coach is thinking…"
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent.opacity(0.18))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your training coach")
                        .font(.headline)
                    Text("Tell me a goal and I'll build a plan you can follow and track.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Try asking")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        submit(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            if coach.messages.last?.role == .user {
                Button("Try again") {
                    Task { @MainActor in
                        await coach.retry(context: { makeContext() }, plans: plans)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message your coach", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                submit(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? Theme.accent : Color.secondary.opacity(0.4))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !coach.isSending
    }

    // MARK: Actions

    private func submit(_ text: String) {
        guard !coach.isSending else { return }
        input = ""
        inputFocused = false
        Task { @MainActor in
            await coach.send(text, context: { makeContext() }, plans: plans)
        }
    }

    @MainActor
    private func makeContext() -> CoachContext {
        CoachContextBuilder.make(
            workouts: store,
            plans: plans,
            profile: BodyProfile(genderRaw: genderRaw, age: age, weightKg: weightKg, heightCm: heightCm),
            weightUnit: WeightUnit(rawValue: unitRaw) ?? .kg,
            heightUnit: HeightUnit(rawValue: heightUnitRaw) ?? .cm,
            shareHistory: shareHistory
        )
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if coach.errorMessage != nil {
                proxy.scrollTo("error", anchor: .bottom)
            } else if coach.isSending {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = coach.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Messages

private struct MessageRow: View {
    let message: CoachMessage

    @EnvironmentObject private var plans: PlanStore

    private var isUser: Bool { message.role == .user }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            Text(attributed)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Theme.accent : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 320, alignment: isUser ? .trailing : .leading)
                .textSelection(.enabled)

            if let planID = message.planID {
                PlanCard(planID: planID)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

/// A tappable summary of a plan the coach created.
private struct PlanCard: View {
    let planID: UUID
    @EnvironmentObject private var plans: PlanStore

    var body: some View {
        if let plan = plans.plan(id: planID) {
            NavigationLink {
                PlanDetailView(planID: planID)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent.opacity(0.18))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Text("\(plan.weeks) weeks · \(plan.totalSessions) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(statusText(plan))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func statusText(_ plan: TrainingPlan) -> String {
        switch plan.status {
        case .proposed: return "Review and start it"
        case .active: return "In progress"
        case .completed: return "Completed"
        case .archived: return "Stopped"
        }
    }
}

// MARK: - First-use consent

/// Explains what the coach receives before anything is sent.
struct ConsentView: View {
    let onAllow: () -> Void

    @AppStorage(StorageKey.coachShareHistory) private var shareHistory = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)

                Text("Meet your AI coach")
                    .font(.title.bold())

                Text("Ask for a plan, a PR program or race prep and the coach builds it around you. Plans appear in the Plans tab, where you can start one and track your progress.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Your messages are sent to an AI service (Anthropic's Claude) through this app's server to write replies.", systemImage: "paperplane")
                    Label("No name, email or account details are sent.", systemImage: "person.crop.circle.badge.minus")
                    Label("The coach is an AI. It can make mistakes and isn't a doctor.", systemImage: "exclamationmark.triangle")
                }
                .font(.subheadline)

                Toggle(isOn: $shareHistory) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share my training info")
                            .font(.subheadline.weight(.semibold))
                        Text("Age, weight, height, personal records and recent workouts, so plans fit you. You can change this later in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button("Continue", action: onAllow)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}
