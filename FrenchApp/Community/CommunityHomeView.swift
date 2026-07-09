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
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var requestedIDs: Set<String> = []

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
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        loading = true
        errorMessage = nil
        do {
            candidates = try await service.candidates(for: profile)
            matches = try await service.matches(for: profile)
            let partnerIDs = matches.map { $0.otherProfileID(for: profile.id) }
            partnerProfiles = try await service.profiles(ids: partnerIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
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
                    ForEach(matches) { match in
                        matchRow(match)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func matchRow(_ match: TandemMatch) -> some View {
        let partnerID = match.otherProfileID(for: profile.id)
        let partner = partnerProfiles[partnerID]

        if match.status == .accepted, let partner {
            NavigationLink {
                ChatView(service: service, profile: profile, partner: partner, match: match)
            } label: {
                matchRowContent(match, partner: partner)
            }
            .buttonStyle(.plain)
        } else {
            matchRowContent(match, partner: partner)
        }
    }

    private func matchRowContent(_ match: TandemMatch, partner: CommunityProfile?) -> some View {
        HStack(spacing: 12) {
            ProfileAvatar(
                photoData: partner?.photoData,
                initials: partner?.initials ?? "?",
                size: 48
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(partner?.displayName ?? "Unbekanntes Profil")
                    .font(.body.weight(.semibold))
                Text(statusLabel(match))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statusLabel(_ match: TandemMatch) -> String {
        switch match.status {
        case .accepted:
            return "Tandem aktiv — tippe zum Chatten"
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
