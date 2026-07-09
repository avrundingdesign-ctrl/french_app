import SwiftUI

/// Tandem-Chat: Du schreibst und liest in deiner Lernsprache.
/// Nachrichten des Partners (in seiner Lernsprache = deiner Muttersprache)
/// werden on-device übersetzt — das Original ist per Tipp einsehbar.
struct ChatView: View {
    let service: CommunityService
    let profile: CommunityProfile
    let partner: CommunityProfile
    let match: TandemMatch
    var onMatchEnded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var translations: [String: String] = [:]
    @State private var showOriginal: Set<String> = []
    @State private var input = ""
    @State private var sending = false
    @State private var showReportSheet = false
    @State private var confirmBlock = false
    @State private var confirmEnd = false
    @State private var showFilterWarning = false
    @State private var errorMessage: String?

    private let readTracker = ChatReadTracker()
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
        .toolbar { moderationMenu }
        .task { await reload() }
        .onReceive(refreshTimer) { _ in
            Task { await reload() }
        }
        .background {
            ChatTranslationBridge(messages: messages, viewer: profile, translations: $translations)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheetView(service: service, reporter: profile, reported: partner, matchID: match.id)
        }
        .confirmationDialog(
            "\(partner.displayName) blockieren?",
            isPresented: $confirmBlock,
            titleVisibility: .visible
        ) {
            Button("Blockieren", role: .destructive) { blockPartner() }
        } message: {
            Text("Das Tandem wird beendet, der Verlauf gelöscht und ihr seht euch nicht mehr in den Vorschlägen.")
        }
        .confirmationDialog(
            "Tandem mit \(partner.displayName) beenden?",
            isPresented: $confirmEnd,
            titleVisibility: .visible
        ) {
            Button("Tandem beenden", role: .destructive) { endTandem() }
        } message: {
            Text("Der Nachrichtenverlauf wird für beide Seiten gelöscht.")
        }
        .alert("Nachricht nicht gesendet", isPresented: $showFilterWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Deine Nachricht enthält Wörter, die hier nicht erlaubt sind. Bitte formuliere sie um.")
        }
        .alert("Fehler", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var moderationMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showReportSheet = true
                } label: {
                    Label("Melden …", systemImage: "flag")
                }
                Button {
                    confirmEnd = true
                } label: {
                    Label("Tandem beenden …", systemImage: "person.2.slash")
                }
                Button(role: .destructive) {
                    confirmBlock = true
                } label: {
                    Label("Blockieren …", systemImage: "hand.raised")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func blockPartner() {
        Task {
            do {
                try await service.block(profileID: partner.id, by: profile)
                readTracker.forget(matchID: match.id)
                onMatchEnded()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func endTandem() {
        Task {
            do {
                try await service.endMatch(match)
                readTracker.forget(matchID: match.id)
                onMatchEnded()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
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
            // Chat ist offen → alles bis zur letzten Nachricht gilt als gelesen.
            if let last = latest.last {
                readTracker.markRead(matchID: match.id, at: last.sentAt)
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
        guard ContentFilter.isAcceptable(text) else {
            showFilterWarning = true
            return
        }
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
                readTracker.markRead(matchID: match.id, at: message.sentAt)
            }
            sending = false
        }
    }
}

// MARK: - Melde-Formular

/// Meldung eines Profils (Guideline 1.2): Grund wählen, optional Details —
/// geht als Report-Record an den Betreiber, nicht an den Gemeldeten.
struct ReportSheetView: View {
    let service: CommunityService
    let reporter: CommunityProfile
    let reported: CommunityProfile
    var matchID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .inappropriate
    @State private var details = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Grund") {
                    Picker("Grund", selection: $reason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.rawValue).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("Was ist passiert? (optional)", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.danger)
                    } else {
                        Text("Deine Meldung geht an das FrenchApp-Team und wird zeitnah geprüft. \(reported.displayName) erfährt nichts davon.")
                    }
                }
            }
            .navigationTitle("\(reported.displayName) melden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") { submit() }
                        .disabled(sending)
                }
            }
            .alert("Danke für deine Meldung", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("Wir schauen uns das an.")
            }
        }
    }

    private func submit() {
        sending = true
        errorMessage = nil
        Task {
            do {
                try await service.report(
                    profileID: reported.id,
                    matchID: matchID,
                    reason: reason,
                    details: details.trimmingCharacters(in: .whitespacesAndNewlines),
                    by: reporter
                )
                sent = true
            } catch {
                errorMessage = error.localizedDescription
            }
            sending = false
        }
    }
}
