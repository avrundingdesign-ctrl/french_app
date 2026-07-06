# Technisches & Didaktisches Konzept: iOS-App „Französisch lernen A1–B2" (Deutsch → Französisch)

> **Zweck dieses Dokuments:** Vollständiges Spec-/Briefing-Dokument zur Weitergabe an Claude Code (als `.md` speichern). Native iOS-App, Swift/SwiftUI, offline-first, **ohne Streaks/Gamification-Streaks**, **ohne Audio**, **mit Grammatik-Engine**, **mit Vokabeltrainer + Spaced Repetition**. Lernrichtung Deutsch → Französisch, Zielgruppe absolute Anfänger (0 Vorwissen) mit Durchführung durch A1 → A2 → B1/B2.

---

## TL;DR
- **Tech-Stack:** SwiftUI + **SwiftData** (iOS 17+), vollständig offline. Statische Inhaltsdaten (Vokabeln, Grammatik, Konjugationen, Beispielsätze) als **gebündelte read-only SQLite-Datenbank**; veränderlicher Nutzerfortschritt in SwiftData. Kein Backend nötig.
- **Spaced Repetition:** **SM-2** (SuperMemo 2, erstmals eingesetzt in SuperMemo 1.0 für DOS am 13. Dezember 1987, entwickelt von Piotr Woźniak) als Basis — einfach, bewährt, erklärbar und für Decks unter ~1000 Karten praktisch gleich effizient wie modernere Verfahren. FSRS optional als späteres Upgrade.
- **Grammatik-Engine + Curriculum:** regelbasierter französischer Konjugator (3 Verbgruppen + Ausnahmentabelle) plus deklarativer Grammatikregel-Speicher; CEFR-Lernpfad A1→A2→B1→B2 mit sequenzieller Freischaltung. **Wichtigste Lizenzwarnung:** Fast alle offenen französischen Konjugationsdaten stammen von **Verbiste (GPLv2)** — für eine kommerzielle Closed-Source-App muss die Konjugationslogik/-daten aus permissiv lizenzierten oder eigenen Quellen aufgebaut werden.

---

## Key Findings
1. **SM-2 ist die richtige Wahl für den Start.** Der Algorithmus (Woźniak, 1987) ist stateless zwischen Reviews (außer Ease-Faktor + letztes Intervall), einfach zu implementieren und dem Nutzer erklärbar. **FSRS** (Free Spaced Repetition Scheduler, seit 2022, Standard in Anki seit v23.10) erreicht laut dem open-spaced-repetition-Benchmark (über 700 Mio. Reviews, ~20.000 Anki-Nutzer) dieselbe 90%-Retention mit rund **30% weniger Wiederholungen** und hat in **99,6% der Sammlungen einen niedrigeren Log-Loss** als SM-2 (FSRS-6 mit Nutzeroptimierung: mittlerer Log-Loss 0,344) — diese Zahlen stammen jedoch aus Simulation auf Logdaten, nicht aus kontrollierten Studien. Für ein Anfänger-Vokabeldeck rechtfertigt der Effizienzvorteil die Zusatzkomplexität anfangs nicht.
2. **Lizenz-Falle bei Konjugationsdaten.** Verbiste, verbecc und mlconjug3 leiten ihre französischen Konjugationsdaten alle von **Verbiste** ab (GPLv2-or-later). Der Autor stellt ausdrücklich klar, dass auch eine Formatkonvertierung der Daten unter GPL weitergegeben werden muss — der „Tabelle vorgenerieren und nur Daten ausliefern"-Trick umgeht die Copyleft-Pflicht **nicht**.
3. **CEFR-Grammatikprogression ist gut dokumentiert** und lässt sich fast 1:1 in einen datengetriebenen Lernpfad übersetzen (siehe Curriculum unten).
4. **Kein Audio ist kein Nachteil für den Kern.** Alle didaktisch wichtigen Übungstypen für Anfänger (Multiple Choice, Cloze, Übersetzung, Matching, Satzbau, Konjugation) funktionieren rein textbasiert. Nur Hör-/Ausspracheübungen entfallen.

