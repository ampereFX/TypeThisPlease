# TypeThisPlease

TypeThisPlease is a native macOS speech-to-text utility built around a menubar workflow, global hotkeys, checkpoint-based drafting, and a process-backed local Whisper runtime.

## What it does

- Runs as a menubar-first app with a draft window, settings window, and floating recording HUD.
- Starts and stops recording from a configurable global hotkey.
- Supports checkpoint hotkeys that commit the spoken portion into draft placeholders while recording continues.
- Copies the final transcript to the clipboard and can optionally auto-paste it into the frontmost app.
- Keeps the transcription backend abstracted behind a `TranscriptionEngine` protocol so Whisper v1 is not a dead end.

## Current architecture

- `SwiftUI` drives the primary UI.
- `AppKit` is used for global hotkeys, custom windows, file pickers, and menu-bar app behavior.
- `AVAudioEngine` captures audio segments.
- `CoreAudio` enumerates and observes available input devices.
- `WhisperCPPTranscriptionEngine` runs a local Whisper-compatible CLI as an external process.
- `ModelManager` manages runtime/model file locations and direct downloads.

## Repo layout

- `Sources/TypeThisPlease/Domain`: app settings, session state, device policy, engine interfaces.
- `Sources/TypeThisPlease/Services`: orchestration, recording, hotkeys, permissions, output, model management.
- `Sources/TypeThisPlease/UI`: SwiftUI views and AppKit-backed controls.
- `Tests/TypeThisPleaseTests`: domain and policy tests.
- `docs/ARCHITECTURE.md`: implementation-oriented documentation for future agents and contributors.

## Running

1. Install or point the app to a local Whisper-compatible executable and model file.
2. Open settings from the menubar.
3. Configure global hotkeys and verify microphone/accessibility permissions.
4. Start recording from the menubar or the configured hotkey.
5. Trigger checkpoints to progressively build the draft.

## Notes

- The bundled runtime download flow expects direct file URLs for the runtime binary and model file.
- Auto-paste requires Accessibility permission and falls back to clipboard-only delivery when unavailable.
- The current draft model is append-oriented by design: transcript placeholders and manual text blocks are ordered by checkpoint boundaries.
