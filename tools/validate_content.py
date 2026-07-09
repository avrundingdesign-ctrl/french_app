#!/usr/bin/env python3
"""Validiert die gebündelten Inhaltsdaten der Français-App.

Prüft Querverweise (Vokabeln, Verben, Grammatikregeln), Übungs-Specs und
didaktische Mindestanforderungen. Läuft ohne Dependencies:

    python3 tools/validate_content.py

Exit-Code 0 = alles OK, 1 = Fehler gefunden. Die gleichen Prüfungen laufen
zusätzlich als Unit-Tests in der App (ContentTests) — dieses Skript ist der
schnelle Weg ohne Xcode und der Haken für CI/pre-commit.
"""

import json
import sys
from pathlib import Path

CONTENT_DIR = Path(__file__).resolve().parent.parent / "FrenchApp" / "Resources" / "Content"

VALID_TENSES = {
    "present", "imparfait", "passeCompose", "plusQueParfait",
    "futurProche", "futurSimple", "futurAnterieur",
    "conditionnel", "conditionnelPasse", "subjonctifPresent",
}
VALID_LEVELS = {"A1", "A2", "B1", "B2", "C1"}
# Deutsch-Kurs (Gegenrichtung): eigene Tempora des GermanConjugator.
VALID_TENSES_DE = {"praesens", "perfekt", "praeteritum", "futur", "imperativ"}
VALID_GERMAN_VERB_TYPES = {"weak", "strong", "mixed", "modal", "irregular"}
INSEPARABLE_PREFIXES = ("be", "ge", "er", "ver", "zer", "ent", "emp", "miss")
EXAM_SECTION_KINDS = ["listening", "reading", "language", "writing"]
# Prüfungsfragen brauchen keinen Lektionskontext — Vokabel-Typen sind tabu.
EXAM_QUESTION_TYPES = {"mcSentence", "cloze", "translate", "wordOrder", "conjugation", "errorCorrection"}


def load(name):
    with open(CONTENT_DIR / f"{name}.json", encoding="utf-8") as f:
        return json.load(f)


def check_spec(ex, where, verbs, errors):
    """Typ-spezifische Prüfung eines Übungs-Specs (Lektion und Prüfung)."""
    t = ex["type"]
    if t == "conjugation":
        if ex["verb"] not in verbs:
            errors.append(f"{where}: Verb {ex['verb']} fehlt")
        if ex.get("tense", "present") not in VALID_TENSES:
            errors.append(f"{where}: unbekanntes Tempus {ex.get('tense')}")
        if not 0 <= ex.get("person", -1) <= 5:
            errors.append(f"{where}: person fehlt/ungültig")
    elif t == "cloze":
        if "___" not in ex["text"]:
            errors.append(f"{where}: Cloze ohne ___")
        if "choices" in ex:
            if ex["answer"] not in ex["choices"]:
                errors.append(f"{where}: answer nicht in choices")
            if len(set(ex["choices"])) < 3:
                errors.append(f"{where}: weniger als 3 eindeutige choices")
    elif t in ("mcSentence", "errorCorrection"):
        distractors = ex.get("distractors") or []
        if len(set(distractors)) < 2:
            errors.append(f"{where}: weniger als 2 Distraktoren")
        if ex["answer"] in distractors:
            errors.append(f"{where}: answer ist auch Distraktor")
    elif t == "translate":
        if not ex.get("de") or not ex.get("fr"):
            errors.append(f"{where}: translate braucht de und fr")
    elif t == "wordOrder":
        if len(ex["fr"].split(" ")) < 3:
            errors.append(f"{where}: wordOrder unter 3 Wörtern")
    elif t in ("vocabIntro", "vocabProd"):
        if not ex.get("vocab"):
            errors.append(f"{where}: {t} ohne vocab-Liste")


