// System-Prompts für den Proxy.
//
// Der Prompt wird bewusst **hier** gebaut und nicht von der App geschickt:
// Sonst wäre der Proxy für jeden, der die Adresse aus dem App-Binary liest,
// ein kostenloser Allzweck-Claude. So kann er nur das, wofür er gedacht ist.
//
// Inhaltlich identisch zu `AIPersona.systemPrompt` in
// `FrenchApp/Community/AIPartner.swift` — ändert sich einer, muss der andere
// mitziehen.

export const LANGUAGES = { fr: 'Französisch', de: 'Deutsch' }
export const LEVELS = ['A1', 'A2', 'B1', 'B2']

/// Nur diese Namen sind erlaubt — der Name landet im Prompt, also darf er
/// nicht frei aus der App kommen.
export const NAMES = { fr: 'Manon', de: 'Jonas' }

const LEVEL_HINTS = {
  A1: 'Kurze Hauptsätze im Präsens, Alltagswortschatz, keine Nebensätze.',
  A2: 'Einfache Sätze, Vergangenheit erlaubt, vertraute Alltagsthemen.',
  B1: 'Auch Nebensätze und zusammenhängende Erzählungen.',
  B2: 'Natürliches Tempo, auch abstrakte Themen und idiomatische Wendungen.',
}

/// A1/A2 kommen mit dem günstigen Modell aus; ab B1 wird beiläufiges
/// Korrigieren anspruchsvoll, und ein falsch „korrigierter" Satz bringt der
/// lernenden Person aktiv etwas Falsches bei.
export const ENTRY_MODEL = 'claude-haiku-4-5'
export const ADVANCED_MODEL = 'claude-opus-4-8'

export function modelFor(level) {
  return level === 'B1' || level === 'B2' ? ADVANCED_MODEL : ENTRY_MODEL
}

/// `output_config.effort` gibt es erst ab der Opus-4.x-/Sonnet-5-Reihe.
/// Haiku 4.5 beantwortet den Parameter mit 400, also darf er dort fehlen.
export function supportsEffort(model) {
  return model !== ENTRY_MODEL
}

export function buildChatPrompt({ language, level }) {
  const target = LANGUAGES[language]
  const native = LANGUAGES[language === 'fr' ? 'de' : 'fr']
  const name = NAMES[language]

  return `Du bist ${name} und chattest mit einer Person, die ${target} auf Niveau ${level} lernt. ${target} ist deine Muttersprache.

- Antworte AUSSCHLIESSLICH auf ${target}. Nie auf ${native}, auch nicht in Klammern oder als Übersetzung.
- Passe Wortschatz und Satzbau an Niveau ${level} an. ${LEVEL_HINTS[level]}
- Halte das Gespräch am Laufen: ein bis drei Sätze antworten, dann eine Rückfrage stellen.
- Macht die Person einen Fehler, korrigiere ihn beiläufig, indem du den Satz in deiner Antwort richtig wiederholst. Kein Grammatik-Vortrag, keine Bewertung, kein Lob für Korrektheit.
- Bleib in der Rolle. Keine Meta-Kommentare, kein Markdown, keine Erklärung deiner Überlegungen. Gib nur die Chat-Antwort aus.`
}

export function buildTranslatePrompt({ sourceLanguage, targetLanguage }) {
  return `Du bist ein Übersetzer. Übersetze den Text der nutzenden Person von ${LANGUAGES[sourceLanguage]} nach ${LANGUAGES[targetLanguage]}.

Gib ausschließlich die Übersetzung aus — keine Anführungszeichen, keine Erklärung, keine Alternativen, kein Markdown. Behalte den Ton des Originals bei; Umgangssprache bleibt Umgangssprache.`
}

// MARK: - Eingabeprüfung

export const LIMITS = {
  maxMessages: 20,
  maxMessageChars: 2000,
  maxTranslateChars: 2000,
}

/// Wirft bei allem, was nicht exakt dem erwarteten Format entspricht. Die App
/// ist der einzige legitime Aufrufer — großzügiges Parsen bringt hier nichts
/// außer Angriffsfläche.
export function validateRequest(payload) {
  if (!payload || typeof payload !== 'object') throw new Error('Body fehlt')

  if (payload.mode === 'chat') {
    if (!LANGUAGES[payload.language]) throw new Error('Unbekannte Sprache')
    if (!LEVELS.includes(payload.level)) throw new Error('Unbekanntes Niveau')
    if (!Array.isArray(payload.messages) || payload.messages.length === 0) {
      throw new Error('Keine Nachrichten')
    }
    if (payload.messages.length > LIMITS.maxMessages) throw new Error('Zu viele Nachrichten')
    for (const message of payload.messages) {
      if (message.role !== 'user' && message.role !== 'assistant') {
        throw new Error('Unbekannte Rolle')
      }
      if (typeof message.content !== 'string' || message.content.length === 0) {
        throw new Error('Leere Nachricht')
      }
      if (message.content.length > LIMITS.maxMessageChars) throw new Error('Nachricht zu lang')
    }
    if (payload.messages[0].role !== 'user') throw new Error('Verlauf muss mit user beginnen')
    return {
      mode: 'chat',
      model: modelFor(payload.level),
      system: buildChatPrompt(payload),
      messages: payload.messages.map((m) => ({ role: m.role, content: m.content })),
    }
  }

  if (payload.mode === 'translate') {
    if (!LANGUAGES[payload.sourceLanguage]) throw new Error('Unbekannte Quellsprache')
    if (!LANGUAGES[payload.targetLanguage]) throw new Error('Unbekannte Zielsprache')
    if (typeof payload.text !== 'string' || payload.text.length === 0) {
      throw new Error('Kein Text')
    }
    if (payload.text.length > LIMITS.maxTranslateChars) throw new Error('Text zu lang')
    return {
      mode: 'translate',
      // Übersetzen ist die einfachere Aufgabe — immer das günstige Modell.
      model: ENTRY_MODEL,
      system: buildTranslatePrompt(payload),
      messages: [{ role: 'user', content: payload.text }],
    }
  }

  throw new Error('Unbekannter Modus')
}
