# v2 Online — Tandem-Community

Branch `v2_Online`: Sprach-Tandem-Netzwerk in der App. Deutsche Muttersprachler
werden mit französischen Muttersprachlern gematcht und chatten — jeder liest
und schreibt in seiner **Lernsprache**, die App übersetzt dazwischen.

## Architektur

| Baustein | Lösung | Warum |
|---|---|---|
| Konto/„Login" | **CloudKit** (Apple-ID des Geräts) | Kein Passwort-Server, keine Betriebskosten, DSGVO-freundlich. Pro iCloud-Account genau ein Profil. |
| Profile, Matches, Chat | CloudKit **Public Database** (Record-Typen `Profile`, `Match`, `Message`) | Serverlos, in jedem Apple-Developer-Konto enthalten. |
| Übersetzung | **Apple Translation Framework** (ab iOS 18) | On-device, offline, kostenlos, privat — keine API-Schlüssel. Auf iOS 17 wird der Originaltext angezeigt. |
| Demo-Modus | `MockCommunityService` (In-Memory, simulierte Partner mit Auto-Antworten) | Entwicklung/Test ohne iCloud; erreichbar über den Button „Demo-Modus starten" oder Launch-Argument `--community-demo`. |

## Übersetzungsprinzip

Jeder Nutzer schreibt in der Sprache, die er übt (seiner Lernsprache).
Die Nachricht wird gespeichert wie geschrieben; der Empfänger sieht sie
on-device übersetzt in *seine* Lernsprache — Original per Tipp einsehbar.

Beispiel: Anna (deutsch, lernt FR) schreibt «Je cherche un restaurant.»
→ Pierre (französisch, lernt DE) liest „Ich suche ein Restaurant."
Er antwortet „Ich kenne ein gutes!" → Anna liest «J'en connais un bon !»

## Einmalige Einrichtung (für den echten Betrieb)

1. Apple-Developer-Konto: App-ID `design.avrunding.frenchapp` um die
   **iCloud-Capability** ergänzen, Container `iCloud.design.avrunding.frenchapp` anlegen.
2. In Xcode unter Signing & Capabilities das Team wählen (Entitlements liegen
   schon in `FrenchApp/FrenchApp.entitlements`, xcodegen bindet sie ein).
3. Im [CloudKit Dashboard](https://icloud.developer.apple.com) die Indizes anlegen
   (Queryable): `Profile.nativeLanguage`, `Profile.createdAt`, `Match.participants`,
   `Message.matchID`, `Message.sentAt` — CloudKit legt die Record-Typen beim ersten
   Schreiben im Development-Environment automatisch an.
4. Vor dem Release: Schema von Development nach Production deployen.

Ohne diese Einrichtung zeigt der Tandem-Tab den Hinweis-Screen mit Demo-Modus.

## Offene Punkte (bewusst v2.1+)

- Push bei neuen Nachrichten (CKQuerySubscription) — aktuell 4-Sekunden-Polling im Chat
- Blockieren/Melden von Profilen, Moderation
- Match-Auflösung (Tandem beenden)
- Übersetzungs-Modell-Download-UI (Erstnutzung fragt iOS selbst nach)