---

## Details

### 1. App-Struktur & Screens

**Orientierung an bestehenden Apps:**
- **Duolingo:** gamifizierter Lernpfad („Baum"/Pfad), sehr kurze Lektionen, „play first, profile second"-Onboarding, wenig explizite Grammatik. Stark bei Gewohnheitsbildung (für uns nur teilweise relevant, da keine Streaks).
- **Babbel:** strukturierter, **CEFR-orientiert (A1–B2)**, integriert Grammatik direkt in Lektionen mit kurzen 1–2-Satz-Erklärungen gefolgt von Drill-Übungen (Fill-in-the-blank). Genau das gewünschte Modell für diese App.
- **Busuu/Memrise:** thematische Lektionen + Vokabelreview.
- **Anki:** reines SRS-Karteikartensystem — Vorbild für den Vokabeltrainer-Teil.

**Vollständige Screen-Liste (mit Zweck & Kernelementen):**

| # | Screen | Zweck | Kernelemente |
|---|--------|-------|--------------|
| 1 | **Onboarding** | Ersteinstieg ohne Reibung | Zielabfrage, Einstufung (Anfänger startet automatisch A1), optionaler Test; Profilerstellung **nach** erster Lektion (Duolingo-Prinzip); kein Login-Zwang |
| 2 | **Home / Lernpfad** | Zentraler Hub, Orientierung | Vertikaler Pfad der Lektionen gruppiert nach Niveau (A1→A2→B1→B2), Freischalt-Status, Fortschrittsbalken pro Niveau, Button „Fällige Wiederholungen" |
| 3 | **Lektions-/Übungsseite** | Eine Lernsequenz durchführen | Aufeinanderfolgende Übungen, Fortschrittsleiste oben, sofortiges Feedback (richtig/falsch + Erklärung), „Weiter"-Button |
| 4 | **Vokabeltrainer / Review** | SRS-Session | Karten, die heute fällig sind; Selbstbewertungs-Buttons (siehe SM-2); Zähler verbleibender Karten |
| 5 | **Grammatik-Seite (Übersicht + Detail)** | Nachschlagen & Lernen | Grammatikthemen nach Niveau; Detailseite mit Erklärung (Deutsch), Beispielen, interaktiven Konjugationstabellen, verknüpften Übungen |
| 6 | **Profil / Statistik** | Fortschritt sichtbar machen | Anzahl gelernter/gefestigter Wörter, beherrschte Grammatikthemen, Fortschritt pro CEFR-Niveau, Balken/Ringe — **KEINE Streaks, keine Ligen/Leaderboards** |
| 7 | **Einstellungen** | Personalisierung | Tägliches Pensum (Kartenzahl), Ziel-Retention, Wiederholung zurücksetzen, Datenexport, Erscheinungsbild |
| 8 | **Fehler-/Wiederholungsübersicht** | Gezielte Schwächen üben | Automatisch gesammelte falsch beantwortete Items; „Fehler üben"-Session |
| 9 | **Lektions-Ergebnis** | Abschluss & Motivation | Zusammenfassung (neu gelernt, Fehler), was als Nächstes freigeschaltet wird |

---

### 2. Übungstypen (rein textbasiert, ohne Audio)

| Übungstyp | Beschreibung | Eignet sich für |
|-----------|--------------|-----------------|
| **Multiple Choice** | Aus 3–4 Optionen die richtige Übersetzung/Form wählen | Einführung neuer Vokabeln, Rekognition (leichtester Einstieg für A1) |
| **Übersetzung DE→FR** | Deutschen Satz/Wort ins Französische übersetzen (Freitext oder Wortbausteine) | Aktive Produktion (schwieriger) |
| **Übersetzung FR→DE** | Umgekehrt | Passives Verständnis (leichter, gut für Anfang) |
| **Lückentext (Cloze)** | Fehlendes Wort/Form einsetzen | Grammatik im Kontext: Konjugationen, Artikel, Präpositionen |
| **Wortpaare zuordnen (Matching)** | FR- und DE-Wörter verbinden | Schnelle Vokabelfestigung, geringe kognitive Last |
| **Satzbau / Wörter ordnen** | Vorgegebene Wörter in richtige Reihenfolge ziehen | Syntax & Wortstellung (z. B. Pronomen-Position, Negation) |
| **Konjugationsübung** | Verb in geforderter Zeit/Person eingeben | Kern der Grammatik-Engine; Verbtraining |
| **Deklinations-/Artikelübung** | Richtigen Artikel/Genus wählen | Genus, bestimmte/unbestimmte/Teilungsartikel |
| **Fehlerkorrektur** | Fehlerhaften Satz finden/korrigieren | B1/B2 (z. B. Subjonctif vs. Indikativ, participe-passé-Angleichung) |

**Didaktisches Prinzip:** neue Items zuerst mit rekognitiven Typen (Multiple Choice, Matching, FR→DE), dann produktive Typen (DE→FR, Cloze, Konjugation) — steigende Schwierigkeit innerhalb einer Lektion.

---

### 3. Spaced Repetition / Vokabeltrainer

**Empfehlung: SM-2 als Start-Algorithmus.**

SM-2 wurde von Piotr Woźniak entwickelt und erstmals in SuperMemo 1.0 für DOS am 13. Dezember 1987 eingesetzt; es war der erste Computeralgorithmus zur Berechnung des optimalen Wiederholungszeitpunkts im Spaced Repetition.

**Zustand pro Karte:** `easeFactor` (Ease-Faktor), `repetitions` (Zähler erfolgreicher Wiederholungen in Folge), `interval` (Tage bis nächste Fälligkeit), `nextReview` (Datum).

**Ablauf (kanonisches SM-2):**
1. Nutzer bewertet die Erinnerung mit Qualität **q ∈ 0–5** (0 = totaler Blackout, 3 = richtig mit Mühe, 5 = perfekt). Praktisch kann man dies auf 3–4 Buttons mappen (z. B. „Nochmal / Schwer / Gut / Einfach"), wie es Anki tut.
2. **Wenn q ≥ 3 (richtig):**
   - `repetitions == 0` → `interval = 1` Tag
   - `repetitions == 1` → `interval = 6` Tage
   - `repetitions > 1` → `interval = round(interval_vorher × easeFactor)`
   - `repetitions += 1`
3. **Wenn q < 3 (falsch):** `repetitions = 0`, `interval = 1` (Karte kommt morgen wieder).
4. **Ease-Faktor immer aktualisieren:**
   `easeFactor = easeFactor + (0.1 − (5 − q) × (0.08 + (5 − q) × 0.02))`
5. **Untergrenze:** `if easeFactor < 1.3 → easeFactor = 1.3`.

**Startwerte:** In Woźniaks Originalbeschreibung durften E-Factors zwischen 1,1 (schwerste Items) und 2,5 (leichteste) variieren; der Standard-Startwert ist **2,5**. Anki setzt die Untergrenze in seiner Implementierung auf **1,3**. Diese 1,3-Untergrenze wird für diese App übernommen.

**Alternativen (im Konzept dokumentiert, aber nicht für Start empfohlen):**
- **Leitner-System:** 5 Boxen mit festen Intervallen, sehr einfach, aber keine per-Karte-Personalisierung. Gut für <200 Karten; für ein wachsendes A1–B2-Vokabular unterlegen.
- **FSRS:** modelliert Difficulty/Stability/Retrievability pro Karte, ~30% weniger Reviews bei gleicher Retention, aber 21 Parameter und Trainingslogik. **Empfehlung:** später als opt-in-Upgrade; SM-2-Reviewhistorie kann später zu FSRS migriert werden.

**Vokabeltrainer-Logik:**
- Neue Wörter werden aus der aktuellen Lektion in den SRS-Pool eingespeist.
- Täglich werden fällige Karten (`nextReview <= heute`) plus ein Limit neuer Karten gezeigt (Pensum in Einstellungen).
- **Fehler aus Lektionsübungen** setzen automatisch das zugehörige `ReviewState` zurück (personalisierte Fehlerwiederholung).

---

### 4. Grammatik-Engine (Konzept)

**Zwei entkoppelte Komponenten:**

#### A) Regelbasierter Konjugator
Französische Verben zerfallen in **drei Gruppen**:
- **1. Gruppe (-er):** Laut Elon.io French Grammar enthält die erste Gruppe „roughly 90% of all French verbs — most counts put it at over 6,000 — and it is the only group that is still productive"; jedes -er-Verb folgt dem Modellverb *parler* im Präsens Indikativ — mit einer berühmten Ausnahme, dem unregelmäßigen *aller*. Präsens-Endungen: **-e, -es, -e, -ons, -ez, -ent**.
- **2. Gruppe (-ir mit Partizip -issant):** Endungen **-is, -is, -it, -issons, -issez, -issent** (Modell *finir*).
- **3. Gruppe (unregelmäßig):** -re-Verben, unregelmäßige -ir-Verben, *aller*, *être*, *avoir* etc. — als Ausnahmen-Datentabelle.

**Algorithmus:** Stamm (*radical*) = Infinitiv minus Endung; passende Endung nach Gruppe/Zeit/Person anhängen. Unregelmäßige Formen und Stammänderungen (z. B. *tenir → tien-*) werden aus einer Tabelle geladen, nicht generiert. Zusammengesetzte Zeiten (passé composé, plus-que-parfait) = Hilfsverb (*avoir*/*être*) konjugiert + participe passé (mit Angleichungsregeln).

> **Umsetzungshinweis:** Konjugationstabellen sollten **build-time** aus einer sauberen Quelle vorgeneriert und als statische Daten ausgeliefert werden (kein Runtime-Konjugator nötig). **Aber:** siehe Lizenzabschnitt — die Datenquelle darf nicht Verbiste-abgeleitet sein.

#### B) Deklarativer Grammatikregel-Speicher
Jede Grammatikregel als Datenobjekt: Titel, **Erklärung auf Deutsch**, Beispielsätze (FR + DE), CEFR-Niveau, verknüpfte Übungen und ggf. verknüpfte Konjugationsmuster. So sind Erklärungen redaktionell pflegbar und die Engine bleibt datengetrieben statt hartkodiert. Didaktischer Aufbau pro Regel: kurze Regel → Beispiel → Gegenbeispiel/typischer Fehler → Übung (analog Babbels integriertem Grammatikansatz).

---

### 5. Datenquellen — konkret, mit Lizenzen

> **Zentrale Erkenntnis:** Vokabel- und Beispielsatzdaten sind aus offenen Quellen gut verfügbar. **Konjugationsdaten sind das Lizenzproblem.**

**Vokabeln & Frequenz:**
- **Lexique.org (Lexique 3.83 / Lexique 4)** — laut lexique.org „a database that provides various information for 140,000 French words" inkl. Frequenz, Genus, grammatischer Kategorie, Lemma, Silbenzahl; **Lizenz CC BY-SA**. Lexique 3.83 basiert auf Untertiteln von 9.474 Filmen/Serien (52 Mio. Wörter) plus 218 Büchern (14,7 Mio. Wörter). **Ideal für Frequenz-basierte Vokabelauswahl** (welche Wörter zuerst lehren). Download als TSV: `http://www.lexique.org/databases/Lexique383/Lexique383.tsv`. Python-Wrapper: `pylexique`.
- **Français fondamental** — klassische Grundwortschatzliste (~1500 Wörter), historisch, als didaktische Referenz für A1/A2-Priorisierung.

**Deutsch↔Französisch-Übersetzungen:**
- **DBnary** (`kaiko.getalp.org`) — Wiktionary als RDF/Ontolex, **CC BY-SA 3.0**, enthält DE- und FR-Einträge inkl. Übersetzungen (Französisch ~322 K Einträge). Zweiwöchentliche Updates, DOI-versioniert auf Zenodo.
- **Wiktextract / kaikki.org** — geparste Wiktionary-Daten als JSON (Übersetzungen, Wortarten, Genus, teils Konjugationen). Tool ist **MIT**, die zugrundeliegenden Wiktionary-Daten **CC BY-SA**.
- **FreeDict** (`freedict.org`) — freie bilinguale Wörterbücher inkl. **Deutsch↔Französisch**, TEI-XML, freie Lizenzen (GPL/CC je Wörterbuch prüfen).

**Beispielsätze:**
- **Tatoeba** (`tatoeba.org/downloads`) — crowdgesourcte Sätze mit Übersetzungen in >400 Sprachen inkl. DE/FR. **Lizenz CC BY 2.0**, ein Teil zusätzlich **CC0 1.0**. Downloads als tab-getrennte Sätze + Links; Python-Tool `tatoebatools`. **Wichtig:** Enthält Fehler (Community-Daten) → für eine Lern-App kuratieren/filtern.

**Konjugationen (⚠️ Lizenz-kritisch):**
- **Verbiste** (Pierre Sarrazin) — XML-Wissensbasis mit über 7.000 französischen Verben (~190 italienische). Laut offizieller Verbiste-Seite: *„Verbiste is free software distributed under the GNU General Public License (version 2 or later). Please note that this means that proprietary software linked with this library cannot be distributed legally. Also, if the XML knowledge base is converted to another format, the result must be shipped [under GPL]."* → **Für eine kommerzielle Closed-Source-App unbrauchbar**, auch als vorgenerierte Tabelle (der Autor schließt die Formatkonvertierung ausdrücklich ein).
- **verbecc** (GitHub `bretttolbert/verbecc`) — Code unter **LGPL-3.0**, aber die französischen Konjugations-XML sind laut README „derived from Pierre Sarrazin's C++ program Verbiste" → tragen dieselbe GPL-Copyleft-Last auf den Daten.
- **mlconjug3** (GitHub `Ars-Linguistica/mlconjug3`) — Code unter **MIT** (sauber für kommerziellen Einsatz, nur Attributionspflicht), ML-basiert und kann sogar unbekannte/erfundene Verben konjugieren. **Aber:** laut README „created with the help of Verbiste" → die französischen Trainingsdaten stammen wieder aus Verbiste; die MIT-Lizenz des Codes klärt die Provenienz der Daten nicht.

> **Fazit Konjugationsdaten:** Für eine proprietäre App entweder (a) Konjugationen **regelbasiert selbst generieren** (die 3-Gruppen-Endungen sind Gemeingut/nicht schützbar, nur eine begrenzte Liste unregelmäßiger Verben muss eigenständig aus einer permissiven Quelle wie CC BY-SA-Wiktionary/DBnary aufgebaut werden), oder (b) `mlconjug3` (MIT-Code) nur als **Werkzeug** nutzen und die Verbliste/-formen aus einer Nicht-Verbiste-Quelle beziehen. Vor kommerzieller Nutzung juristisch prüfen lassen.

**CEFR-Wortlisten:** diverse (FrenchLearner, Kwiziq, Lawless French) — meist **ohne offene Lizenz**, nur als **redaktionelle Referenz** für die Themenauswahl nutzen, nicht 1:1 kopieren. Die eigene CEFR-Zuordnung kann durch Kombination von Lexique-Frequenz + Grammatikprogression selbst erstellt werden.

---

### 6. CEFR-Curriculum (A1 → B2), Deutsch-Erklärungen, Lernpfad

Grammatikprogression (basierend auf dokumentierten CEFR-Grammatikinventaren; Kernzeiten pro Niveau):

**A1 (Découverte / Einstieg):**
- *Grammatik:* Präsens regelmäßiger Verben (1./2. Gruppe) + *être, avoir, faire, aller, venir, pouvoir, vouloir, devoir*; bestimmte/unbestimmte/Teilungsartikel (le/la/les, un/une/des, du/de la); Genus & Numerus, Adjektiv-Angleichung; Negation *ne…pas*; Frageformen (*est-ce que / qu'est-ce que*); Possessiv-/Demonstrativadjektive; *il y a*; **futur proche** (*aller* + Inf.); Einführung **passé composé**; Zahlen; Subjektpronomen + Tonika.
- *Vokabelfelder:* Begrüßung/Vorstellung, Familie, Zahlen/Uhrzeit, Essen/Trinken, Alltag, einfache Reise.

**A2 (Survie / Grundlage):**
- *Grammatik:* **imparfait**, **futur simple**, passé composé vertieft (Angleichung *être*); Reflexivverben; Pronomen COD/COI, **en/y**; Komparativ; *il faut* + Inf.; *si* + Präsens (Bedingung); Relativpronomen *qui/que/où*; Ordinalzahlen; Präpositionen des Orts/der Zeit.
- *Vokabelfelder:* Wohnen, Einkaufen, Gesundheit, Freizeit, erweiterte Reise, Arbeit (Basis).

**B1 (Seuil / Schwelle):**
- *Grammatik:* **Subjonctif présent** (Einführung, nach *il faut que*, Verben des Wunsches/Gefühls); **conditionnel présent + passé**; **plus-que-parfait**; Relativpronomen *dont*; **Gérondif**; participe présent; indirekte Rede; Hypothesen-System (*si* + imparfait/conditionnel etc.); Passiv; *ne…que* (Restriktion); doppelte Pronomen.
- *Vokabelfelder:* Meinung/Argumentation (Basis), Beruf, Erfahrungen/Pläne, Umwelt, Medien.

**B2 (Avancé):**
- *Grammatik:* alle zusammengesetzten Zeiten; **Subjonctif vertieft** (+ Konjunktionen, subjonctif vs. indicatif); **futur antérieur**; infinitif passé; **passé simple** (nur Erkennung/Lesen); participe-passé-Angleichungsregeln vollständig (inkl. pronominale Verben); komplexe Konnektoren (Konzession, Ziel, Ursache/Folge, Opposition).
- *Vokabelfelder:* abstrakte/argumentative Themen, Fachsprache-Basis, Nuancen, Idiomatik.

**Lernpfad-Struktur:** Niveaus → Einheiten (Vokabelfeld + zugehörige Grammatikthemen) → Lektionen (je 8–15 Übungen). Sequenzielle Freischaltung: nächste Lektion erst nach Abschluss der vorigen; neue Vokabeln jeder Lektion wandern in den SRS-Pool. Grammatikthemen sind mit den Lektionen verknüpft, aber jederzeit über die Grammatik-Seite nachschlagbar.

---

### 7. Kernfunktionen (ohne Streaks, ohne Audio)

- **Fortschritts-Tracking** pro Niveau, Lektion und einzelnem Wort/Grammatikthema.
- **SRS-Wiederholungssystem** (SM-2) als eigenständiger täglicher Trainingsmodus.
- **Lektions-Freischaltung** (sequenziell, freischaltbasiert statt zeitbasiert).
- **Personalisierte Fehlerwiederholung**: falsch beantwortete Items werden gesammelt und priorisiert wiederholt (Reset des `ReviewState`).
- **Profil-Statistiken**: gelernte/gefestigte Wörter, beherrschte Grammatik, Fortschrittsringe pro Niveau.
- **Tägliches Pensum** als konfigurierbares Ziel (Kartenzahl) — **explizit ohne Streak-Zähler, ohne Ligen, ohne Herzen/Leben**.
- **Datenexport/Reset** in Einstellungen.

---

### 8. Technische Architektur (iOS)

**Empfohlener Stack:**
- **UI:** SwiftUI, Deployment Target **iOS 17+**.
- **Nutzerdaten-Persistenz:** **SwiftData** — deklarativ, SwiftUI-nativ (`@Model`, `@Query`), automatische Migrationen (leichtgewichtig), Autosave. Für ein neues Projekt ohne Legacy und mit moderatem Datenmodell die empfohlene Wahl 2025/2026. **Caveat:** SwiftData lädt Objektgraphen eher eager und unterstützt nur leichtgewichtige Migrationen; bei sehr großen Objektgraphen oder komplexen Migrationsanforderungen wäre **Core Data** die robustere Alternative. Für diese App (überschaubarer Nutzerfortschritt) genügt SwiftData.
- **Statische Inhaltsdaten:** Vokabeln, Grammatikregeln, Konjugationstabellen und Beispielsätze als **read-only SQLite-Datei im App-Bundle** (performant, nicht über SwiftData verwaltet, um den Nutzer-Store schlank zu halten). Alternativ vorverarbeitetes JSON, das beim ersten Start in SwiftData/SQLite importiert wird. Empfehlung: **read-only SQLite mit direktem Zugriff** (z. B. via GRDB) für die große Inhaltsmenge, SwiftData nur für veränderlichen Fortschritt.
- **Kein Backend erforderlich** (offline-first). **Optional später:** iCloud/CloudKit-Sync für Fortschritt (SwiftData integriert privates iCloud-Syncing gut; öffentliche CloudKit-DB wäre eher Core-Data-Terrain).

**Datenmodell — Vorschlag (Entitäten & Kernattribute):**

Statische Inhaltsdaten (gebündelt, read-only):
- `Vocabulary`(id, fr, de, wortart, genus, cefrLevel, frequenzRang, lemmaId)
- `Lesson`(id, titel, cefrLevel, einheitId, reihenfolge)
- `Exercise`(id, typ, prompt, correctAnswer, options[], lessonId, vocabId?, grammarRuleId?)
- `GrammarRule`(id, titel, erklärungDE, beispiele[], cefrLevel, typischerFehler)
- `Verb`(id, infinitiv, gruppe, hilfsverb, istUnregelmäßig)
- `VerbConjugation`(verbId, tempus, modus, person, form) — vorgeneriert
- `ExampleSentence`(id, fr, de, quelle, vocabIds[])

Nutzerdaten (SwiftData, veränderlich):
- `ReviewState`(vocabId, easeFactor=2.5, interval, repetitions, nextReview) — **SM-2-Zustand**
- `UserProgress`(lessonId, status[gesperrt/offen/abgeschlossen], score, abgeschlossenAm)
- `GrammarProgress`(grammarRuleId, status)
- `MistakeLog`(exerciseId, vocabId?, timestamp) — für Fehlerwiederholung
- `Settings`(täglichesPensum, neueKartenProTag, zielRetention)

**Build-Pipeline (empfohlen):** Ein Vorverarbeitungsskript (Python) erzeugt die gebündelte SQLite aus den Rohquellen: Lexique (Frequenz/Genus) + DBnary/FreeDict (DE-Übersetzungen) + kuratierte Tatoeba-Sätze + selbst-/regelgenerierte Konjugationen. So bleiben Lizenz- und Kurationsschritte außerhalb der App.

---

## Recommendations

**Phase 1 — MVP (A1):**
1. SwiftUI + SwiftData (iOS 17+) aufsetzen; read-only SQLite für Inhalte via GRDB einbinden.
2. **SM-2** implementieren (Startwerte 2.5 / Untergrenze 1.3; 3–4 Bewertungsbuttons auf q gemappt).
3. Übungstypen zuerst: Multiple Choice, Matching, FR→DE, Cloze, Konjugation.
4. A1-Curriculum (Vokabelfelder + Grammatikthemen oben) als ~30–40 Lektionen; Vokabeln nach **Lexique-Frequenz** priorisieren.
5. Screens 1–6 bauen; Home-Lernpfad + Vokabeltrainer + Grammatik-Seite.

**Phase 2 — Ausbau (A2/B1):**
6. Übungstypen ergänzen: Satzbau, DE→FR-Produktion, Deklinations-/Artikelübung, Fehlerkorrektur.
7. Grammatik-Engine für zusammengesetzte Zeiten + Subjonctif/Conditionnel.
8. Fehlerwiederholungs-Screen + Statistik ausbauen.

**Phase 3 — Reife (B2 + Optimierung):**
9. B2-Grammatik & -Vokabular.
10. Optional **FSRS** als opt-in (SM-2-Historie migrieren) — Benchmark-Schwelle: erst sinnvoll, wenn Nutzer regelmäßig große Deckgrößen (>1000 aktive Karten) erreichen.
11. Optional iCloud-Sync.

**Datenquellen-Strategie (verbindlich):**
- Vokabeln/Frequenz: **Lexique.org** (CC BY-SA).
- DE-FR-Übersetzungen: **DBnary** (CC BY-SA) + **FreeDict**.
- Beispielsätze: **Tatoeba** (CC BY 2.0 / CC0) — kuratiert.
- Konjugationen: **regelbasiert selbst generieren** + unregelmäßige Verben aus CC-BY-SA-Wiktionary/DBnary; **`mlconjug3` (MIT) nur als Tooling**. **Verbiste/verbecc-Daten meiden** (GPL). Attributions- und ShareAlike-Pflichten der CC-BY-SA-Quellen in den App-Credits erfüllen.

**Benchmarks/Schwellen, die Entscheidungen ändern würden:**
- Muss iOS 15/16 unterstützt werden → auf **Core Data** wechseln statt SwiftData.
- Retention der Nutzer bei Vokabeln < ~80% oder sehr große Decks → **FSRS** evaluieren.
- Kommerzielle Verwertung geplant → CC-BY-SA-ShareAlike-Verpflichtung juristisch prüfen (betrifft ggf. die abgeleitete Datenbank, nicht den App-Code); ggf. auf CC0/permissive Quellen oder eigene Redaktion umstellen.

---

## Caveats
- **Lizenzen sind das größte Risiko.** Verbiste-abgeleitete Konjugationsdaten (Verbiste GPLv2, verbecc LGPL-3.0 mit GPL-Daten) dürfen nicht in eine proprietäre App — auch nicht als vorgenerierte Tabelle. `mlconjug3` ist MIT (Code), aber die Datenprovenienz ist zu klären. CC-BY-SA-Quellen (Lexique, DBnary, Tatoeba-CC-BY) erfordern **Attribution** und ggf. **ShareAlike** für die abgeleitete Datenbank. **Keine Rechtsberatung** — vor kommerziellem Release anwaltlich prüfen lassen.
- **FSRS-Effizienzzahlen** (~30% weniger Reviews, 99,6% niedrigerer Log-Loss) stammen aus Simulation auf Anki-Logdaten, nicht aus kontrollierten Live-Studien; die Anki-Nutzerdaten sind zudem in Richtung „Crammer/Prokrastinierer" verzerrt (Kritik u. a. von Woźniak).
- **SwiftData** ist noch vergleichsweise jung: dünnere Community-Wissensbasis, nur leichtgewichtige Migrationen, mögliche Performance-/Sortierungsprobleme bei großen Objektgraphen. Für den (kleinen) Nutzerfortschritt dieser App unkritisch; für die große Inhalts-DB bewusst read-only SQLite außerhalb SwiftData halten.
- **Tatoeba-Daten enthalten Fehler** (Crowdsourcing) und sind nicht durchgehend von Muttersprachlern — Beispielsätze für A1–B2 unbedingt kuratieren/nach Länge & Niveau filtern.
- **CEFR-Wortlisten** kommerzieller Lernseiten sind meist nicht offen lizenziert — nur als redaktionelle Orientierung, nicht als Datenquelle verwenden.
- Die didaktische **Niveau-Zuordnung** einzelner Wörter/Themen (welches Wort ist „A1"?) ist teilweise Ermessenssache; Kombination aus Frequenz (Lexique) + dokumentierter Grammatikprogression liefert eine solide, aber nicht kanonische Einteilung.