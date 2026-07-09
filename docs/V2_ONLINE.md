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

## Moderation & App-Review-Pflichten (Guideline 1.2 / 5.1.1)

Für Apps mit nutzergenerierten Inhalten verlangt Apple Blockieren, Melden,
Inhaltsfilterung und In-App-Kontolöschung — alles eingebaut:

| Pflicht | Umsetzung |
|---|---|
| Nutzer blockieren | Chat-Menü (⋯) und Kontextmenü auf Partnervorschlägen. `Block`-Record; beide Richtungen verschwinden aus den Vorschlägen, ein gemeinsames Tandem wird samt Verlauf aufgelöst. |
| Inhalte melden | Melde-Formular (Grund + Details) im Chat-Menü und auf Vorschlägen. Landet als `Report`-Record in der Public DB — **im CloudKit-Dashboard regelmäßig prüfen und zeitnah reagieren** (Apple erwartet das). |
| Filter für anstößige Inhalte | `ContentFilter` (DE/FR/EN-Wortliste, on-device, wortweise mit Akzent-/Groß-Faltung) blockiert das Senden mit Hinweis. Liste in `CommunityModeration.swift` erweiterbar. |
| Tandem beenden | Chat-Menü — löscht Match + Verlauf für beide Seiten. |
| Konto löschen (5.1.1(v)) | Profil-Editor → „Profil endgültig löschen": Profil, Matches, Verläufe und eigene Blocks werden entfernt. |

Außerhalb des Codes vor dem Release noch nötig: Datenschutzerklärung
(Apple/CloudKit als Verarbeiter), Privacy Nutrition Labels in App Store
Connect, Support-Kontakt, ggf. Altersfreigabe prüfen.

## Chat-Liste & Push

- Chat-Liste zeigt letzte Nachricht + relative Zeit, sortiert nach Aktivität
  (eingehende Anfragen zuoberst), Ungelesen-Punkt (Lesestand rein lokal via
  `ChatReadTracker`, keine Lesebestätigung an den Partner).
- Push bei neuen Nachrichten: `CommunityPush` legt pro angenommenem Match eine
  `CKQuerySubscription` auf fremde `Message`-Records an — CloudKit stellt die
  Benachrichtigung ohne eigenen Push-Server zu. Braucht die
  Push-Notifications-Capability auf der App-ID (`aps-environment` steht im
  Entitlements-File); ohne Einrichtung/Erlaubnis bleibt es beim
  4-Sekunden-Polling im offenen Chat.

## Einmalige Einrichtung (für den echten Betrieb)

1. Apple-Developer-Konto: App-ID `design.avrunding.frenchapp` um die
   **iCloud-Capability** und **Push Notifications** ergänzen, Container
   `iCloud.design.avrunding.frenchapp` anlegen.
2. In Xcode unter Signing & Capabilities das Team wählen (Entitlements liegen
   schon in `FrenchApp/FrenchApp.entitlements`, xcodegen bindet sie ein).
3. Im [CloudKit Dashboard](https://icloud.developer.apple.com) die Indizes anlegen
   (Queryable): `Profile.nativeLanguage`, `Profile.createdAt`, `Match.participants`,
   `Message.matchID`, `Message.sentAt`, `Block.blockerID`, `Block.blockedID` —
   CloudKit legt die Record-Typen (`Profile`, `Match`, `Message`, `Block`,
   `Report`) beim ersten Schreiben im Development-Environment automatisch an.
4. Vor dem Release: Schema von Development nach Production deployen.

Ohne diese Einrichtung zeigt der Tandem-Tab den Hinweis-Screen mit Demo-Modus.

## Offene Punkte (bewusst v2.2+)

- Ausgefeiltere Inhaltsfilterung (aktuell Wortliste; z. B. SensitiveContentAnalysis)
- Verwaltung blockierter Profile (Entblocken hat noch keine UI, `unblock` ist im Service vorhanden)
- Übersetzungs-Modell-Download-UI (Erstnutzung fragt iOS selbst nach)
