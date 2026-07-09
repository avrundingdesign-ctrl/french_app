# Roadmap

Fortschreibung der Phasen aus `SPEC.md` (dort: Phase 1–3, alle umgesetzt).
Stand 2026-07-09: Lernpfad A1→B2 komplett (96 Lektionen, 1482 Vokabeln,
35 Pakete, Prüfungen A1–C1, Hörtraining, Vertiefungen), Tandem-Community
auf Branch `v2_Online` inkl. Moderation store-reif.

## Phase 4 — Betrieb & Feinschliff (teilweise offen)

- [ ] Apple-Developer-Setup: iCloud- + Push-Capability, CloudKit-Container
      und Indizes (`docs/V2_ONLINE.md`), Gerätetest des CloudKit-Pfads
- [ ] App-Store-Vorbereitung: Datenschutzerklärung, Privacy Labels,
      Support-Kontakt, Screenshots, Altersfreigabe
- [ ] `v2_Online` → `main` mergen (nach Gerätetest)
- [ ] Optional: FSRS-Opt-in, XCUITests, weitere Wortschatz-Runden
      (Ziel ~2500 Wörter für belastbares B2), Unblock-UI

## Phase 5 — Deutsch-Integration (umgekehrte Lernrichtung FR → DE)

**Warum zuerst:** Das Tandem lebt davon, dass echte Franzosen in der App
sind — und die sind nur da, wenn sie hier **Deutsch lernen** können.
Die umgekehrte Lernrichtung ist damit Voraussetzung für ein
funktionierendes Tandem-Netzwerk, nicht bloß ein Zusatzfeature.

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

- Deutsch-Kurs A2→B2 (72 weitere Lektionen), Grammatik B1/B2
  (Adjektivdeklination, Passiv, Konjunktiv II, Nebensätze …)
- Prüfungen im Goethe-/telc-Stil, Zertifikate pro Richtung
- Wortschatz-Pakete gespiegelt (Notizen/Untertitel auf Französisch)
- Vertiefungskapitel für die DE-Richtung

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

**Reihenfolge:** erst Phase 5a (sonst kauft niemand auf der
FR-Seite), Paywall kann parallel zu 5b kommen, da sie primär die
bestehende DE→FR-Seite betrifft.
