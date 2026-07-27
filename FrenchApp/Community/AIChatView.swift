import SwiftUI

/// Chat mit dem KI-Gesprächspartner.
///
/// Welcher Dienst antwortet, entscheidet `AIPartnerResolver` — bevorzugt
/// Apples On-Device-Modell, weil es kostenlos, offline und ohne Einrichtung
/// läuft. Die KI schreibt durchgehend in der **Lernsprache** des Nutzers; das
/// Verständnis sichert das Antippen einer Nachricht ab.
struct AIChatView: View {
    let profile: CommunityProfile
    let isDemo: Bool
    let keyStore: AIKeyStoring
    let proxy: AIProxyConfig?
    /// Nur für Tests und Previews — überspringt die Dienstauswahl.
    let serviceOverride: AIPartnerService?

    init(
        profile: CommunityProfile,
        isDemo: Bool = false,
        keyStore: AIKeyStoring = KeychainAIKeyStore(),
        proxy: AIProxyConfig? = AIProxyConfig.fromBundle(),
        serviceOverride: AIPartnerService? = nil
    ) {
        self.profile = profile
        self.isDemo = isDemo
        self.keyStore = keyStore
        self.proxy = proxy
        self.serviceOverride = serviceOverride
    }

    @EnvironmentObject private var premium: PremiumStore
    @AppStorage("ai.level") private var levelRaw = CEFRLevel.a1.rawValue

    @State private var routing: AIPartnerRouting?
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var confirmReset = false

    // Übersetzen auf Tippen
    @State private var translations: [String: String] = [:]
    @State private var flipped: Set<String> = []
    @State private var requested: Set<String> = []
    @State private var translating: Set<String> = []
    @State private var unavailable: Set<String> = []

    private let store = AIChatStore()
    private static let levels: [CEFRLevel] = [.a1, .a2, .b1, .b2]
    private static let typingAnchor = "typing"

