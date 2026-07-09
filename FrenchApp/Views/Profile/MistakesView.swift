import SwiftUI
import SwiftData

/// Fehler-/Wiederholungsübersicht (Spec Screen 8): automatisch gesammelte
/// falsch beantwortete Übungen, mit „Fehler üben"-Session.
struct MistakesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MistakeRecord.timestamp, order: .reverse) private var mistakes: [MistakeRecord]

    @State private var showPractice = false
    @Query private var settingsList: [UserSettings]

    private var content: ContentStore { settingsList.first?.content ?? .shared }

    /// Nur Fehler des aktiven Kurses (Lektions-IDs sind kursspezifisch).
    private var courseMistakes: [MistakeRecord] {
        mistakes.filter { content.lessonByID[$0.lessonID] != nil }
    }

    private var unresolved: [MistakeRecord] {
        courseMistakes.filter { !$0.isResolved }
    }

    private var resolved: [MistakeRecord] {
        courseMistakes.filter(\.isResolved)
    }

    var body: some View {
        List {
            if unresolved.isEmpty && resolved.isEmpty {
                ContentUnavailableView(
                    "Keine Fehler",
                    systemImage: "checkmark.seal",
                    description: Text("Falsch beantwortete Übungen aus Lektionen landen automatisch hier.")
                )
            }

            if !unresolved.isEmpty {
                Section("Offen (\(unresolved.count))") {
                    ForEach(unresolved, id: \.persistentModelID) { record in
                        mistakeRow(record)
                    }
                    .onDelete { offsets in
                        delete(offsets, from: unresolved)
                    }
                }
            }

            if !resolved.isEmpty {
                Section("Geübt (\(resolved.count))") {
                    ForEach(resolved, id: \.persistentModelID) { record in
                        mistakeRow(record)
                    }
                    .onDelete { offsets in
                        delete(offsets, from: resolved)
                    }
                }
            }
        }
        .navigationTitle("Fehler")
        .safeAreaInset(edge: .bottom) {
            if !unresolved.isEmpty {
                Button {
                    showPractice = true
                } label: {
                    Text("Fehler üben (\(unresolved.count))")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.regularMaterial)
            }
        }
        .fullScreenCover(isPresented: $showPractice) {
            LessonSessionView(mode: .mistakes(unresolved), content: content)
        }
    }

    private func mistakeRow(_ record: MistakeRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.prompt)
                .font(.subheadline)
            HStack {
                Text(record.correctAnswer)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.success)
                Spacer()
                if let lesson = content.lessonByID[record.lessonID] {
                    Text(lesson.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(record.timestamp.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .opacity(record.isResolved ? 0.6 : 1)
    }

    private func delete(_ offsets: IndexSet, from source: [MistakeRecord]) {
        for index in offsets {
            context.delete(source[index])
        }
    }
}
