import CloudKit
import Foundation

/// Produktiv-Backend über CloudKit (Public Database).
///
/// „Login" läuft über die Apple-ID des Geräts: CloudKit liefert pro
/// iCloud-Account eine stabile Nutzer-ID — keine Passwörter, keine eigene
/// Server-Infrastruktur. Voraussetzung: iCloud-Capability mit Container
/// `iCloud.design.avrunding.frenchapp` im Apple-Developer-Konto
/// (siehe docs/V2_ONLINE.md).
final class CloudKitCommunityService: CommunityService {
    static let containerID = "iCloud.design.avrunding.frenchapp"

    private let container: CKContainer
    private var database: CKDatabase { container.publicCloudDatabase }

    init() {
        container = CKContainer(identifier: Self.containerID)
    }

    // MARK: - Konto & Profil

    func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// Stabile Profil-ID aus der CloudKit-Nutzer-ID.
    private func myProfileRecordID() async throws -> CKRecord.ID {
        let userID = try await container.userRecordID()
        return CKRecord.ID(recordName: "profile_\(userID.recordName)")
    }

    func loadMyProfile() async throws -> CommunityProfile? {
        let recordID = try await myProfileRecordID()
        do {
            let record = try await database.record(for: recordID)
            return Self.profile(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveProfile(_ draft: ProfileDraft) async throws -> CommunityProfile {
        let recordID = try await myProfileRecordID()
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: "Profile", recordID: recordID)
            record["createdAt"] = Date()
        }
        record["displayName"] = draft.displayName.trimmingCharacters(in: .whitespaces)
        record["bio"] = draft.bio
        record["hobbies"] = draft.hobbies
        record["nativeLanguage"] = draft.nativeLanguage.rawValue

        if let data = draft.photoData {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: url)
            record["photo"] = CKAsset(fileURL: url)
        } else {
            record["photo"] = nil
        }

        let saved = try await database.save(record)
        guard let profile = Self.profile(from: saved) else {
            throw CommunityError.network("Profil konnte nicht gespeichert werden.")
        }
        return profile
    }

    // MARK: - Partnersuche

    func candidates(for profile: CommunityProfile) async throws -> [CommunityProfile] {
        let predicate = NSPredicate(
            format: "nativeLanguage == %@", profile.learningLanguage.rawValue
        )
        let query = CKQuery(recordType: "Profile", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (results, _) = try await database.records(matching: query, resultsLimit: 50)
        let existingPartners = Set(
            try await matches(for: profile).map { $0.otherProfileID(for: profile.id) }
        )
        return results
            .compactMap { try? $0.1.get() }
            .compactMap(Self.profile(from:))
            .filter { $0.id != profile.id && !existingPartners.contains($0.id) }
    }

    func profiles(ids: [String]) async throws -> [String: CommunityProfile] {
        guard !ids.isEmpty else { return [:] }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0) }
        let results = try await database.records(for: recordIDs)
        var byID: [String: CommunityProfile] = [:]
        for (recordID, result) in results {
            if let record = try? result.get(), let profile = Self.profile(from: record) {
                byID[recordID.recordName] = profile
            }
        }
        return byID
    }

    // MARK: - Matches

    func requestMatch(from me: CommunityProfile, to partner: CommunityProfile) async throws -> TandemMatch {
        let record = CKRecord(recordType: "Match")
        record["requesterID"] = me.id
        record["partnerID"] = partner.id
        record["status"] = MatchStatus.pending.rawValue
        record["createdAt"] = Date()
        // Für Abfragen „alle Matches mit mir": beide IDs in einem Listenfeld.
        record["participants"] = [me.id, partner.id]
        let saved = try await database.save(record)
        guard let match = Self.match(from: saved) else {
            throw CommunityError.network("Anfrage konnte nicht gespeichert werden.")
        }
        return match
    }

    func matches(for profile: CommunityProfile) async throws -> [TandemMatch] {
        let predicate = NSPredicate(format: "participants CONTAINS %@", profile.id)
        let query = CKQuery(recordType: "Match", predicate: predicate)
        let (results, _) = try await database.records(matching: query, resultsLimit: 100)
        return results
            .compactMap { try? $0.1.get() }
            .compactMap(Self.match(from:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    func accept(_ match: TandemMatch) async throws -> TandemMatch {
        let record = try await database.record(for: CKRecord.ID(recordName: match.id))
        record["status"] = MatchStatus.accepted.rawValue
        let saved = try await database.save(record)
        return Self.match(from: saved) ?? match
    }

    // MARK: - Nachrichten

    func messages(for match: TandemMatch) async throws -> [ChatMessage] {
        let predicate = NSPredicate(format: "matchID == %@", match.id)
        let query = CKQuery(recordType: "Message", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: true)]
        let (results, _) = try await database.records(matching: query, resultsLimit: 200)
        return results
            .compactMap { try? $0.1.get() }
            .compactMap(Self.message(from:))
    }

    func send(
        text: String,
        language: TandemLanguage,
        in match: TandemMatch,
        from profile: CommunityProfile
    ) async throws -> ChatMessage {
        let record = CKRecord(recordType: "Message")
        record["matchID"] = match.id
        record["senderProfileID"] = profile.id
        record["text"] = text
        record["language"] = language.rawValue
        record["sentAt"] = Date()
        let saved = try await database.save(record)
        guard let message = Self.message(from: saved) else {
            throw CommunityError.network("Nachricht konnte nicht gesendet werden.")
        }
        return message
    }

    // MARK: - Record-Mapping

    private static func profile(from record: CKRecord) -> CommunityProfile? {
        guard let name = record["displayName"] as? String,
              let langRaw = record["nativeLanguage"] as? String,
              let language = TandemLanguage(rawValue: langRaw)
        else { return nil }

        var photoData: Data?
        if let asset = record["photo"] as? CKAsset, let url = asset.fileURL {
            photoData = try? Data(contentsOf: url)
        }
        return CommunityProfile(
            id: record.recordID.recordName,
            displayName: name,
            bio: record["bio"] as? String ?? "",
            hobbies: record["hobbies"] as? [String] ?? [],
            nativeLanguage: language,
            photoData: photoData,
            createdAt: record["createdAt"] as? Date ?? .now
        )
    }

    private static func match(from record: CKRecord) -> TandemMatch? {
        guard let requesterID = record["requesterID"] as? String,
              let partnerID = record["partnerID"] as? String,
              let statusRaw = record["status"] as? String,
              let status = MatchStatus(rawValue: statusRaw)
        else { return nil }
        return TandemMatch(
            id: record.recordID.recordName,
            requesterID: requesterID,
            partnerID: partnerID,
            status: status,
            createdAt: record["createdAt"] as? Date ?? .now
        )
    }

    private static func message(from record: CKRecord) -> ChatMessage? {
        guard let matchID = record["matchID"] as? String,
              let senderID = record["senderProfileID"] as? String,
              let text = record["text"] as? String,
              let langRaw = record["language"] as? String,
              let language = TandemLanguage(rawValue: langRaw)
        else { return nil }
        return ChatMessage(
            id: record.recordID.recordName,
            matchID: matchID,
            senderProfileID: senderID,
            text: text,
            language: language,
            sentAt: record["sentAt"] as? Date ?? .now
        )
    }
}
