import SwiftUI
import PhotosUI

/// Einstieg in die Tandem-Community (v2 Online): prüft das Konto,
/// führt durchs Profil-Anlegen und zeigt dann Partnersuche + Chats.
struct CommunityRootView: View {
    enum Phase {
        case checking
        case needsAccount
        /// Profil anlegen (nil) oder bestehendes bearbeiten.
        case needsProfile(existing: CommunityProfile?)
        case ready(CommunityProfile)
    }

    @State private var service: CommunityService = ProcessInfo.processInfo.arguments.contains("--community-demo")
        ? MockCommunityService()
        : CloudKitCommunityService()
    @State private var isDemo = ProcessInfo.processInfo.arguments.contains("--community-demo")
    @State private var phase: Phase = .checking

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .checking:
                    ProgressView("Verbinde …")
                case .needsAccount:
                    accountHint
                case .needsProfile(let existing):
                    ProfileEditorView(
                        service: service,
                        draft: existing.map(ProfileDraft.init) ?? ProfileDraft(),
                        existingProfile: existing,
                        onSaved: { profile in
                            phase = .ready(profile)
                        },
                        onDeleted: {
                            phase = .needsProfile(existing: nil)
                        }
                    )
                case .ready(let profile):
                    CommunityHomeView(service: service, profile: profile, isDemo: isDemo) {
                        phase = .needsProfile(existing: profile)
                    }
                }
            }
            .navigationTitle("Tandem")
            .toolbar {
                if isDemo {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("DEMO")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.warning, in: Capsule())
                    }
                }
            }
        }
        .task { await start() }
    }

    private func start() async {
        if await service.accountAvailable() {
            let profile = try? await service.loadMyProfile()
            phase = profile.flatMap { $0 }.map(Phase.ready) ?? .needsProfile(existing: nil)
        } else {
            phase = .needsAccount
        }
    }

    private var accountHint: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.icloud")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
            Text("Anmeldung über iCloud")
                .font(.title3.bold())
            Text("Dein Tandem-Konto läuft über deine Apple-ID — ohne extra Passwort. Melde dich in den iOS-Einstellungen bei iCloud an und komm zurück.\n\nOder probiere die Community im Demo-Modus mit simulierten Partnern aus.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                service = MockCommunityService()
                isDemo = true
                phase = .needsProfile(existing: nil)
            } label: {
                Text("Demo-Modus starten")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Profil anlegen & bearbeiten

struct ProfileEditorView: View {
    let service: CommunityService
    @State var draft: ProfileDraft
    /// Gesetzt, wenn ein bestehendes Profil bearbeitet wird — schaltet die
    /// Lösch-Sektion frei (Konto-Löschung in der App, Guideline 5.1.1(v)).
    var existingProfile: CommunityProfile?
    let onSaved: (CommunityProfile) -> Void
    var onDeleted: () -> Void = {}

    @State private var hobbyInput = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileAvatar(photoData: draft.photoData, initials: initialsPreview, size: 96)
                            Image(systemName: "pencil.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .background(Circle().fill(.background))
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Dein Name", text: $draft.displayName)
                    .textInputAutocapitalization(.words)
                Picker("Meine Muttersprache", selection: $draft.nativeLanguage) {
                    ForEach(TandemLanguage.allCases) { language in
                        Text("\(language.flag) \(language.label)").tag(language)
                    }
                }
            } header: {
                Text("Über dich")
            } footer: {
                Text("Du suchst Partner mit Muttersprache \(draft.nativeLanguage.other.label) — im Chat liest und schreibst du auf \(draft.nativeLanguage.other.label).")
            }

            Section("Profiltext") {
                TextEditor(text: $draft.bio)
                    .frame(minHeight: 90)
            }

            Section("Hobbys") {
                if !draft.hobbies.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(draft.hobbies, id: \.self) { hobby in
                            HStack(spacing: 4) {
                                Text(hobby)
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                            .onTapGesture {
                                draft.hobbies.removeAll { $0 == hobby }
                            }
                        }
                    }
                }
                HStack {
                    TextField("Hobby hinzufügen", text: $hobbyInput)
                        .onSubmit(addHobby)
                    Button(action: addHobby) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(hobbyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    if saving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Profil speichern")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!draft.isValid || saving)
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                }
            }

            if existingProfile != nil {
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        if deleting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Profil endgültig löschen")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(deleting)
                } footer: {
                    Text("Löscht dein Tandem-Profil, alle Matches und sämtliche Nachrichtenverläufe. Dein Lernfortschritt in der App bleibt erhalten.")
                }
            }
        }
        .confirmationDialog(
            "Profil wirklich löschen?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Endgültig löschen", role: .destructive) { deleteProfile() }
        } message: {
            Text("Das kann nicht rückgängig gemacht werden.")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    draft.photoData = data
                }
            }
        }
    }

    private var initialsPreview: String {
        let parts = draft.displayName.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : initials
    }

    private func addHobby() {
        let hobby = hobbyInput.trimmingCharacters(in: .whitespaces)
        guard !hobby.isEmpty, !draft.hobbies.contains(hobby) else { return }
        draft.hobbies.append(hobby)
        hobbyInput = ""
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            do {
                let profile = try await service.saveProfile(draft)
                onSaved(profile)
            } catch {
                errorMessage = error.localizedDescription
            }
            saving = false
        }
    }

    private func deleteProfile() {
        guard let existingProfile else { return }
        deleting = true
        errorMessage = nil
        Task {
            do {
                try await service.deleteMyProfile(existingProfile)
                onDeleted()
            } catch {
                errorMessage = error.localizedDescription
            }
            deleting = false
        }
    }
}

// MARK: - Avatar

struct ProfileAvatar: View {
    let photoData: Data?
    let initials: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.15))
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