def check_spec_de(ex, where, verbs_de, errors):
    """Spec-Prüfung für den Deutsch-Kurs: de ist Zielsprache, Tempora
    und Personenregeln folgen dem GermanConjugator."""
    t = ex["type"]
    if t == "conjugation":
        verb = verbs_de.get(ex["verb"])
        if verb is None:
            errors.append(f"{where}: Verb {ex['verb']} fehlt in verbs_de")
            return
        tense = ex.get("tense", "praesens")
        if tense not in VALID_TENSES_DE:
            errors.append(f"{where}: unbekanntes Tempus {tense}")
        person = ex.get("person", -1)
        if tense == "imperativ":
            if person not in (1, 4, 5):
                errors.append(f"{where}: Imperativ nur für du/ihr/Sie (1/4/5)")
            if verb["type"] in ("modal",) or (verb.get("present") and not verb.get("imperative")):
                errors.append(f"{where}: {ex['verb']} hat keinen Imperativ")
        elif not 0 <= person <= 5:
            errors.append(f"{where}: person fehlt/ungültig")
        if tense == "praeteritum" and not verb.get("praeteritum"):
            errors.append(f"{where}: {ex['verb']} hat keine Präteritum-Tabelle (A1: nur sein/haben/werden/Modalverben)")
        if tense == "perfekt" and verb["type"] != "weak" and not verb.get("participle"):
            errors.append(f"{where}: {ex['verb']} hat kein Partizip für das Perfekt")
    elif t == "cloze":
        if "___" not in ex["text"]:
            errors.append(f"{where}: Cloze ohne ___")
        if "choices" in ex:
            if ex["answer"] not in ex["choices"]:
                errors.append(f"{where}: answer nicht in choices")
    elif t in ("mcSentence", "errorCorrection"):
        distractors = ex.get("distractors") or []
        if len(set(distractors)) < 2:
            errors.append(f"{where}: weniger als 2 Distraktoren")
        if ex["answer"] in distractors:
            errors.append(f"{where}: answer ist auch Distraktor")
    elif t == "translate":
        if not ex.get("de") or not ex.get("fr"):
            errors.append(f"{where}: translate braucht de und fr")
    elif t == "wordOrder":
        # Zielsatz ist hier das de-Feld.
        if len(ex["de"].split(" ")) < 3:
            errors.append(f"{where}: wordOrder unter 3 Wörtern")
    elif t in ("vocabIntro", "vocabProd"):
        if not ex.get("vocab"):
            errors.append(f"{where}: {t} ohne vocab-Liste")


