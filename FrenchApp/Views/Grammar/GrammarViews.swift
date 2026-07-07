import SwiftUI
import SwiftData

/// Grammatik-Übersicht (Spec Screen 5): Themen nach Niveau, nachschlagbar
/// unabhängig vom Lernpfad.
struct GrammarListView: View {
    @Query private var progress: [LessonProgress]

    private let content = ContentStore.shared

    private var snapshot: ProgressSnapshot {
        ProgressSnapshot(progress: progress, content: content)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(content.levels) { level in
                    Section {
                        ForEach(content.grammarRules.filter { $0.level == level }) { rule in
                            NavigationLink(value: rule) {
                                HStack {
                                    Text(rule.title)
                                    Spacer()
                                    if snapshot.isGrammarCovered(rule.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.success)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            LevelBadge(level: level)
                            Text(level.subtitle)
                        }
                    }
                }
            }
            .navigationTitle("Grammatik")
            .navigationDestination(for: GrammarRule.self) { rule in
                GrammarDetailView(rule: rule)
            }
        }
    }
}

/// Grammatik-Detailseite: Erklärung auf Deutsch, Beispiele, typischer Fehler,
/// interaktive Konjugationstabellen, verknüpfte Lektionen.
struct GrammarDetailView: View {
    let rule: GrammarRule

    @Query private var progress: [LessonProgress]
    @State private var selectedTense: Conjugator.Tense = .present

    private let content = ContentStore.shared

    private var snapshot: ProgressSnapshot {
        ProgressSnapshot(progress: progress, content: content)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    LevelBadge(level: rule.level)
                    Spacer()
                }

                Text(.init(rule.explanation))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if !rule.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beispiele")
                            .font(.headline)
                        ForEach(rule.examples, id: \.fr) { example in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(example.fr)
                                    .font(.body.weight(.semibold))
                                Text(example.de)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                if let mistake = rule.typicalMistake {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Typischer Fehler")
                                .font(.subheadline.bold())
                            Text(.init(mistake))
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }

                if let infinitives = rule.verbTables, !infinitives.isEmpty {
                    conjugationSection(infinitives)
                }

                relatedLessons
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(rule.title)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Konjugationstabellen

    private func conjugationSection(_ infinitives: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Konjugation")
                .font(.headline)

            ForEach(infinitives, id: \.self) { infinitive in
                if let verb = content.conjugator.verb(infinitive) {
                    ConjugationTable(verb: verb, conjugator: content.conjugator)
                }
            }
        }
    }

    private var relatedLessons: some View {
        let lessons = content.lessons(covering: rule.id)
        return Group {
            if !lessons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Behandelt in")
                        .font(.headline)
                    ForEach(lessons) { lesson in
                        HStack {
                            Image(systemName: snapshot.isCompleted(lesson.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(snapshot.isCompleted(lesson.id) ? Theme.success : Color.secondary)
                            Text(lesson.title)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
}

/// Konjugationstabelle mit Tempus-Umschalter — direkt aus der Grammatik-Engine.
struct ConjugationTable: View {
    let verb: VerbEntry
    let conjugator: Conjugator

    @State private var tense: Conjugator.Tense = .present

    private var availableTenses: [Conjugator.Tense] {
        Conjugator.Tense.allCases.filter { tense in
            conjugator.form(of: verb, tense: tense, person: 0) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verb.infinitive)
                    .font(.title3.bold())
                Text(verb.de)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(groupLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if availableTenses.count > 1 {
                if availableTenses.count <= 3 {
                    tensePicker.pickerStyle(.segmented)
                } else {
                    HStack {
                        Text("Zeitform")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        tensePicker.pickerStyle(.menu)
                    }
                }
            }

            VStack(spacing: 0) {
                let rows = conjugator.table(for: verb, tense: tense)
                ForEach(rows.indices, id: \.self) { index in
                    HStack {
                        Text(rows[index].pronoun)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(rows[index].form)
                            .font(.body.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .card()
    }

    private var tensePicker: some View {
        Picker("Zeit", selection: $tense) {
            ForEach(availableTenses, id: \.self) { t in
                Text(t.germanLabel).tag(t)
            }
        }
    }

    private var groupLabel: String {
        switch verb.group {
        case 1: return "1. Gruppe (-er)"
        case 2: return "2. Gruppe (-ir)"
        default: return "unregelmäßig"
        }
    }
}
