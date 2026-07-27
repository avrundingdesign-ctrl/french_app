# App Privacy (App Store Connect „Privacy Nutrition Label")

Reference-Doku für den Privacy-Fragebogen in App Store Connect
(„App Privacy" → „Get Started"). Wird dort manuell im Web-UI ausgefüllt,
diese Datei ist nur die Entscheidungsgrundlage. Basis: Code-Stand
2026-07-12, Branch `v2_Online`.

Datenschutzerklärung (öffentliche Pflicht-URL): https://trin.studio/datenschutz.html
Support-URL: https://trin.studio/#kontakt

## Grundmodus (ohne Tandem-Community)

Keine Datenerhebung. Lernfortschritt, SRS-Status, Einstellungen und
Zertifikatsname liegen ausschließlich lokal in SwiftData
(`ModelConfiguration(cloudKitDatabase: .none)` — bewusst kein iCloud-Sync).
→ Für diesen Teil der App: **„Data Not Collected"** wäre korrekt, wenn es
die Community-Funktion nicht gäbe. Da sie Teil derselben App ist, muss
der Fragebogen aber die Community-Daten mit abdecken (siehe unten) —
es gibt keinen separaten Fragebogen pro Feature.

## Tandem-Community (CloudKit, opt-in)

Nur relevant, wenn der Nutzer die Community aktiviert (eigener
Onboarding-Schritt, nicht Voraussetzung für die App-Nutzung).

| Apple-Kategorie | Datentyp | Verlinkt mit Identität? | Zweck | Tracking? |
|---|---|---|---|---|
| Identifiers | User ID (CloudKit-Record-Name / iCloud-Account) | Ja | App-Funktionalität | Nein |
| Contact Info | Name (Anzeigename/Nickname, frei wählbar) | Ja | App-Funktionalität | Nein |
| User Content | Photos or Videos (optionales Profilfoto) | Ja | App-Funktionalität | Nein |
| User Content | Other User Content (Chat-Nachrichten, Bio, Hobbys) | Ja | App-Funktionalität | Nein |

**Nicht zutreffend / nicht erhoben:** Location, Contacts, Browsing
History, Search History, Financial Info, Health & Fitness, Usage Data,
Diagnostics, Sensitive Info.

**Tracking:** Nein — kein Zweck außerhalb der App, kein Data-Broker,
kein Advertising-SDK. Beantwortung der Frage „Do you or your third-party
partners collect data from this app for tracking purposes?" → **Nein**.

**Warum „Linked to Identity"** und nicht „Not Linked": Profil, Matches
und Nachrichten hängen am CloudKit-Nutzerkonto (iCloud), das ist die
Definition von „linked" laut Apple-Doku, auch wenn wir die Apple-ID
selbst nie sehen.

**Dritte:** Für den Tandem-Teil keine — CloudKit ist Apples eigene
Infrastruktur, kein Analytics-/Advertising-/Crash-SDK verbaut (siehe `grep`
über `FrenchApp/` auf Analytics/Firebase/AdMob/Crashlytics/Sentry — leer).
**Ausnahme: der KI-Gesprächspartner**, siehe nächster Abschnitt.

## KI-Gesprächspartner

Der KI-Partner kann über **drei** Wege laufen (`AIPartnerResolver`). Nur zwei
davon übertragen überhaupt Daten:

| Weg | Wann | Daten verlassen das Gerät? |
|---|---|---|
| **Apple Intelligence** (`AppleAIPartnerService`) | Standard, wenn iOS 26 + Apple-Intelligence-Gerät | **Nein** — das Modell läuft on-device |
| **Eigener Anthropic-Key** | Nutzer hinterlegt selbst einen Key | Ja → Anthropic |
| **Proxy** (`server/`, Premium) | Nur wenn `AIProxyBaseURL` gesetzt und Premium aktiv | Ja → CloudFlare → Anthropic |

Der **Regelfall auf neueren Geräten ist der erste** — dort ist der KI-Partner
datenschutzrechtlich unauffällig, weil nichts das Gerät verlässt. Das ist auch
der Grund, warum er Vorrang hat.

### Wenn Daten übertragen werden (Weg 2 und 3)

⚠️ **Erster echter Drittanbieter in der App.** Die Aussage „Dritte: Keine"
gilt für diese beiden Wege nicht mehr.

| Apple-Kategorie | Datentyp | Verlinkt mit Identität? | Zweck | Tracking? |
|---|---|---|---|---|
| User Content | Other User Content (Chatnachrichten an die KI) | Nein | App-Funktionalität | Nein |