def validate_german_course(vocab, errors, warnings):
    """Prüft das _de-Dateiset der Gegenrichtung (Frankophone lernen Deutsch)."""
    verbs_de = {v["infinitive"]: v for v in load("verbs_de")["verbs"]}
    for name, verb in verbs_de.items():
        if verb["type"] not in VALID_GERMAN_VERB_TYPES:
            errors.append(f"verbs_de {name}: unbekannter Typ {verb['type']}")
        if verb["type"] in ("strong", "mixed") and not verb.get("participle"):
            errors.append(f"verbs_de {name}: starkes/gemischtes Verb ohne Partizip")
        if verb["type"] == "irregular" and not verb.get("present"):
            errors.append(f"verbs_de {name}: unregelmäßig ohne Präsenstabelle")
        for key in ("present", "praeteritum"):
            if verb.get(key) and len(verb[key]) != 6:
                errors.append(f"verbs_de {name}: {key} braucht 6 Formen")
        if verb.get("imperative") and len(verb["imperative"]) != 3:
            errors.append(f"verbs_de {name}: imperative braucht 3 Formen (du/ihr/Sie)")
        prefix = verb.get("separablePrefix")
        bare = name[5:] if name.startswith("sich ") else name  # Reflexive: "sich anziehen" → "anziehen"
        if prefix and not bare.startswith(prefix):
            errors.append(f"verbs_de {name}: separablePrefix ist kein Präfix des Infinitivs")

    rules_de = {r["id"]: r for r in load("grammar_de")["rules"]}
    for rule_id, rule in rules_de.items():
        if not rule_id.startswith("de_g_"):
            errors.append(f"Regel {rule_id}: de_g_-Präfix fehlt")
        if rule["level"] not in VALID_LEVELS:
            errors.append(f"Regel {rule_id}: ungültiges Niveau")
        for infinitive in rule.get("verbTables") or []:
            if infinitive not in verbs_de:
                errors.append(f"Regel {rule_id}: Verb {infinitive} fehlt in verbs_de")

    course = load("course_de")
    lesson_count = spec_count = 0
    new_vocab: list[str] = []
    lesson_ids: list[str] = []
    for unit in course["units"]:
        if unit["level"] not in VALID_LEVELS:
            errors.append(f"Einheit {unit['id']}: ungültiges Niveau")
        for lesson in unit["lessons"]:
            lesson_count += 1
            lesson_ids.append(lesson["id"])
            if not lesson["id"].startswith("de_"):
                errors.append(f"{lesson['id']}: de_-Präfix fehlt (Kollisionsgefahr mit FR-Kurs)")
            new_vocab += lesson["newVocab"]
            for grammar_id in lesson.get("grammar") or []:
                if grammar_id not in rules_de:
                    errors.append(f"{lesson['id']}: Regel {grammar_id} fehlt")
            for vocab_id in lesson["newVocab"]:
                if vocab_id not in vocab:
                    errors.append(f"{lesson['id']}: Vokabel {vocab_id} fehlt")
            if len(lesson["exercises"]) < 5:
                errors.append(f"{lesson['id']}: nur {len(lesson['exercises'])} Übungs-Specs")
            for i, ex in enumerate(lesson["exercises"]):
                spec_count += 1
                where = f"{lesson['id']} ex{i}"
                for vocab_id in ex.get("vocab") or []:
                    if vocab_id not in vocab:
                        errors.append(f"{where}: Vokabel {vocab_id} fehlt")
                check_spec_de(ex, where, verbs_de, errors)

    dupes = {l for l in lesson_ids if lesson_ids.count(l) > 1}
    if dupes:
        errors.append(f"Doppelte DE-Lektions-IDs: {sorted(dupes)}")
    # Duplikatprüfung pro Kurs — der DE-Kurs darf FR-Vokabeln erneut einführen.
    dupes = {v for v in new_vocab if new_vocab.count(v) > 1}
    if dupes:
        errors.append(f"DE-Kurs: Vokabeln mehrfach eingeführt: {sorted(dupes)}")

    exams = load("exams_de")["exams"]
    exam_question_count = 0
    for exam in exams:
        if exam["level"] not in VALID_LEVELS:
            errors.append(f"{exam['id']}: ungültiges Niveau")
        if exam.get("durationMinutes", 0) < 10:
            errors.append(f"{exam['id']}: durationMinutes fehlt/zu kurz")
        kinds = [s["kind"] for s in exam["sections"]]
        if kinds != EXAM_SECTION_KINDS:
            errors.append(f"{exam['id']}: Teile {kinds}, erwartet {EXAM_SECTION_KINDS}")
        for section in exam["sections"]:
            if not section.get("intro"):
                errors.append(f"{exam['id']} {section['kind']}: intro fehlt")
            question_count = 0
            for ti, task in enumerate(section["tasks"]):
                if section["kind"] == "listening" and not task.get("audioScript"):
                    errors.append(f"{exam['id']} listening t{ti}: audioScript fehlt")
                if section["kind"] == "reading" and not task.get("passage"):
                    errors.append(f"{exam['id']} reading t{ti}: passage fehlt")
                for qi, ex in enumerate(task["questions"]):
                    question_count += 1
                    exam_question_count += 1
                    where = f"{exam['id']} {section['kind']} t{ti} q{qi}"
                    if ex["type"] not in EXAM_QUESTION_TYPES:
                        errors.append(f"{where}: Typ {ex['type']} in Prüfungen nicht erlaubt")
                        continue
                    check_spec_de(ex, where, verbs_de, errors)
            if question_count < 4:
                errors.append(f"{exam['id']} {section['kind']}: nur {question_count} Fragen")

    pairs = load("listening_de")["minimalPairs"]
    if len(pairs) < 20:
        errors.append(f"listening_de: nur {len(pairs)} Minimal-Paare — mindestens 20")
    seen_pairs = set()
    for i, pair in enumerate(pairs):
        where = f"listening_de[{i}]"
        if not all(pair.get(k) for k in ("a", "b", "deA", "deB", "contrast")):
            errors.append(f"{where}: Feld fehlt/leer")
            continue
        if pair["a"] == pair["b"]:
            errors.append(f"{where}: a und b identisch")
        key = tuple(sorted((pair["a"], pair["b"])))
        if key in seen_pairs:
            errors.append(f"{where}: Paar {key} doppelt")
        seen_pairs.add(key)

    # Gespiegelte Wortschatz-Pakete des Deutsch-Kurses.
    packs_de = load("packs_de")["packs"]
    pack_ids = [p["id"] for p in packs_de]
    if len(pack_ids) != len(set(pack_ids)):
        errors.append("Doppelte DE-Paket-IDs")
    pack_vocab_de: list[str] = []
    for pack in packs_de:
        if not pack["id"].startswith("de_pack_"):
            errors.append(f"{pack['id']}: de_pack_-Präfix fehlt")
        if pack["level"] not in VALID_LEVELS:
            errors.append(f"{pack['id']}: ungültiges Niveau")
        if len(pack["vocab"]) < 15:
            errors.append(f"{pack['id']}: nur {len(pack['vocab'])} Wörter — mindestens 15")
        for vocab_id in pack["vocab"]:
            pack_vocab_de.append(vocab_id)
            if vocab_id not in vocab:
                errors.append(f"{pack['id']}: Vokabel {vocab_id} fehlt")
            if vocab_id in new_vocab:
                errors.append(f"{pack['id']}: {vocab_id} wird schon von einer DE-Lektion eingeführt")
    dupes = {v for v in pack_vocab_de if pack_vocab_de.count(v) > 1}
    if dupes:
        errors.append(f"Vokabeln in mehreren DE-Paketen: {sorted(dupes)}")

    # challenges_de ist in 5b bewusst leer, muss aber laden.
    load("challenges_de")

    print(
        f"DE-Kurs: {len(verbs_de)} Verben · {len(rules_de)} Regeln · "
        f"{lesson_count} Lektionen · {spec_count} Übungs-Specs · "
        f"{len(exams)} Prüfung(en) mit {exam_question_count} Fragen · {len(pairs)} Minimal-Paare · "
        f"{len(packs_de)} Pakete mit {len(pack_vocab_de)} Wörtern"
    )
    return set(new_vocab) | set(pack_vocab_de)


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []

    vocab = {v["id"] for v in load("vocabulary")["vocabulary"]}
    vocab_list = [v["id"] for v in load("vocabulary")["vocabulary"]]
    if len(vocab) != len(vocab_list):
        dupes = {v for v in vocab_list if vocab_list.count(v) > 1}
        errors.append(f"Doppelte Vokabel-IDs: {sorted(dupes)}")

    verbs = {v["infinitive"]: v for v in load("verbs")["verbs"]}
    for name, verb in verbs.items():
        if verb["group"] == 3 and "present" not in verb and not name.startswith(("offrir", "ouvrir")):
            # erLike-Verben (offrir/ouvrir) werden regelbasiert generiert.
            if name not in ("offrir", "ouvrir", "découvrir", "souffrir"):
                errors.append(f"Verb {name}: Gruppe 3 ohne Präsensformen")
        if "present" in verb and len(verb["present"]) != 6:
            errors.append(f"Verb {name}: braucht 6 Präsensformen")
        if "subjonctif" in verb and len(verb["subjonctif"]) != 6:
            errors.append(f"Verb {name}: braucht 6 Subjonctif-Formen")

    rules = {r["id"]: r for r in load("grammar")["rules"]}
    for rule_id, rule in rules.items():
        if rule["level"] not in VALID_LEVELS:
            errors.append(f"Regel {rule_id}: ungültiges Niveau {rule['level']}")
        for infinitive in rule.get("verbTables") or []:
            if infinitive not in verbs:
                errors.append(f"Regel {rule_id}: Verb {infinitive} fehlt")

    course = load("course")
    lesson_count = spec_count = 0
    all_new_vocab: list[str] = []
    lesson_ids: list[str] = []
    level_counts: dict[str, int] = {}

    for unit in course["units"]:
        if unit["level"] not in VALID_LEVELS:
            errors.append(f"Einheit {unit['id']}: ungültiges Niveau")
        for lesson in unit["lessons"]:
            lesson_count += 1
            lesson_ids.append(lesson["id"])
            level_counts[unit["level"]] = level_counts.get(unit["level"], 0) + 1
            all_new_vocab += lesson["newVocab"]

            for grammar_id in lesson.get("grammar") or []:
                if grammar_id not in rules:
                    errors.append(f"{lesson['id']}: Regel {grammar_id} fehlt")
            for vocab_id in lesson["newVocab"]:
                if vocab_id not in vocab:
                    errors.append(f"{lesson['id']}: Vokabel {vocab_id} fehlt")

            if len(lesson["exercises"]) < 5:
                errors.append(f"{lesson['id']}: nur {len(lesson['exercises'])} Übungs-Specs")

            for i, ex in enumerate(lesson["exercises"]):
                spec_count += 1
                where = f"{lesson['id']} ex{i}"
                for vocab_id in ex.get("vocab") or []:
                    if vocab_id not in vocab:
                        errors.append(f"{where}: Vokabel {vocab_id} fehlt")
                check_spec(ex, where, verbs, errors)

    # Niveau-Prüfungen (DELF/DALF-Stil)
    exams = load("exams")["exams"]
    exam_levels = [e["level"] for e in exams]
    exam_question_count = 0
    if len(exam_levels) != len(set(exam_levels)):
        errors.append("Mehrere Prüfungen für dasselbe Niveau")
    for exam in exams:
        if exam["level"] not in VALID_LEVELS:
            errors.append(f"{exam['id']}: ungültiges Niveau {exam['level']}")
        if exam.get("durationMinutes", 0) < 10:
            errors.append(f"{exam['id']}: durationMinutes fehlt/zu kurz")
        kinds = [s["kind"] for s in exam["sections"]]
        if kinds != EXAM_SECTION_KINDS:
            errors.append(f"{exam['id']}: Teile {kinds}, erwartet {EXAM_SECTION_KINDS}")
        for section in exam["sections"]:
            if not section.get("intro"):
                errors.append(f"{exam['id']} {section['kind']}: intro fehlt")
            question_count = 0
            for ti, task in enumerate(section["tasks"]):
                if section["kind"] == "listening" and not task.get("audioScript"):
                    errors.append(f"{exam['id']} listening t{ti}: audioScript fehlt")
                if section["kind"] == "reading" and not task.get("passage"):
                    errors.append(f"{exam['id']} reading t{ti}: passage fehlt")
                for qi, ex in enumerate(task["questions"]):
                    question_count += 1
                    exam_question_count += 1
                    where = f"{exam['id']} {section['kind']} t{ti} q{qi}"
                    if ex["type"] not in EXAM_QUESTION_TYPES:
                        errors.append(f"{where}: Typ {ex['type']} in Prüfungen nicht erlaubt")
                        continue
                    check_spec(ex, where, verbs, errors)
            if question_count < 4:
                errors.append(f"{exam['id']} {section['kind']}: nur {question_count} Fragen")

    # Vertiefungskapitel (optionale Komplex-Übungen pro Niveau)
    challenges = load("challenges")["challenges"]
    challenge_levels = [c["level"] for c in challenges]
    challenge_question_count = 0
    if len(challenge_levels) != len(set(challenge_levels)):
        errors.append("Mehrere Vertiefungskapitel für dasselbe Niveau")
    for chapter in challenges:
        if chapter["level"] not in VALID_LEVELS:
            errors.append(f"{chapter['id']}: ungültiges Niveau")
        count = 0
        for ti, task in enumerate(chapter["tasks"]):
            for qi, ex in enumerate(task["questions"]):
                count += 1
                challenge_question_count += 1
                where = f"{chapter['id']} t{ti} q{qi}"
                if ex["type"] not in EXAM_QUESTION_TYPES:
                    errors.append(f"{where}: Typ {ex['type']} hier nicht erlaubt")
                    continue
                check_spec(ex, where, verbs, errors)
        if count < 12:
            errors.append(f"{chapter['id']}: nur {count} Aufgaben — mindestens 12")

    # Wortschatz-Pakete
    packs = load("packs")["packs"]
    pack_ids = [p["id"] for p in packs]
    if len(pack_ids) != len(set(pack_ids)):
        errors.append("Doppelte Paket-IDs")
    pack_vocab: list[str] = []
    for pack in packs:
        if pack["level"] not in VALID_LEVELS:
            errors.append(f"{pack['id']}: ungültiges Niveau")
        if len(pack["vocab"]) < 15:
            errors.append(f"{pack['id']}: nur {len(pack['vocab'])} Wörter — mindestens 15")
        for vocab_id in pack["vocab"]:
            pack_vocab.append(vocab_id)
            if vocab_id not in vocab:
                errors.append(f"{pack['id']}: Vokabel {vocab_id} fehlt")
            if vocab_id in all_new_vocab:
                errors.append(f"{pack['id']}: {vocab_id} wird schon von einer Lektion eingeführt")
    dupes = {v for v in pack_vocab if pack_vocab.count(v) > 1}
    if dupes:
        errors.append(f"Vokabeln in mehreren Paketen: {sorted(dupes)}")

    # Hörtraining: Minimal-Paare
    pairs = load("listening")["minimalPairs"]
    if len(pairs) < 20:
        errors.append(f"Nur {len(pairs)} Minimal-Paare — mindestens 20 erwartet")
    seen_pairs = set()
    for i, pair in enumerate(pairs):
        where = f"minimalPairs[{i}]"
        if not all(pair.get(k) for k in ("a", "b", "deA", "deB", "contrast")):
            errors.append(f"{where}: Feld fehlt/leer")
            continue
        if pair["a"] == pair["b"]:
            errors.append(f"{where}: a und b identisch")
        key = tuple(sorted((pair["a"], pair["b"])))
        if key in seen_pairs:
            errors.append(f"{where}: Paar {key} doppelt")
        seen_pairs.add(key)

    dupes = {l for l in lesson_ids if lesson_ids.count(l) > 1}
    if dupes:
        errors.append(f"Doppelte Lektions-IDs: {sorted(dupes)}")
    dupes = {v for v in all_new_vocab if all_new_vocab.count(v) > 1}
    if dupes:
        errors.append(f"Vokabeln mehrfach eingeführt: {sorted(dupes)}")

    # Gegenrichtung (Frankophone lernen Deutsch) — eigenes Dateiset.
    german_vocab = validate_german_course(vocab, errors, warnings)

    unused = vocab - set(all_new_vocab) - set(pack_vocab) - german_vocab
    if unused:
        warnings.append(f"{len(unused)} Vokabeln weder in Lektion noch Paket: {sorted(unused)[:10]} …")

    print(
        f"{len(vocab)} Vokabeln · {len(verbs)} Verben · {len(rules)} Regeln · "
        f"{lesson_count} Lektionen {level_counts} · {spec_count} Übungs-Specs · "
        f"{len(exams)} Prüfungen mit {exam_question_count} Fragen · {len(pairs)} Minimal-Paare · "
        f"{len(packs)} Pakete mit {len(pack_vocab)} Wörtern · "
        f"{len(challenges)} Vertiefungen mit {challenge_question_count} Aufgaben"
    )
    for w in warnings:
        print(f"⚠️  {w}")
    if errors:
        print(f"\n❌ {len(errors)} Fehler:")
        for e in errors:
            print(f"   {e}")
        return 1
    print("✅ Alle Prüfungen bestanden")
    return 0


if __name__ == "__main__":
    sys.exit(main())
