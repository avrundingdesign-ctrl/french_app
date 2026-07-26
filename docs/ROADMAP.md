# Roadmap

Fortschreibung der Phasen aus `SPEC.md` (dort: Phase 1–3, alle umgesetzt).
Stand 2026-07-09: Lernpfad A1→B2 komplett (96 Lektionen, 1482 Vokabeln,
35 Pakete, Prüfungen A1–C1, Hörtraining, Vertiefungen), Tandem-Community
auf Branch `v2_Online` inkl. Moderation store-reif.

## Phase 4 — Betrieb & Feinschliff (teilweise offen)

- [ ] Apple-Developer-Setup: iCloud- + Push-Capability, CloudKit-Container
      und Indizes (`docs/V2_ONLINE.md`), Gerätetest des CloudKit-Pfads
- [x] App-Store-Vorbereitung (Teil 1, 2026-07-12): Datenschutzerklärung
      auf trin.studio/datenschutz.html um FrenchApp-Abschnitt erweitert,
      Privacy-Label-Mapping in `docs/APP_PRIVACY.md`, Support-/Rechtliches-
      Links in SettingsView (Datenschutz, Impressum, Support-Mail).
      Noch offen: Screenshots, Altersfreigabe-Fragebogen final ausfüllen
      (Vorlage in APP_PRIVACY.md)
- [ ] `v2_Online` → `main` mergen (nach Gerätetest)
- [ ] Optional: FSRS-Opt-in, XCUITests, weitere Wortschatz-Runden
      (Ziel ~2500 Wörter für belastbares B2), Unblock-UI

## Phase 5 — Deutsch-Integration (umgekehrte Lernrichtung FR → DE)

**Warum zuerst:** Das Tandem lebt davon, dass echte Franzosen in der App
sind — und die sind nur da, wenn sie hier **Deutsch lernen** können.
Die umgekehrte Lernrichtung ist damit Voraussetzung für ein
funktionierendes Tandem-Netzwerk, nicht bloß ein Zusatzfeature.

**Stand 2026-07-09: Stufe 5a ist umgesetzt** — Richtungswahl im Onboarding
und in den Einstellungen (verlustfreier Wechsel), deutscher A1-Kurs
(24 Lektionen, 203 Vokabeln wiederverwendet), GermanConjugator
(100 Verben, Präsens/Perfekt/Präteritum/Imperativ), 23 Grammatikregeln
auf Französisch, Goethe-Stil-A1-Prüfung, Hörtraining mit de-DE-Stimme
und 24 Minimalpaaren, SRS-Trennung per `de:`-Präfix, String-Katalog mit
~140 französischen UI-Übersetzungen (Rest fällt auf Deutsch zurück —
Übersetzung iterativ erweiterbar).

### Stufe 5a — Minimal nutzbar für Franzosen (Tandem-Enabler)

1. **Richtungswahl im Onboarding:** „Ich spreche Deutsch → lerne
   Französisch" / « Je parle français → j'apprends l'allemand ».
   Neues Feld in `UserSettings` (courseDirection); Tandem-Profil
   übernimmt die Muttersprache daraus.
2. **Französische UI:** komplette Lokalisierung über String-Katalog
   (aktuell sind alle Texte deutsch hartkodiert — mechanisch, aber
   flächig; betrifft auch Fehlermeldungen, Prüfungs- und Zertifikatstexte).
3. **Deutsch-Kurs A1** (24 Lektionen, gespiegelte Struktur in eigener
   `course_de.json`): Vokabelpaare sind wiederverwendbar (fr/de +
   Beispielsätze existieren schon beidseitig), aber Übungs-Specs,
   Erklärungen und Notizen müssen auf Französisch neu verfasst werden.
4. **Deutscher Konjugator (regelbasiert, selbst verfasst):** Präsens,
   Präteritum, Perfekt (haben/sein!), Futur I, Imperativ; starke Verben
   mit Ablaut, trennbare Präfixe. Gleiche Lizenz-Regel wie beim
   französischen: keine GPL-Quellen.
5. **Deutsche Grammatikregeln A1 auf Französisch** (~20 Regeln:
   der/die/das, Akkusativ, Satzklammer, Modalverben, Perfekt …).
