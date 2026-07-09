import SwiftUI
import SwiftData

/// Lektions-/Übungsseite (Spec Screen 3) und Fehler-Übungsmodus (Screen 8).
struct LessonSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var session: LessonSession
    @State private var showQuitConfirm = false

    init(mode: SessionMode, content: ContentStore = .shared) {
        _session = State(initialValue: LessonSession(mode: mode, content: content))
    }

    var body: some View {
        Group {
            if session.exercises.isEmpty {
                emptyState
            } else {
                switch session.phase {
                case .active:
                    activeView
                case .finished:
                    LessonResultView(session: session) { dismiss() }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
    }

    // MARK: - Aktive Übung

    private var activeView: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 12)

            ScrollView {
                if let exercise = session.current {
                    exerciseView(exercise)
                        .id(exercise.id)
                        .padding()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            if let feedback = session.feedback {
                FeedbackBanner(feedback: feedback) {
                    withAnimation { session.advance(context: context) }
                }
            }
        }
        .confirmationDialog(
            "Lektion beenden?",
            isPresented: $showQuitConfirm,
            titleVisibility: .visible
        ) {
            Button("Beenden", role: .destructive) { dismiss() }
            Button("Weiterlernen", role: .cancel) {}
        } message: {
            Text("Dein Fortschritt in dieser Lektion geht verloren.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                showQuitConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: session.progress)
                .tint(Theme.accent)
            Text("\(session.index + 1)/\(session.exercises.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func exerciseView(_ exercise: RuntimeExercise) -> some View {
        switch exercise.kind {
        case .multipleChoice(let mc):
            MCExerciseView(exercise: mc) { session.record($0) }
        case .matching(let matching):
            MatchingExerciseView(exercise: matching) { session.record($0) }
        case .textInput(let input):
            TextInputExerciseView(exercise: input) { session.record($0) }
        case .wordOrder(let order):
            WordOrderExerciseView(exercise: order) { session.record($0) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.success)
            Text("Nichts zu üben")
                .font(.headline)
            Text("Diese Übungen sind nicht mehr verfügbar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Schließen") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Feedback

struct FeedbackBanner: View {
    let feedback: LessonSession.Feedback
    let onContinue: () -> Void

    private var color: Color {
        if feedback.correct {
            return feedback.accentHint ? Theme.warning : Theme.success
        }
        return Theme.danger
    }

    private var title: String {
        if feedback.correct {
            return feedback.accentHint ? "Richtig — achte auf die Akzente!" : "Richtig!"
        }
        return "Leider falsch"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: feedback.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(color)

            if !feedback.correct || feedback.accentHint {
                Text("Richtige Antwort: **\(feedback.correctAnswer)**")
                    .font(.subheadline)
            }

            if let explanation = feedback.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(action: onContinue) {
                Text("Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(color).frame(height: 3)
        }
    }
}

// MARK: - Ergebnis (Spec Screen 9)

struct LessonResultView: View {
    let session: LessonSession
    let onDone: () -> Void

    private var summary: LessonSession.Summary { session.summary }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    ProgressRing(
                        progress: summary.score,
                        color: summary.score >= 0.8 ? Theme.success : Theme.warning,
                        lineWidth: 12
                    )
                    .frame(width: 120, height: 120)
                    VStack {
                        Text("\(Int((summary.score * 100).rounded()))%")
                            .font(.title.bold().monospacedDigit())
                        Text("richtig")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 32)

                Text(session.isLessonMode ? "Lektion abgeschlossen!" : "Fehler geübt!")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    resultRow(
                        icon: "checkmark.circle.fill",
                        color: Theme.success,
                        text: "\(summary.correctCount) von \(summary.total) Übungen richtig"
                    )
                    if summary.mistakes > 0 {
                        resultRow(
                            icon: "arrow.counterclockwise.circle.fill",
                            color: Theme.warning,
                            text: "\(summary.mistakes) \(summary.mistakes == 1 ? "Fehler wandert" : "Fehler wandern") in deine Fehlerwiederholung"
                        )
                    }
                    if !summary.newWordsEnrolled.isEmpty {
                        resultRow(
                            icon: "plus.circle.fill",
                            color: Theme.accent,
                            text: "\(summary.newWordsEnrolled.count) neue Wörter im Vokabeltraining"
                        )
                        FlowLayout(spacing: 6) {
                            ForEach(summary.newWordsEnrolled) { item in
                                Text(item.fr)
                                    .font(.footnote)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Theme.accent.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    if let next = summary.nextLessonTitle {
                        resultRow(
                            icon: "lock.open.fill",
                            color: Theme.accent,
                            text: "Freigeschaltet: \(next)"
                        )
                    }
                }
                .card()
                .padding(.horizontal)

                Button {
                    onDone()
                } label: {
                    Text("Fertig")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func resultRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
