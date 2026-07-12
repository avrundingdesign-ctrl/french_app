import SwiftUI
import SwiftData

/// Einstellungen (Spec Screen 7): Tagespensum, Erscheinungsbild,
/// Datenexport und Zurücksetzen — bewusst ohne Streak-Optionen.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query private var states: [ReviewState]
    @Query private var progress: [LessonProgress]
    @Query private var mistakes: [MistakeRecord]
    @Query private var reviewLog: [ReviewLogEntry]

    @AppStorage("appearance") private var appearance = "system"
    @State private var confirmSRSReset = false
    @State private var confirmFullReset = false

    var body: some View {
        Form {
            if let settings = settingsList.first {
                courseSection(settings)
                trainingSection(settings)
                certificateSection(settings)
            }

            Section("Erscheinungsbild") {
                Picker("Design", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Hell").tag("light")
                    Text("Dunkel").tag("dark")
                }
            }

            Section("Daten") {
                ShareLink(item: exportJSON(), preview: SharePreview("Français-Fortschritt")) {
                    Label("Fortschritt exportieren (JSON)", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    confirmSRSReset = true
                } label: {
                    Label("Vokabeltraining zurücksetzen", systemImage: "arrow.counterclockwise")
                }

                Button(role: .destructive) {
                    confirmFullReset = true
                } label: {
                    Label("Gesamten Fortschritt löschen", systemImage: "trash")
                }
            }

            Section("Über") {
                LabeledContent("Version", value: appVersion)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Methodik")
                        .font(.subheadline.bold())
                    Text("Wiederholungen plant der SM-2-Algorithmus (SuperMemo, Woźniak 1987). Konjugationen erzeugt eine regelbasierte Grammatik-Engine; alle Lerninhalte sind redaktionell für diese App erstellt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("Rechtliches & Support") {
                Link(destination: URL(string: "https://trin.studio/datenschutz.html")!) {
                    Label("Datenschutzerklärung", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://trin.studio/impressum.html")!) {
                    Label("Impressum", systemImage: "doc.text")
                }
                Link(destination: URL(string: "mailto:c.hesse@trin.studio")!) {
                    Label("Support kontaktieren", systemImage: "envelope")
                }
            }
        }
        .navigationTitle("Einstellungen")
        .confirmationDialog(
            "Vokabeltraining zurücksetzen?",
            isPresented: $confirmSRSReset,
            titleVisibility: .visible
        ) {
            Button("Zurücksetzen", role: .destructive) { resetSRS() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Wiederholungsdaten (\(states.count) Karten) werden gelöscht. Lektionsfortschritt bleibt erhalten.")
        }
        .confirmationDialog(
            "Gesamten Fortschritt löschen?",
            isPresented: $confirmFullReset,
            titleVisibility: .visible
        ) {
            Button("Alles löschen", role: .destructive) { resetAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Lektionen, Vokabeltraining und Fehlerprotokoll werden unwiderruflich gelöscht.")
        }
    }

    private func courseSection(_ settings: UserSettings) -> some View {
        Section {
            Picker("Kurs", selection: Binding(
                get: { settings.courseDirection },
                set: { settings.courseDirection = $0 }
            )) {
                ForEach(CourseDirection.allCases) { direction in
                    Text("\(direction.flag) \(direction.targetLanguageName) lernen").tag(direction)
                }
            }
        } header: {
            Text("Kurs")
        } footer: {
            Text("Der Wechsel ist verlustfrei: Lernstand, Lektionen und Zertifikate des anderen Kurses bleiben gespeichert und erscheinen wieder, sobald du zurückwechselst.")
        }
    }

    private func trainingSection(_ settings: UserSettings) -> some View {
        Section {
            Stepper(value: Binding(
                get: { settings.newCardsPerDay },
                set: { settings.newCardsPerDay = $0 }
            ), in: 1...50) {
                LabeledContent("Neue Karten pro Tag", value: "\(settings.newCardsPerDay)")
            }
        } header: {
            Text("Tägliches Pensum")
        } footer: {
            Text("Bestimmt, wie viele neue Wörter pro Tag zusätzlich zu den fälligen Wiederholungen ins Training kommen.")
        }
    }

    private func certificateSection(_ settings: UserSettings) -> some View {
        Section {
            TextField("Dein Name", text: Binding(
                get: { settings.certificateName },
                set: { settings.certificateName = $0 }
            ))
            .textInputAutocapitalization(.words)
        } header: {
            Text("Name auf Zertifikaten")
        } footer: {
            Text("Erscheint auf deinen Zertifikaten nach bestandener Niveau-Prüfung. Ohne Namen steht dort «Apprenant·e de français».")
        }
    }

    // MARK: - Aktionen

    private func resetSRS() {
        for state in states { context.delete(state) }
        for entry in reviewLog { context.delete(entry) }
    }

    private func resetAll() {
        for state in states { context.delete(state) }
        for entry in reviewLog { context.delete(entry) }
        for item in progress { context.delete(item) }
        for mistake in mistakes { context.delete(mistake) }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        return version
    }

    // MARK: - Export

    private struct ExportData: Encodable {
        struct Review: Encodable {
            let vocabID: String
            let easeFactor: Double
            let repetitions: Int
            let interval: Int
            let nextReview: Date
        }

        struct Lesson: Encodable {
            let lessonID: String
            let completedAt: Date
            let bestScore: Double
        }

        let exportedAt: Date
        let reviews: [Review]
        let lessons: [Lesson]
    }

    private func exportJSON() -> String {
        let data = ExportData(
            exportedAt: .now,
            reviews: states.map {
                ExportData.Review(
                    vocabID: $0.vocabID,
                    easeFactor: $0.easeFactor,
                    repetitions: $0.repetitions,
                    interval: $0.interval,
                    nextReview: $0.nextReview
                )
            },
            lessons: progress.map {
                ExportData.Lesson(
                    lessonID: $0.lessonID,
                    completedAt: $0.completedAt,
                    bestScore: $0.bestScore
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(data),
              let string = String(data: encoded, encoding: .utf8)
        else { return "{}" }
        return string
    }
}
