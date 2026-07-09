import CloudKit
import UIKit
import UserNotifications

/// Push bei neuen Tandem-Nachrichten: pro angenommenem Match eine
/// CKQuerySubscription auf fremde Message-Records — CloudKit stellt die
/// Benachrichtigung selbst zu, ein eigener Push-Server ist nicht nötig.
///
/// Schlägt die Einrichtung fehl (iCloud-Container nicht eingerichtet,
/// Mitteilungen abgelehnt), passiert nichts Schlimmes: im offenen Chat
/// bleibt das Polling aktiv.
@MainActor
enum CommunityPush {
    /// Verhindert, dass jeder Home-Aufruf erneut gegen CloudKit synct.
    private static var lastSyncedMatchIDs: Set<String>?

    static func updateSubscriptions(for profile: CommunityProfile, matches: [TandemMatch]) async {
        let acceptedIDs = Set(matches.filter { $0.status == .accepted }.map(\.id))
        guard acceptedIDs != lastSyncedMatchIDs else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            // Erst fragen, wenn es überhaupt einen Chat gibt, der Push braucht.
            guard !acceptedIDs.isEmpty else { return }
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
            else { return }
        case .denied:
            return
        default:
            break
        }
        UIApplication.shared.registerForRemoteNotifications()

        let database = CKContainer(identifier: CloudKitCommunityService.containerID)
            .publicCloudDatabase
        guard let existing = try? await database.allSubscriptions() else { return }
        let existingIDs = Set(existing.map(\.subscriptionID))

        for matchID in acceptedIDs where !existingIDs.contains(Self.subscriptionID(matchID)) {
            let subscription = CKQuerySubscription(
                recordType: "Message",
                predicate: NSPredicate(
                    format: "matchID == %@ AND senderProfileID != %@", matchID, profile.id
                ),
                subscriptionID: Self.subscriptionID(matchID),
                options: .firesOnRecordCreation
            )
            let info = CKSubscription.NotificationInfo()
            info.alertBody = "Neue Tandem-Nachricht 💬"
            info.soundName = "default"
            subscription.notificationInfo = info
            _ = try? await database.save(subscription)
        }

        // Subscriptions beendeter Tandems aufräumen.
        let activeIDs = Set(acceptedIDs.map(Self.subscriptionID))
        for subscription in existing
        where subscription.subscriptionID.hasPrefix("message_")
            && !activeIDs.contains(subscription.subscriptionID) {
            _ = try? await database.deleteSubscription(withID: subscription.subscriptionID)
        }

        lastSyncedMatchIDs = acceptedIDs
    }

    private static func subscriptionID(_ matchID: String) -> String {
        "message_\(matchID)"
    }
}
