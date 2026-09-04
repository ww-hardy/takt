# TAKT

**Wertwandler Zeit-Tracking** — automatische Tätigkeits- und Kundenerkennung für Beratung, Coaching und Projektleitung.

TAKT erfasst Bildschirmaktivitäten lokal, fasst sie zu Timeline-Karten zusammen und nutzt einen konfigurierbaren LLM-Dienst (OpenAI-kompatibel, lokal via Ollama/LM Studio oder Cloud), um Arbeiten automatisch Kunden, Projekten und Kategorien zuzuordnen.

## Funktionen

- **Automatische Zeiterfassung** — Screenshots im konfigurierbaren Intervall, lokal gespeichert, per LLM zu Aktivitätskarten zusammengefasst
- **KI-Kundenerkennung** — Ordnet Aktivitäten anhand von Kundenbeschreibungen automatisch zu; unsichere Zuordnungen werden dem Nutzer zur Bestätigung vorgelegt
- **Multi-Client** — Mehrere Kunden mit Projekten, abrechenbar/nicht-abrechenbar, CSV-/Markdown-Export
- **Tagesberichte** — Zusammenfassung des Arbeitstags nach 5 Stunden analysierter Timeline-Daten
- **KI-Chat** — Direkter Dialog mit dem konfigurierten LLM über erfasste Aktivitäten
- **Lokale Kontrolle** — Alle Daten bleiben auf dem Mac; keine Telemetrie ohne Opt-in
- **Onboarding** — Geführter 5-Schritt-Setup: Welcome → LLM-Anbieter (Cloud oder lokal) → Erster Kunde → Bildschirm-Berechtigung → Start

## Systemanforderungen

- macOS 13.0+
- Apple Silicon (M1+) oder Intel
- Bildschirm-Aufnahmeberechtigung (TCC Screen Recording)
- LLM-Dienst: OpenAI-kompatibler API-Endpoint oder lokale Installation (Ollama / LM Studio)

## Installation

1. [Neueste DMG herunterladen](https://github.com/ww-hardy/takt/releases)
2. DMG öffnen, TAKT.app in `Programme` ziehen
3. Beim ersten Start: Bildschirm-Aufnahmeberechtigung erteilen und LLM-Anbieter konfigurieren

Updates erfolgen automatisch über Sparkle (Applenotarisiert, Ed25519-signiert).

## LLM-Anbieter

TAKT unterstützt im Onboarding:

| Anbieter | Beschreibung |
|----------|-------------|
| **OpenAI-kompatibel** | Jeder Dienst mit `/v1/chat/completions`-Endpoint (Nous Portal, OpenRouter, OpenAI, Anthropic etc.) |
| **Lokal** | Ollama oder LM Studio auf localhost; vollständig offline |

Konfiguriert wird: Base URL, Modell-ID und API-Key (nur bei Cloud). Der Chat nutzt denselben Provider wie die Erkennung.

## Architektur

TAKT ist ein Fork von [Dayflow](https://github.com/JerryZLiu/Dayflow) mit eigener Wertwandler-Designsprache, deutscher UI und erweiterter Kunden-/Projektlogik.

| Schicht | Technologie |
|---------|------------|
| UI | SwiftUI, TaktTheme-Designsystem, TaktFont-Typografie |
| Recording | ScreenCaptureKit, DispatchSourceTimer, `~/Library/Application Support/wertwandler-takt/` |
| Storage | SQLite (WAL-Modus), `chunks.sqlite` |
| LLM | `LLMProviderRoutingStore` → OpenAI-kompatibel / lokal; `CardTaggingService` für Kunden-Zuordnung |
| Updates | Sparkle 2 (Ed25519-signiert, GitHub-Appcast, SilentUserDriver) |
| Signing | Apple Developer ID, Hardened Runtime, Notarized |

## Build

```bash
# Debug
xcodebuild -project Dayflow/Dayflow.xcodeproj -scheme TAKT -configuration Debug build

# Release
xcodebuild -project Dayflow/Dayflow.xcodeproj -scheme TAKT -configuration Release build

# DMG (signiert + notarisiert)
codesign --force --deep --options runtime --sign "Developer ID Application: ..." TAKT.app
hdiutil create -volname TAKT -srcfolder staging -format UDZO TAKT.dmg
xcrun notarytool submit TAKT.dmg --keychain-profile AC_PASSWORD --wait
xcrun stapler staple TAKT.dmg
```

## Update-Release-Workflow

1. Release-Build: `xcodebuild -scheme TAKT -configuration Release build`
2. Developer-ID signieren + DMG erstellen + notarisieren
3. DMG mit Sparkle signieren: `sign_update --ed-key-file <key> TAKT-x.x.x.dmg`
4. `appcast.xml` aktualisieren (Signatur, Größe, URL eintragen)
5. Commit + Push
6. GitHub Release mit DMG als Asset erstellen

## Datenpfade

| Pfad | Inhalt |
|------|--------|
| `~/Library/Application Support/wertwandler-takt/` | Timeline-Daten, Screenshots, Recordings, Backups |
| `~/Library/Preferences/ch.wertwandler.takt.plist` | UserDefaults |
| `~/Library/Caches/ch.wertwandler.takt/` | Cache |
| Keychain (`ch.wertwandler.takt.apikeys.*`) | LLM-API-Keys |

## Lizenz

TAKT steht unter der MIT-Lizenz. Siehe [LICENSE](LICENSE) für den vollständigen Lizenztext.

Copyright (c) 2026 Wertwandler

## Kontakt

- **Website:** [wertwandler.ch](https://wertwandler.ch)
- **Support:** support@wertwandler.ch
- **GitHub:** [ww-hardy/takt](https://github.com/ww-hardy/takt)

---

Powered by Wertwandler
