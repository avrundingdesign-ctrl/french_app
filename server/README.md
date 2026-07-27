# KI-Proxy (CloudFlare Worker)

Hält den Anthropic-API-Key **serverseitig** und lässt nur echte, unveränderte
Instanzen der App durch (Apple App Attest).

## Warum das nötig ist

Ein Key, der in der App steckt, ist nicht zu schützen:

- App-Store-Binaries lassen sich entschlüsseln und mit `strings` durchsuchen.
- Selbst ein perfekt verstecker Key steht beim Absenden im Klartext im
  `x-api-key`-Header — ein Debug-Proxy auf dem eigenen Gerät liest ihn mit.

Es gibt automatisierte Scanner, die genau danach suchen. Wenn der Key rausgeht,
läuft die Rechnung auf dich, bis du es merkst.

Hier liegt der Key auf dem Server, ist **ohne App-Update rotierbar**, und pro
Gerät gilt ein Tageslimit.

## Wer kommt durch

Jede Anfrage trägt eine **App-Attest-Assertion**: eine Signatur aus der Secure
Enclave über den Request-Body. Der private Schlüssel verlässt das Gerät nie.
Wer die Proxy-Adresse aus dem Binary liest, kann sie deshalb trotzdem nicht
benutzen.

Zusätzlich baut der Worker den System-Prompt **selbst** — die App schickt nur
Sprache, Niveau und die Nachrichten (`src/prompt.js`). Ohne das wäre der Proxy
ein kostenloser Allzweck-Claude für jeden, der die Adresse kennt.

> **Zur Premium-Prüfung:** Sie passiert in der App (`PremiumStore.isPremium`),
> nicht hier. Das trägt, weil App Attest *veränderte* Apps abweist — eine
> gepatchte App, die den Premium-Check überspringt, besteht die Attestation
> nicht. Wer es fester will, prüft zusätzlich die Kaufquittung über die App
> Store Server API; das ist hier bewusst nicht drin.

## Einrichten

```sh
cd server
npm install
```

**1. Apple-Daten eintragen** in `wrangler.toml`:

```toml
APPLE_TEAM_ID  = "..."   # Apple Developer Portal → Membership Details
APPLE_BUNDLE_ID = "design.avrunding.frenchapp"
```

**2. KV-Namespace anlegen** (speichert Geräte und Tageszähler):

```sh
npx wrangler kv namespace create DEVICES
```

Die ausgegebene `id` in `wrangler.toml` unter `[[kv_namespaces]]` eintragen.

**3. Anthropic-Key als Secret hinterlegen** — nie in `wrangler.toml`:

```sh
npx wrangler secret put ANTHROPIC_API_KEY
```

**4. Deployen:**

```sh
npx wrangler deploy
```

**5. Adresse in die App eintragen** — in `project.yml` unter dem Target
`FrenchApp`:

```yaml
AI_PROXY_BASE_URL: "https://frenchapp-ai-proxy.<subdomain>.workers.dev"
```

Danach `xcodegen generate`. Leer lassen heißt: kein Proxy-Pfad, der KI-Partner
läuft dann nur über Apple Intelligence oder einen eigenen Key.

**6. Entitlement prüfen.** In `FrenchApp/FrenchApp.entitlements` steht
`com.apple.developer.devicecheck.appattest-environment`. Für Builds aus Xcode
`development`, für App-Store-Builds `production`.

Passend dazu in `wrangler.toml`:

```toml
ALLOW_DEV_ATTEST = "true"    # nur während der Entwicklung
```

Im Produktivbetrieb **muss** das `"false"` sein — sonst kommen
Development-Attestations durch, die sich leichter fälschen lassen.

## Testen

```sh
npm test
```

Deckt den Assertion-Pfad ab, der bei **jeder** Anfrage läuft: DER-Umwandlung
der Signatur, Zählerprüfung gegen Wiedereinspielung, App-Bindung, fremde
Schlüssel. Dazu die Eingabeprüfung, die verhindert, dass der Proxy als
Allzweck-Claude missbraucht wird.

Nicht abgedeckt: die **Attestation** bei der Registrierung — dafür bräuchte es
ein echtes, von Apple signiertes Blob. Dieser Pfad ist auf einem echten Gerät
zu testen (Simulator kann kein App Attest).

Lokal laufen lassen:

```sh
npx wrangler dev
npx wrangler tail   # Logs im Betrieb
```

## Endpunkte

| Methode | Pfad | Zweck |
|---|---|---|
| `GET` | `/v1/attest/challenge` | Einmal-Challenge für die Registrierung |
| `POST` | `/v1/attest/register` | Attestation prüfen, Public Key merken |
| `POST` | `/v1/chat` | Assertion prüfen, Limit zählen, an Anthropic weiterreichen |

Fehler kommen als `{"error":{"code":"…","message":"…"}}`. Die App wertet
`code` aus: `attest_failed`/`unknown_key` lösen eine Neuanmeldung aus,
`rate_limited` und `refused` bekommen eigene Meldungen.

## Kosten

Der Worker läuft im CloudFlare-Gratis-Tier (100.000 Anfragen/Tag, KV
inklusive). Was Geld kostet, ist Anthropic:

- Ein Chat-Zug mit Verlauf: **ca. 0,25 Cent** (Haiku, A1/A2)
- Ab B1 nutzt der Worker das stärkere Modell — dort deutlich mehr

`DAILY_MESSAGE_LIMIT` (Standard 40) deckelt das pro Gerät und Tag.

> **Einschränkung:** Der Tageszähler liegt in KV und ist *letztlich* konsistent
> — bei vielen parallelen Anfragen kann das Limit leicht überschritten werden.
> Für ein hartes Limit wäre ein Durable Object nötig. Für den Kostenschutz
> reicht diese Genauigkeit.

## Wenn etwas nicht geht

| Symptom | Ursache |
|---|---|
| `attest_failed` bei jeder Anfrage | Team-ID oder Bundle-ID falsch; oder Entitlement-Umgebung passt nicht zu `ALLOW_DEV_ATTEST` |
| Im Simulator kommt nichts durch | App Attest gibt es dort nicht — eigenen Key hinterlegen oder Demo-Modus nutzen |
| `unknown_key` nach KV-Wechsel | Geräte sind weg; die App meldet sich beim nächsten Versuch selbst neu an |
| `Challenge ist abgelaufen` | Zwischen Challenge und Registrierung lagen über 5 Minuten |