**Empfänger:** Anthropic PBC, `api.anthropic.com`. Übertragen wird
ausschließlich der Nachrichtentext des KI-Chats (plus die letzten 20
Nachrichten als Gesprächskontext, `ClaudeAIPartnerService.historyLimit`) —
**kein** Profilname, kein Foto, keine iCloud-ID, kein Lernfortschritt.
Bei aktivem Key kann zusätzlich Text aus dem Tandem-Chat übertragen werden,
wenn der Nutzer eine Nachricht antippt und die On-Device-Übersetzung
(Apple Translation) nicht verfügbar ist — dann übernimmt die KI die
Übersetzung.

**Warum „Not Linked":** Die Anfragen laufen über den Key des Nutzers und
tragen keine Kennung aus der App; die Verknüpfung besteht allenfalls
zwischen Nutzer und seinem eigenen Anthropic-Konto, nicht durch uns.

**Der API-Key** liegt bei Weg 2 ausschließlich im Geräte-Schlüsselbund
(`KeychainAIKeyStore`, `kSecAttrAccessibleAfterFirstUnlock`) — nicht in
iCloud, nicht in `UserDefaults`, nicht im Code. Bei Weg 3 liegt er
serverseitig im Worker und ist der App gar nicht bekannt.

**Zum Proxy (Weg 3):** CloudFlare ist dabei Auftragsverarbeiter (Transport
und kurzzeitige Verarbeitung), Anthropic Empfänger des Nachrichtentextes.
Gespeichert wird im Worker **kein** Chatinhalt — nur pro Gerät ein
Public Key, ein Signaturzähler und ein Tageszähler (`server/src/index.js`).
Der Schlüssel identifiziert das Gerät, nicht die Person; er hängt an keinem
Namen, keiner iCloud-ID und keinem Lernfortschritt.

**Noch zu erledigen vor Release:**
- Datenschutzerklärung unter `trin.studio/datenschutz.html` ergänzen:
  Anthropic als Empfänger, bei aktivem Proxy zusätzlich CloudFlare als
  Auftragsverarbeiter.
- Im App-Store-Connect-Fragebogen die Zeile oben mit aufnehmen — sofern die
  App überhaupt mit Weg 2 oder 3 ausgeliefert wird. Läuft sie nur mit Apple
  Intelligence, entsteht keine zusätzliche Kategorie.
- Prüfen, ob der Proxy-Pfad im Release aktiv sein soll
  (`AI_PROXY_BASE_URL` in `project.yml`). Leer = aus.

## Bei Einführung der Paywall (Phase 6, StoreKit 2)

Sobald der Einmalkauf kommt: In-App-Käufe werden über Apples eigene
Transaction-API abgewickelt — Kaufhistorie/Zahlungsdaten laufen über
Apple, nicht über eigene Server, daher i. d. R. **keine** zusätzliche
Kategorie nötig (kein „Purchase History" durch den Entwickler erhoben).
Diesen Abschnitt beim Umsetzen von Phase 6 noch einmal gegenprüfen.

## Altersfreigabe (Age Rating, separater App-Store-Connect-Fragebogen)

Unbedenklich für „4+": keine Gewalt/Nacktheit/Glücksspiel-Inhalte. Zu
beachten: „Unrestricted Web Access" = Nein (kein In-App-Browser mit
freiem Web-Zugriff), aber **„User Generated Content"** = Ja (Tandem-Chat,
Profile) → zieht in Apples Fragebogen typischerweise ein Mindestalter
von 17+ nach sich, *außer* wirksame Moderation ist nachgewiesen. Dafür
ist bereits vorhanden (siehe App-Review-Nachweis unten): Melden/Blockieren,
Wortfilter (`CommunityModeration.swift`), keine unmoderierten Freitext-Profile
ohne Report-Möglichkeit. Trotzdem im Formular ehrlich „Enthält
nutzergenerierte Inhalte: Ja" ankreuzen — Apple entscheidet die Alterseinstufung
daraus selbst.

**KI-generierte Inhalte:** Der KI-Chat erzeugt Text, den wir nicht
vorab kontrollieren. Apple verlangt dafür eine klare Kennzeichnung; die
ist umgesetzt: Der Partner heißt überall sichtbar „… (KI)"
(`AIPersona.displayName`), trägt ein Funkel-Symbol statt eines Fotos,
und über dem Chat steht dauerhaft „Du chattest mit einer KI, nicht mit
einem Menschen." Ausgehende Nachrichten laufen zusätzlich durch den
bestehenden Wortfilter (`ContentFilter`); eingehende sind durch die
Sicherheitsfilter des Modells abgedeckt (`stop_reason: "refusal"` wird
behandelt). Statt „Melden" gibt es beim KI-Partner „Gespräch neu starten" —
melden ergibt bei einem Bot keinen Sinn.