6. **SRS-Trennung:** `ReviewState` ist per vocabID unique — gleiche
   Vokabel in beiden Richtungen würde den Lernstand mischen. Lösung:
   Richtungs-Feld bzw. richtungs-präfixierte IDs + Migration.
7. Hörtraining/TTS mit `de-DE`-Stimme.

### Stufe 5b — Vollausbau

**Stand 2026-07-10: A2-Tranche umgesetzt** — 24 weitere Lektionen
(Dativ, Wechselpräpositionen, Pronomen Akk./Dat., Komparativ/Superlativ,
Ordinalzahlen, Futur, Reflexivverben, weil/dass/wenn-Nebensätze,
Modalverben-Präteritum), 18 A2-Grammatikregeln auf Französisch,
30 neue Verben (inkl. Reflexive „sich waschen" und Futur im
GermanConjugator), Goethe-Stil-A2-Prüfung, 4 gespiegelte A2-Pakete.

**Stand 2026-07-13: Konjugator-Ausbau + B1-Tranche umgesetzt** —
GermanConjugator bildet jetzt Präteritum für alle Verbklassen
(schwach regelbasiert, stark/gemischt über `praeteritumStem`),
Plusquamperfekt (Präteritum von haben/sein + Partizip II) und
Konjunktiv II (Tabellen für sein/haben/werden/wissen/Modalverben +
häufige starke Verben, sonst würde-Form). 18 neue B1-Grammatikregeln
auf Französisch (Adjektivdeklination, Genitiv, Passiv, Konjunktiv II,
Plusquamperfekt, Relativsätze, indirekte Fragen, weitere Nebensätze,
Finalsätze, Doppelkonnektoren) und 24 B1-Lektionen (6 Einheiten) —
komplett auf den schon zweisprachigen 112 B1-Vokabeln der
Französisch-Richtung aufgebaut, kein neues Vokabular nötig.

Noch offen in 5b:
- Deutsch-Kurs B2 (24 weitere Lektionen), Grammatik B2 (z. B. Konjunktiv I
  für indirekte Rede, erweiterte Partizipialkonstruktionen, Nominalstil)
- Prüfungen B1/B2 im Goethe-Stil
- Vertiefungskapitel für die DE-Richtung
- Restliche UI-Übersetzungen ins Französische

**Größter Aufwand:** Content (Kurs, Grammatik, Prüfungen auf Französisch);
Code-Anteil überschaubar (Richtungslogik, Lokalisierung, Konjugator).

## Phase 6 — Monetarisierung: Paywall (StoreKit 2)

**Prinzip:** Einstieg und Netzwerk bleiben frei, Tiefe kostet.

- **Frei:** kompletter A1+A2-Lernpfad, Basis-Wortschatzpakete,
  Tandem-Community (Netzwerkeffekt nicht ausbremsen!), SRS-Trainer.
- **Premium:** B1/B2-Wortschatzpakete, Grammatik-Übungsmodus über die
  ersten Themen hinaus, Vertiefungskapitel, Prüfungssimulationen B2/C1.
