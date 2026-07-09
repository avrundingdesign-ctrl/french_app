import SwiftUI

/// Hauptansicht der Community: Partnersuche und laufende Chats.
struct CommunityHomeView: View {
    let service: CommunityService
    let profile: CommunityProfile
    let isDemo: Bool
    let onEditProfile: () -> Void

    enum Section: String, CaseIterable, Identifiable {
        case partners = "Partner finden"
        case chats = "Chats"
        var id: String { rawValue }
    }

    @State private var section: Section = .partners
    @State private var candidates: [CommunityProfile] = []
    @State private var matches: [TandemMatch] = []
    @State private var partnerProfiles: [String: CommunityProfile] = [:]
    @State private var latestMessages: [String: ChatMessage] = [:]
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var requestedIDs: Set<String> = []
    @State private var reportTarget: CommunityProfile?
    @State private var blockTarget: CommunityProfile?

    private let readTracker = ChatReadTracker()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Bereich", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch section {
                case .partners: partnerList
                case .chats: chatList
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onEditProfile) {
                    ProfileAvatar(photoData: profile.photoData, initials: profile.initials, size: 30)
                }
            }
        }
        // onAppear statt task: lädt auch beim Zurückkehren aus einem Chat neu
        // (Gelesen-Status, letzte Nachricht, beendete Tandems).
        .onAppear { Task { await reload() } }
        .refreshable { await reload() }
        .sheet(item: $reportTarget) { target in
            ReportSheetView(service: service, reporter: profile, reported: target, matchID: nil)
        }
        .confirmationDialog(
            "\(blockTarget?.displayName ?? "Profil") blockieren?",
            isPresented: .init(
                get: { blockTarget != nil },
                set: { if !$0 { blockTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Blockieren", role: .destructive) {
                if let blockTarget { block(blockTarget) }
            }
        } message: {
            Text("Ihr seht euch nicht mehr in den Vorschlägen; ein bestehendes Tandem wird beendet.")
        }
    }

    private func reload() async {
        // Spinner nur beim Erststart — danach still im Hintergrund aktualisieren.
        if matches.isEmpty && candidates.isEmpty { loading = true }
        errorMessage = nil
        do {
            candidates = try await service.candidates(for: profile)
            matches = try await service.matches(for: profile)
            let partnerIDs = matches.map { $0.otherProfileID(for: profile.id) }
            partnerProfiles = try await service.profiles(ids: partnerIDs)
            var latest: [String: ChatMessage] = [:]
            for match in matches where match.status == .accepted {
                latest[match.id] = try? await service.latestMessage(for: match)
            }
            latestMessages = latest
            if !isDemo {
                await CommunityPush.updateSubscriptions(for: profile, matches: matches)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func block(_ target: CommunityProfile) {
        Task {
            do {
                try await service.block(profileID: target.id, by: profile)
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Partnersuche

    private var partnerList: some View {
        ScrollView {
            VStack(spacing: 12) {
                infoHeader

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                }

                if loading {
                    ProgressView().padding(.top, 40)
                } else if candidates.isEmpty {
                    emptyState(
                        icon: "person.2",
                        title: "Noch keine Vorschläge",
                        text: "Sobald sich \(profile.learningLanguage.label.dropLast(0))-Muttersprachler anmelden, erscheinen sie hier. Zieh zum Aktualisieren nach unten."
                    )
                } else {
                    ForEach(candidates) { candidate in
                        candidateCard(candidate)
                    }
                }
            }
            .padding()
        }
    }

    private var infoHeader: some View {
        HStack(spacing: 10) {
            Text(profile.nativeLanguage.flag)
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(profile.learningLanguage.flag)
            Text("Du suchst Partner mit Muttersprache \(profile.learningLanguage.label).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func candidateCard(_ candidate: CommunityProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProfileAvatar(photoData: candidate.photoData, initials: candidate.initials, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName)
                        .font(.headline)
                    Text("\(candidate.nativeLanguage.flag) Muttersprache \(candidate.nativeLanguage.label) · lernt \(candidate.learningLanguage.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !candidate.bio.isEmpty {
                Text(candidate.bio)
                    .font(.subheadline)
                    .lineLimit(3)
            }

            if !candidate.hobbies.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(candidate.hobbies, id: \.self) { hobby in
                        Text(hobby)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                }
            }

            Button {
                request(candidate)
            } label: {
                Text(requestedIDs.contains(candidate.id) ? "Angefragt ✓" : "Tandem anfragen")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(requestedIDs.contains(candidate.id))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button {
                reportTarget = candidate
            } label: {
                Label("Melden …", systemImage: "flag")
            }
            Button(role: .destructive) {
                blockTarget = candidate
            } label: {
                Label("Blockieren …", systemImage: "hand.raised")
            }
        }
    }

    private func request(_ candidate: CommunityProfile) {
        requestedIDs.insert(candidate.id)
        Task {
            do {
                _ = try await service.requestMatch(from: profile, to: candidate)
                await reload()
                section = .chats
            } catch {
                requestedIDs.remove(candidate.id)
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Chats

    private var chatList: some View {
        ScrollView {
            VStack(spacing: 12) {
                if loading {
                    ProgressView().padding(.top, 40)
                } else if matches.isEmpty {
                    emptyState(
                        icon: "bubble.left.and.bubble.right",
                        title: "Noch keine Chats",
                        text: "Frage unter «Partner finden» ein Tandem an — angenommene Anfragen landen hier."
                    )
                } else {
                    ForEach(sortedMatches) { match in
                        matchRow(match)
                    }
                }
            }
            .padding()
        }
    }

    /// Eingehende Anfragen zuerst, danach nach letzter Aktivität.
    private var sortedMatches: [TandemMatch] {
        matches.sorted { first, second in
            let firstIncoming = first.isIncoming(for: profile.id)
            let secondIncoming = second.isIncoming(for: profile.id)
            if firstIncoming != secondIncoming { return firstIncoming }
            return activityDate(first) > activityDate(second)
        }
    }

    private func activityDate(_ match: TandemMatch) -> Date {
        latestMessages[match.id]?.sentAt ?? match.createdAt
    }

    @ViewBuilder
    private func matchRow(_ match: TandemMatch) -> some View {
        let partnerID = match.otherProfileID(for: profile.id)
        let partner = partnerProfiles[partnerID]

        if match.status == .accepted, let partner {
            NavigationLink {
                ChatView(
                    service: service,
                    profile: profile,
                    partner: partner,
                    match: match,
                    onMatchEnded: { Task { await reload() } }
                )
            } label: {
                matchRowContent(match, partner: partner)
            }
            .buttonStyle(.plain)
        } else {
            matchRowContent(match, partner: partner)
        }
    }

    private func matchRowContent(_ match: TandemMatch, partner: CommunityProfile?) -> some View {
        let latest = latestMessages[match.id]
        let unread = readTracker.isUnread(match: match, latestMessage: latest, viewerID: profile.id)

        return HStack(spacing: 12) {
            ProfileAvatar(
                photoData: partner?.photoData,
                initials: partner?.initials ?? "?",
                size: 48
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(partner?.displayName ?? "Unbekanntes Profil")
                    .font(.body.weight(unread ? .bold : .semibold))
                Text(statusLabel(match, latest: latest))
                    .font(.caption)
                    .fontWeight(unread ? .semibold : .regular)
                    .foregroundStyle(unread ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if match.isIncoming(for: profile.id) {
                Button("Annehmen") {
                    Task {
                        _ = try? await service.accept(match)
                        await reload()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
            } else if match.status == .accepted {
                VStack(alignment: .trailing, spacing: 4) {
                    if let latest {
                        Text(latest.sentAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if unread {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statusLabel(_ match: TandemMatch, latest: ChatMessage?) -> String {
        switch match.status {
        case .accepted:
            guard let latest else { return "Tandem aktiv — sag Bonjour!" }
            let prefix = latest.senderProfileID == profile.id ? "Du: " : ""
            return prefix + latest.text
        case .pending:
            return match.isIncoming(for: profile.id)
                ? "Möchte dein Tandem-Partner werden"
                : "Anfrage gesendet — wartet auf Antwort"
        }
    }

    private func emptyState(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 48)
        .padding(.horizontal, 24)
    }
}
