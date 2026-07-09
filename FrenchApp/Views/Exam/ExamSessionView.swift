import SwiftUI
import SwiftData

/// Niveau-Prüfung im DELF-Stil: Intro mit Regeln, Prüfung mit Zeitlimit
/// und ohne Zwischenfeedback, Auswertung nach Punkteschema am Ende.
struct ExamSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var session: ExamSession
    @State private var showQuitConfirm = false
    /// Antwort der aktuellen Frage — bestätigt erst der neutrale „Weiter"-Knopf.
    @State private var pendingOutcome: AnswerOutcome?
    @State private var remainingSeconds: Int

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(exam: ExamDefinition, content: ContentStore = .shared) {
        let session = ExamSession(exam: exam, content: content)
        _session = State(initialValue: session)
        _remainingSeconds = State(initialValue: exam.durationMinutes * 60)
    }

    var body: some View {
        Group {
            switch session.phase {
            case .intro:
                ExamIntroView(exam: session.exam, direction: session.direction, questionCount: session.questions.count) {
                    session.start()
                } onCancel: {
                    dismiss()
                }
            case .active:
                activeView
            case .finished:
                if let result = session.result {
                    ExamResultView(exam: session.exam, result: result) { dismiss() }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        .onReceive(timer) { _ in
            guard session.phase == .active else { return }
            remainingSeconds = session.remainingSeconds()
            if remainingSeconds <= 0 {
                SpeechService.shared.stop()
                session.expire(context: context)
            }
        }
        .onDisappear { SpeechService.shared.stop() }
    }

    // MARK: - Laufende Prüfung

    private var activeView: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 12)

            ScrollView {
                if let question = session.current {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionBadge(question)
                        if let context = question.context {
                            Text(context)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if question.audioScript != nil {
                            AudioPlayerCard(session: session, question: question)
                        }
                        if let passage = question.passage {
                            PassageCard(title: question.passageTitle, passage: passage)
                        }
                        exerciseView(question)
                            .id(question.id)
                    }
                    .padding()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            if pendingOutcome != nil {
                continueBar
            }
        }
        .confirmationDialog(
            "Prüfung abbrechen?",
            isPresented: $showQuitConfirm,
            titleVisibility: .visible
        ) {
            Button("Abbrechen", role: .destructive) {
                SpeechService.shared.stop()
                dismiss()
            }
            Button("Weitermachen", role: .cancel) {}
        } message: {
            Text("Dieser Versuch wird nicht gewertet.")
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
                .tint(Theme.levelColor(session.exam.level))
            Text("\(session.index + 1)/\(session.questions.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            timerBadge
        }
    }

    private var timerBadge: some View {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        let critical = remainingSeconds <= 300
        return Label(
            String(format: "%d:%02d", minutes, seconds),
            systemImage: "timer"
        )
        .font(.caption.bold().monospacedDigit())
        .foregroundStyle(critical ? Theme.danger : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (critical ? Theme.danger : Color.secondary).opacity(0.12),
            in: Capsule()
        )
    }

    private func sectionBadge(_ question: ExamQuestion) -> some View {
        HStack(spacing: 6) {
            Image(systemName: question.kind.symbol)
            Text("Teil \(question.sectionIndex + 1) · \(question.kind.title)")
        }
        .font(.caption.bold())
        .foregroundStyle(Theme.levelColor(session.exam.level))
    }

    @ViewBuilder
    private func exerciseView(_ question: ExamQuestion) -> some View {
        switch question.exercise.kind {
        case .multipleChoice(let mc):
            MCExerciseView(exercise: mc, revealsSolution: false) { pendingOutcome = $0 }
        case .textInput(let input):
            TextInputExerciseView(exercise: input) { pendingOutcome = $0 }
        case .wordOrder(let order):
            WordOrderExerciseView(exercise: order) { pendingOutcome = $0 }
        case .matching(let matching):
            MatchingExerciseView(exercise: matching) { pendingOutcome = $0 }
        }
    }

    /// Neutraler Weiter-Balken — verrät nicht, ob die Antwort stimmt.
    private var continueBar: some View {
        VStack(spacing: 8) {
            Button {
                guard let outcome = pendingOutcome else { return }
                SpeechService.shared.stop()
                pendingOutcome = nil
                withAnimation { session.record(outcome, context: context) }
            } label: {
                Text(session.index + 1 == session.questions.count ? "Abgeben" : "Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.levelColor(session.exam.level))

            Text("Antwort gespeichert — die Auswertung siehst du am Ende.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial)
    }
}

// MARK: - Audio (Hörverstehen)

struct AudioPlayerCard: View {
    let session: ExamSession
    let question: ExamQuestion

    @State private var isPlaying = false

    private var remainingPlays: Int {
        session.playsRemaining[question.taskKey] ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: play) {
                Image(systemName: isPlaying ? "speaker.wave.3.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(canPlay || isPlaying ? Theme.accent : Color.secondary)
                    .symbolEffect(.pulse, isActive: isPlaying)
            }
            .buttonStyle(.plain)
            .disabled(!canPlay)

            VStack(alignment: .leading, spacing: 3) {
                Text(isPlaying ? "Läuft …" : "Aufnahme abspielen")
                    .font(.subheadline.weight(.semibold))
                Text(playsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .onDisappear { SpeechService.shared.stop() }
    }

    private var canPlay: Bool { remainingPlays > 0 && !isPlaying }

    private var playsLabel: String {
        switch remainingPlays {
        case 0: return isPlaying ? "Letztes Abspielen" : "Kein Abspielen mehr möglich"
        case 1: return "Noch 1× abspielbar"
        default: return "Noch \(remainingPlays)× abspielbar"
        }
    }

    private func play() {
        guard canPlay, let script = question.audioScript else { return }
        session.registerPlay(for: question)
        isPlaying = true
        SpeechService.shared.speak(script, level: session.exam.level, language: session.direction.targetLocaleID) {
            isPlaying = false
        }
    }
}

// MARK: - Lesetext

struct PassageCard: View {
    let title: String?
    let passage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(passage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 4)
        }
    }
}

// MARK: - Intro

struct ExamIntroView: View {
    let exam: ExamDefinition
    var direction: CourseDirection = .french
    let questionCount: Int
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.levelColor(exam.level).opacity(0.14))
                        .frame(width: 96, height: 96)
                    Text(exam.level.rawValue)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Theme.levelColor(exam.level))
                }
                .padding(.top, 32)

                VStack(spacing: 4) {
                    Text("Niveau-Prüfung \(exam.level.rawValue)")
                        .font(.title2.bold())
                    Text("Nach dem Vorbild der offiziellen \(direction.examBrand(for: exam.level))-Prüfung")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(exam.sections.enumerated()), id: \.offset) { index, section in
                        HStack(spacing: 12) {
                            Image(systemName: section.kind.symbol)
                                .frame(width: 28)
                                .foregroundStyle(Theme.levelColor(exam.level))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Teil \(index + 1) · \(section.kind.title)")
                                    .font(.subheadline.weight(.semibold))
                                Text(section.kind.frenchTitle + " · 25 Punkte")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .card()
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    ruleRow(icon: "timer", text: "\(exam.durationMinutes) Minuten Zeit — danach wird automatisch abgegeben.")
                    ruleRow(icon: "questionmark.circle", text: "\(questionCount) Aufgaben, kein Feedback während der Prüfung.")
                    ruleRow(icon: "ear", text: "Jede Höraufnahme kannst du höchstens zweimal abspielen.")
                    ruleRow(icon: "checkmark.seal", text: "Bestanden ab 50 von 100 Punkten, mindestens 5 von 25 in jedem Teil — wie im DELF. Beim ersten Bestehen erhältst du dein Zertifikat.")
                }
                .card()
                .padding(.horizontal)

                Button(action: onStart) {
                    Text("Prüfung starten")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.levelColor(exam.level))
                .padding(.horizontal, 24)

                Button("Noch nicht bereit", action: onCancel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func ruleRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.levelColor(exam.level))
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ergebnis

struct ExamResultView: View {
    let exam: ExamDefinition
    let result: ExamSession.Result
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    ProgressRing(
                        progress: result.total / 100,
                        color: result.passed ? Theme.success : Theme.danger,
                        lineWidth: 12
                    )
                    .frame(width: 130, height: 130)
                    VStack {
                        Text(points(result.total))
                            .font(.title.bold().monospacedDigit())
                        Text("von 100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 32)

                VStack(spacing: 4) {
                    Text(result.passed ? "Bestanden — félicitations !" : "Leider nicht bestanden")
                        .font(.title2.bold())
                    Text(result.passed
                        ? "Du hast die Niveau-Prüfung \(exam.level.rawValue) bestanden."
                        : "Ab 50 Punkten (und 5 je Teil) ist die Prüfung bestanden — du kannst sie jederzeit wiederholen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if result.certificateAwarded {
                    certificateBanner
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    ForEach(result.sections) { section in
                        sectionRow(section)
                    }
                }
                .card()
                .padding(.horizontal)

                if !result.wrongAnswers.isEmpty {
                    wrongAnswersSection
                        .padding(.horizontal)
                }

                Button(action: onDone) {
                    Text("Fertig")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var certificateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Zertifikat \(exam.level.rawValue) erhalten!")
                    .font(.headline)
                Text("Du findest es in deiner Zertifikats-Galerie im Profil.")
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Theme.levelColor(exam.level), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionRow(_ section: ExamSession.SectionResult) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(section.kind.title, systemImage: section.kind.symbol)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(points(section.points)) / 25")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(section.passedMinimum ? Color.primary : Theme.danger)
            }
            ProgressView(value: section.points, total: 25)
                .tint(section.passedMinimum ? Theme.levelColor(exam.level) : Theme.danger)
            if !section.passedMinimum {
                Text("Unter der Mindestpunktzahl von 5")
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var wrongAnswersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Das war falsch (\(result.wrongAnswers.count))")
                .font(.headline)
            ForEach(result.wrongAnswers) { wrong in
                VStack(alignment: .leading, spacing: 3) {
                    Label(wrong.prompt, systemImage: wrong.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(wrong.correctAnswer)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.success)
                    if let user = wrong.userAnswer, !user.isEmpty {
                        Text("Deine Antwort: \(user)")
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .card()
    }

    private func points(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}