- **Produkt:** zunächst ein einziger **Einmalkauf** („Premium
  freischalten", non-consumable, Familienfreigabe an) — einfachster
  Review und keine Abo-Verwaltung; Abo später evaluierbar.
- **Umsetzung:** `premium: true`-Flag in den Content-JSONs;
  `PremiumStore` (StoreKit 2, `Transaction.currentEntitlements`);
  Paywall-Screen mit Feature-Liste; **Restore-Button (Apple-Pflicht)**;
  Schloss-Badges an gesperrten Inhalten; Produkt in App Store Connect.
- **Achtung Lizenz:** Vor kommerziellem Verkauf die CC-BY-SA-Frage aus
  `SPEC.md` prüfen — aktuell unkritisch, da der gesamte Content selbst
  verfasst ist; das muss auch für Phase-5-Content so bleiben.

**Stand 2026-07-13: umgesetzt.** `PremiumStore` (StoreKit 2:
`Transaction.currentEntitlements` + `updates`-Listener, purchase,
`AppStore.sync()`-Restore), Gating als pure Logik in `PremiumGate`
(statt `premium`-Flags in den JSONs — Niveau-basiert, damit auch der
wachsende Phase-5-Content automatisch richtig einsortiert wird):
Lektionen und Pakete ab B1 Premium, Prüfungen ab B2, Vertiefungen
komplett; A1+A2, SRS, Hörtraining und Tandem frei — in beiden
Kursrichtungen. Paywall-Sheet mit Feature-Liste, Preis aus dem Product,
Restore, Familienfreigabe-Hinweis; Krone-Badges an allen Sperren
(Lernpfad, Pakete, Prüfungen, Vertiefungen), Premium-Sektion in den
Einstellungen. Lokales Testing über `Configuration.storekit`
(im Scheme hinterlegt, 9,99 €); Dev-Flags `--premium`/`--unlock-all`/
`--show-paywall` für Reviews und Screenshots. 7 neue Tests sichern
die Gating-Entscheidungen und die Substanz der freien Zone ab.

**Noch offen für den Launch:** Produkt
`design.avrunding.frenchapp.premium` in App Store Connect anlegen
(non-consumable, Familienfreigabe an, Preis festlegen) und einen
Kauf-Durchlauf im Sandbox-Account auf echtem Gerät testen.

## Phase 7 — KI-Gesprächspartner & Übersetzen auf Tippen

**Warum:** Der Tandem-Bereich lebt vom Netzwerkeffekt — und genau der
fehlt am Anfang. Findet die Partnersuche niemanden, konnte der Nutzer
bisher nur warten. Ein KI-Partner überbrückt das nicht nur, er ist als
Dauer-Option auch dann sinnvoll, wenn Partner da sind: sofort verfügbar,
endlos geduldig, jederzeit auf dem passenden Niveau.

**Sprachlogik.** Im Tandem schreibt jeder in *seiner* Lernsprache; die KI
dreht das um und schreibt durchgehend in der **Lernsprache des Nutzers** —
sie übt nichts, sie ist Muttersprachlerin. Das Verständnis sichert das
Antippen ab.

**Übersetzen auf Tippen** gilt jetzt in beiden Chats nach einer Regel:
*Tippen zeigt die Nachricht in der jeweils anderen Sprache.* Für
Partner-Nachrichten bleibt die Übersetzung die Standardanzeige
(Immersion, unverändert); eigene Nachrichten und KI-Antworten lassen sich
neu in die Muttersprache umschalten — nützlich für „habe ich das gerade
richtig gesagt?". Primär übersetzt Apple Translation on-device (offline,
kostenlos, ab iOS 18); fällt das aus (iOS 17, Sprachmodell nicht geladen),
springt die KI ein — deshalb heißt „immer" jetzt wirklich immer.

**Umsetzung:** `AIPartner.swift` (Persona, System-Prompt, Anbindung an die
Anthropic Messages API über `URLSession` — für Swift gibt es kein
offizielles SDK), `AIKeyStore.swift` (Keychain), `AIChatStore.swift`
(Verlauf lokal als JSON, bewusst weder SwiftData noch CloudKit),
`AIChatView.swift` (Chat, Einrichtung, Gesprächseinstiege, Niveau-Picker).
`TranslationService.swift` wurde auf beliebige Sprachpaare verallgemeinert
(`TranslationBridge`), `ChatView` nutzt zwei Bridges — eine automatisch für
Partner-Nachrichten, eine auf Anfrage für die Gegenrichtung.

**Entscheidungen (jeweils an einer Stelle umstellbar):**
- **Key:** eigener Anthropic-Key pro Nutzer, im Schlüsselbund. Kein
  eingebauter Key — der wäre aus dem Binary auslesbar, und dann chatten
  Fremde auf fremde Rechnung. Für einen breiten Release mit KI für alle
  führt langfristig kein Weg an einem eigenen Proxy vorbei.
- **Modell:** `claude-opus-4-8` (`ClaudeAIPartnerService.model`).
- **Zugang:** frei, kein Limit — passend zum Eigener-Key-Modell.
  Tageslimit oder Premium-Gating (`PremiumStore.isPremium`) sind
  nachrüstbar.

**Noch offen:** Datenschutzerklärung auf `trin.studio` um Anthropic als
Empfänger ergänzen (Details in `APP_PRIVACY.md`), und den Flow einmal auf
echtem Gerät mit echtem Key durchspielen — im Container gibt es keinen
Swift-Compiler, der Code ist ungebaut geschrieben.
