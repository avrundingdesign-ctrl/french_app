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

**Dritte:** Keine — CloudKit ist Apples eigene Infrastruktur, kein
Analytics-/Advertising-/Crash-SDK verbaut (siehe `grep` über
`FrenchApp/` auf Analytics/Firebase/AdMob/Crashlytics/Sentry — leer).

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
