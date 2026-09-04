# TAKT

**Wertwandler Zeit-Tracking** — automatische Tätigkeits- und Kundenerkennung für Beratung, Coaching und Projektleitung.

TAKT erfasst Bildschirmaktivitäten lokal, fasst sie zu Timeline-Karten zusammen und nutzt einen konfigurierbaren LLM-Dienst (OpenAI-kompatibel, lokal via Ollama/LM Studio/llama.cpp oder Cloud), um Arbeiten automatisch Kunden, Projekten und Kategorien zuzuordnen.

## Funktionen

- **Automatische Zeiterfassung** — Screenshots im konfigurierbaren Intervall, lokal gespeichert, per LLM zu Aktivitätskarten zusammengefasst
- **KI-Kundenerkennung** — Ordnet Aktivitäten anhand von Kundenbeschreibungen automatisch zu; unsichere Zuordnungen werden dem Nutzer zur Bestätigung vorgelegt
- **Multi-Client** — Mehrere Kunden mit Projekten, abrechenbar/nicht-abrechenbar, CSV-/Markdown-Export
- **Tagesberichte** — Zusammenfassung des Arbeitstags nach 5 Stunden analysierter Timeline-Daten
- **KI-Chat** — Direkter Dialog mit dem konfigurierten LLM über erfasste Aktivitäten
- **Lokale Kontrolle** — Bildschirmdaten werden lokal gespeichert; bei Cloud-LLMs werden die für die Analyse nötigen Daten an den konfigurierten Dienst gesendet
- **Onboarding** — Geführter 5-Schritt-Setup: Welcome → LLM-Anbieter (Cloud oder lokal) → Erster Kunde → Bildschirm-Berechtigung → Start

## Systemanforderungen

- macOS 13.0+
- Apple Silicon (M1+) oder Intel
- Bildschirm-Aufnahmeberechtigung (TCC Screen Recording)
- LLM-Dienst: OpenAI-kompatibler API-Endpoint oder lokale Installation (Ollama / LM Studio / llama.cpp)

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
| **Lokal** | Ollama, LM Studio oder llama.cpp auf localhost; Screenshots und Prompts gehen an den lokalen Server |

Konfiguriert wird: Base URL, Modell-ID und API-Key (nur bei Cloud). Bei llama.cpp nutzt TAKT standardmäßig `http://localhost:8080` und den API-Modellnamen `qwen3-vl-4b`. Der Chat nutzt denselben Provider wie die Erkennung.

### llama.cpp lokal starten

```bash
brew install llama.cpp
scripts/run_llama_cpp_vlm.sh --download
scripts/run_llama_cpp_vlm.sh
```

Der Download umfasst das Qwen3-VL-4B-Q4-K_M-Modell und den passenden `mmproj`-Vision-Projektor. Der Server bindet standardmäßig nur an `127.0.0.1:8080`; TAKT verwendet dafür die OpenAI-kompatible Route `/v1/chat/completions`.

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
xcodebuild -project TAKT/TAKT.xcodeproj -scheme TAKT -configuration Debug build

# Release
xcodebuild -project TAKT/TAKT.xcodeproj -scheme TAKT -configuration Release build

# DMG (signiert + notarisiert)
codesign --force --deep --options runtime --sign "Developer ID Application: ..." TAKT.app
hdiutil create -volname TAKT -srcfolder staging -format UDZO TAKT.dmg
xcrun notarytool submit TAKT.dmg --keychain-profile AC_PASSWORD --wait
xcrun stapler staple TAKT.dmg
```

## Update-Release-Workflow

Der reproduzierbare Release-Helfer baut, signiert und paketiert die App:

```bash
brew install create-dmg
NOTARY_PROFILE=AC_PASSWORD \
  SIGN_UPDATE=/path/to/Sparkle/bin/sign_update \
  ./scripts/release.sh --patch
```

Der Sparkle-Private-Key bleibt außerhalb des Repositories. Für lokale Builds kann die
Signatur alternativ über den Sparkle-Keychain-Eintrag erfolgen. Der Helfer aktualisiert
`appcast.xml` im Repository-Root, weil genau diese Datei über
`https://raw.githubusercontent.com/ww-hardy/takt/main/appcast.xml` ausgeliefert wird.

Für llama.cpp werden keine Modell-Downloads automatisch ausgeführt. Erst
`scripts/run_llama_cpp_vlm.sh --download` lädt die Qwen3-VL-Artefakte; der normale
Start verwendet das ressourcenschonende Profil mit Kontext 8192, einem Slot, Batch 512,
UBatch 256 und mindestens 1024 Bildtoken.

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
