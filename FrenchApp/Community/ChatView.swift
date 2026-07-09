import SwiftUI

/// Tandem-Chat: Du schreibst und liest in deiner Lernsprache.
/// Nachrichten des Partners (in seiner Lernsprache = deiner Muttersprache)
/// werden on-device übersetzt — das Original ist per Tipp einsehbar.
struct ChatView: View {
    let service: CommunityService
    let profile: CommunityProfile
    let partner: CommunityProfile
    let match: TandemMatch

    @State private var messages: [ChatMessage] = []
    @State private var translations: [String: String] = [:]
    @State private var showOriginal: Set<String> = []
    @State private var input = ""
    @State private var sending = false

    private let refreshTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            languageBanner

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(partner.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onReceive(refreshTimer) { _ in
            Task { await reload() }
        }
        .background {
            ChatTranslationBridge(messages: messages, viewer: profile, translations: $translations)
        }
    }

    private var languageBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.caption)
            Text("Du schreibst auf \(profile.learningLanguage.label) — \(partner.displayName) liest alles auf \(partner.learningLanguage.label).")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private func reload() async {
        if let latest = try? await service.messages(for: match) {
            if latest != messages {
                messages = latest
            }
        }
    }

    // MARK: - Nachrichten-Blase

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        let isMine = message.senderProfileID == profile.id
        let needsTranslation = ChatDisplay.needsTranslation(message, for: profile)
        let translated = translations[message.id]

        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                if needsTranslation, let translated, !showOriginal.contains(message.id) {
                    Text(translated)
                    Label("übersetzt · Original zeigen", systemImage: "globe")
                        .font(.caption2)
                        .opacity(0.7)
                } else {
                    Text(message.text)
                    if needsTranslation, translated != nil {
                        Label("Original · Übersetzung zeigen", systemImage: "globe")
                            .font(.caption2)
                            .opacity(0.7)
                    } else if needsTranslation, !ChatTranslationBridge.isSupported {
                        Label("Übersetzung ab iOS 18", systemImage: "info.circle")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isMine ? Theme.accent : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .foregroundStyle(isMine ? .white : .primary)
            .onTapGesture {
                guard needsTranslation, translations[message.id] != nil else { return }
                if showOriginal.contains(message.id) {
                    showOriginal.remove(message.id)
                } else {
                    showOriginal.insert(message.id)
                }
            }

            Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(isMine ? .leading : .trailing, 48)
    }

    // MARK: - Eingabe

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                "Auf \(profile.learningLanguage.label) schreiben …",
                text: $input,
                axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.accent : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private var canSend: Bool {
        !sending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        input = ""
        Task {
            if let message = try? await service.send(
                text: text,
                language: profile.learningLanguage,
                in: match,
                from: profile
            ) {
                messages.append(message)
            }
            sending = false
        }
    }
}