    private var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a1 }

    private var persona: AIPersona {
        AIPersona(language: profile.learningLanguage, level: level)
    }

    var body: some View {
        Group {
            if let service = routing?.service {
                chat(service: service)
            } else {
                AIChatSetupView(
                    keyStore: keyStore,
                    hint: unavailableHint,
                    onSaved: refreshRouting
                )
            }
        }
        .navigationTitle(persona.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if routing?.service != nil { chatMenu } }
        .task {
            refreshRouting()
            messages = await store.load()
        }
        // Das Niveau steuert die Modellwahl mit — ab B1 lieber Claude, wenn
        // erreichbar. Also bei Änderung neu entscheiden.
        .onChange(of: levelRaw) { refreshRouting() }
        .onChange(of: premium.isPremium) { refreshRouting() }
        .confirmationDialog(
            "Gespräch neu starten?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Neu starten", role: .destructive) { reset() }
        } message: {
            Text("Der bisherige Verlauf wird gelöscht.")
        }
        .alert("Hinweis", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var unavailableHint: String {
        if case .unavailable(let hint) = routing?.source { return hint }
        return ""
    }

    private func refreshRouting() {
        if let serviceOverride {
            routing = AIPartnerRouting(source: .ownKey, service: serviceOverride)
            return
        }
        routing = AIPartnerResolver.resolve(
            isDemo: isDemo,
            level: level,
            keyStore: keyStore,
            proxy: proxy,
            isPremium: premium.isPremium
        )
    }

    // MARK: - Chat

    private func chat(service: AIPartnerService) -> some View {
        VStack(spacing: 0) {
            aiBanner

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            starters(service: service)
                        }
                        ForEach(messages) { message in
                            bubble(message, service: service).id(message.id)
                        }
                        if sending {
                            typingIndicator.id(Self.typingAnchor)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { scrollToEnd(proxy) }
                .onChange(of: sending) { scrollToEnd(proxy) }
            }

            inputBar(service: service)
        }
        .background(Color(.systemGroupedBackground))
        .background { translationBridge(service: service) }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if sending {
                proxy.scrollTo(Self.typingAnchor, anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    /// Apple verlangt, dass KI-Gespräche klar als solche erkennbar sind —
    /// deshalb dauerhaft sichtbar, nicht nur im Titel. Die zweite Zeile zeigt,
    /// welcher Dienst gerade antwortet.
    private var aiBanner: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.caption)
                Text("Du chattest mit einer KI, nicht mit einem Menschen. Sie schreibt auf \(persona.language.label).")
                    .font(.caption)
            }
            if let label = routing?.source.label, !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.regularMaterial)
    }

    /// Für A1-Lernende ist das leere Eingabefeld die größte Hürde.
    private func starters(service: AIPartnerService) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.sparkles.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("Sag einfach Hallo")
                .font(.headline)
            Text("\(persona.name) antwortet auf \(persona.language.label) — passend zu Niveau \(persona.level.rawValue).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ForEach(persona.starters, id: \.self) { starter in
                    Button {
                        send(starter, service: service)
                    } label: {
                        Text(starter)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(.top, 32)
        .padding(.horizontal, 8)
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("\(persona.name) schreibt …")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    // MARK: - Nachrichten-Blase

    @ViewBuilder
    private func bubble(_ message: ChatMessage, service: AIPartnerService) -> some View {
        let isMine = message.senderProfileID == profile.id
        let translation = translations[message.id]
        let showsTranslation = flipped.contains(message.id) && translation != nil

        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                Text(showsTranslation ? (translation ?? message.text) : message.text)
                translationFooter(for: message, showsTranslation: showsTranslation)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isMine ? Theme.accent : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .foregroundStyle(isMine ? .white : .primary)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { toggleTranslation(message, service: service) }

            Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(isMine ? .leading : .trailing, 48)
    }

    /// Dauerhaft sichtbar — sonst ist nicht erkennbar, dass Blasen antippbar sind.
    @ViewBuilder
    private func translationFooter(for message: ChatMessage, showsTranslation: Bool) -> some View {
        if translating.contains(message.id) {
            Label("Übersetze …", systemImage: "globe")
                .font(.caption2)
                .opacity(0.7)
        } else if unavailable.contains(message.id) {
            Label(
                TranslationBridge.isSupported
                    ? "Übersetzung nicht verfügbar"
                    : "Übersetzung ab iOS 18",
                systemImage: "info.circle"
            )
            .font(.caption2)
            .opacity(0.7)
        } else {
            Label(
                showsTranslation ? "Original zeigen" : "Übersetzen",
                systemImage: "globe"
            )
            .font(.caption2)
            .opacity(0.7)
        }
    }

    // MARK: - Übersetzen

    /// Nur angetippte Nachrichten werden übersetzt — nicht prophylaktisch alle.
    private func translationBridge(service: AIPartnerService) -> some View {
        TranslationBridge(
            requests: messages
                .filter { requested.contains($0.id) }
                .map { TranslationRequest(id: $0.id, text: $0.text) },
            source: profile.learningLanguage,
            target: profile.nativeLanguage,
            translations: $translations,
            onUnavailable: { open in translateWithAI(open, service: service) }
        )
    }

    private func toggleTranslation(_ message: ChatMessage, service: AIPartnerService) {
        if translations[message.id] != nil {
            if flipped.contains(message.id) {
                flipped.remove(message.id)
            } else {
                flipped.insert(message.id)
            }
            return
        }
        guard !translating.contains(message.id) else { return }
        // Hier schreiben KI wie Nutzer in der Lernsprache — die Übersetzung ist
        // also nie die Standardanzeige und muss umgeschaltet werden.
        flipped.insert(message.id)

        if unavailable.contains(message.id) || !TranslationBridge.isSupported {
            // On-device hat schon abgewinkt → direkt zum KI-Dienst. (Erneutes
            // Eintragen in `requested` würde die Bridge nicht noch einmal
            // anstoßen, weil sich ihre Anfrageliste nicht ändert.)
            unavailable.remove(message.id)
            translateWithAI(
                [TranslationRequest(id: message.id, text: message.text)],
                service: service
            )
        } else {
            requested.insert(message.id)
        }
    }

    /// Rückfallebene, wenn Apple Translation nicht kann (iOS 17, Modell fehlt).
    private func translateWithAI(_ open: [TranslationRequest], service: AIPartnerService) {
        for request in open where !translating.contains(request.id) {
            translating.insert(request.id)
            Task {
                do {
                    translations[request.id] = try await service.translate(
                        request.text,
                        from: profile.learningLanguage,
                        to: profile.nativeLanguage
                    )
                } catch {
                    unavailable.insert(request.id)
                }
                translating.remove(request.id)
            }
        }
    }

    // MARK: - Eingabe

    private func inputBar(service: AIPartnerService) -> some View {
        HStack(spacing: 10) {
            TextField(
                "Auf \(persona.language.label) schreiben …",
                text: $input,
                axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .onSubmit { send(input, service: service) }

            Button {
                send(input, service: service)
            } label: {
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

    private func send(_ text: String, service: AIPartnerService) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        guard ContentFilter.isAcceptable(trimmed) else {
            errorMessage = "Deine Nachricht enthält Wörter, die hier nicht erlaubt sind. Bitte formuliere sie um."
            return
        }

        input = ""
        sending = true

        let mine = ChatMessage(
            id: UUID().uuidString,
            matchID: AIPartnerIdentity.matchID,
            senderProfileID: profile.id,
            text: trimmed,
            language: profile.learningLanguage,
            sentAt: .now
        )
        let currentPersona = persona

        Task {
            // Den zurückgegebenen Stand direkt weiterverwenden — die KI braucht
            // die eigene Nachricht bereits im Verlauf.
            let withMine = await store.append(mine)
            messages = withMine
            do {
                let answer = try await service.reply(to: withMine, as: currentPersona)
                messages = await store.append(ChatMessage(
                    id: UUID().uuidString,
                    matchID: AIPartnerIdentity.matchID,
                    senderProfileID: AIPartnerIdentity.profileID,
                    text: answer,
                    language: currentPersona.language,
                    sentAt: .now
                ))
            } catch {
                errorMessage = (error as? AIPartnerError)?.errorDescription
                    ?? error.localizedDescription
            }
            sending = false
        }
    }

    // MARK: - Menü

    private var chatMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Niveau", selection: $levelRaw) {
                    ForEach(Self.levels) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }
                Divider()
                Button {
                    confirmReset = true
                } label: {
                    Label("Gespräch neu starten", systemImage: "arrow.counterclockwise")
                }
                if keyStore.hasKey {
                    Button(role: .destructive) {
                        keyStore.clear()
                        refreshRouting()
                    } label: {
                        Label("API-Key entfernen", systemImage: "key.slash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func reset() {
        translations = [:]
        flipped = []
        requested = []
        translating = []
        unavailable = []
        Task { messages = await store.reset() }
    }
}

// MARK: - Einrichtung

/// Zu sehen, wenn gerade kein Dienst verfügbar ist. Nennt zuerst den Weg, der
/// nichts kostet (Apple Intelligence bzw. Premium) und bietet erst danach den
/// eigenen API-Key an.
struct AIChatSetupView: View {
    let keyStore: AIKeyStoring
    let hint: String
    let onSaved: () -> Void

    @State private var key = ""
    @State private var showKeyField = false
    @State private var showInvalid = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 32)

                Text("KI-Gesprächspartner")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text("""
                Der KI-Partner ist jederzeit zum Üben da — auch wenn gerade kein \
                Tandem-Partner online ist.
                """)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                if !hint.isEmpty {
                    Text(hint)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }

                if showKeyField {
                    keyEntry
                } else {
                    Button("Eigenen API-Key hinterlegen") {
                        showKeyField = true
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }
            .padding(24)
        }
    }

    private var keyEntry: some View {
        VStack(spacing: 12) {
            SecureField("sk-ant-…", text: $key)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                save()
            } label: {
                Text("Key speichern")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)

            if showInvalid {
                Text("Der Key konnte nicht gespeichert werden.")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }

            Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                Label("Key bei Anthropic erstellen", systemImage: "arrow.up.right.square")
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Dein Key wird nur auf diesem Gerät im Schlüsselbund gespeichert — nie in iCloud, nie an uns.")
                } icon: {
                    Image(systemName: "lock.fill")
                }
                Label {
                    Text("Was du dem KI-Partner schreibst, wird zur Beantwortung an Anthropic übertragen. Schreib dort nichts Vertrauliches.")
                } icon: {
                    Image(systemName: "info.circle.fill")
                }
                Label {
                    Text("Die Nutzung wird über deinen eigenen Anthropic-Zugang abgerechnet.")
                } icon: {
                    Image(systemName: "eurosign.circle.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    private func save() {
        guard keyStore.save(key) else {
            showInvalid = true
            return
        }
        key = ""
        onSaved()
    }
}
