# TypeThisPlease

TypeThisPlease is a native macOS speech-to-text utility built around a menubar workflow, global hotkeys, checkpoint-based drafting, and a process-backed local Whisper runtime.

## What it does

- Runs as a menubar-first app with a settings window and a single floating recording/review panel.
- Shows a first-launch onboarding dialog for permissions and setup orientation.
- Starts and stops recording from a configurable global hotkey.
- Supports checkpoint hotkeys that commit the spoken portion into inline transcribing markers while recording continues.
- Keeps a single editable rich-text-style draft surface instead of separate transcript cards.
- Copies the final transcript to the clipboard and can optionally auto-paste it into the frontmost app.
- Persists the floating panel's size and position across launches.
- Keeps the transcription backend abstracted behind a `TranscriptionEngine` protocol so Whisper v1 is not a dead end.

## Current architecture

- `SwiftUI` drives the main composition.
- `AppKit` is used for global hotkeys, custom windows, file pickers, the floating panel, and the text editor bridge.
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
3. On first launch, use the onboarding dialog to grant microphone access and optionally Accessibility for auto-paste.
4. Configure the Whisper executable and model in Settings.
5. Configure global hotkeys and verify the setup state shows both runtime and model as ready.
6. Start recording from the menubar or the configured hotkey.
7. Trigger checkpoints to progressively build the inline draft.
8. Depending on the selected finalize mode, stop once to deliver immediately or stop once to enter review and a second time to deliver.

## Notes

- The bundled runtime download flow expects direct file URLs for the runtime binary and model file.
- `Start Recording` is intentionally disabled until both the runtime and the model are available.
- Auto-paste requires Accessibility permission and falls back to clipboard-only delivery when unavailable.
- The editor is segment-aware: transcript text, manual edits, in-flight checkpoint transcriptions, and the active recording marker all share the same inline visual language with different tints.
