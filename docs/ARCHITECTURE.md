# Architecture Guide

This document is the fast path for another agent or engineer to understand the codebase without reverse-engineering it from source.

## Product shape

TypeThisPlease is a menubar-first macOS app for local speech-to-text. A user starts recording from a global shortcut or the menubar, optionally drops one or more checkpoints while speaking, types manual corrections between committed speech segments, and then finalizes the session into a clipboard-ready transcript.

The implementation assumes:

- Native macOS app, not web or cross-platform.
- `SwiftUI` for view composition.
- `AppKit` for the missing system-level pieces.
- Local STT execution through a process-backed adapter.
- App Store constraints are not the v1 baseline, but the architecture keeps OS integration isolated so that later tightening is possible.

## High-level module map

### App shell

- `TypeThisPleaseApp.swift`
  - SwiftUI entrypoint.
  - Owns the root `AppModel`.
  - Creates the `WindowCoordinator`.
  - Hosts the `MenuBarExtra`.
- `App/MenuBarAppDelegate.swift`
  - Switches the app into accessory mode so the Dock icon stays hidden.

### Domain

- `Domain/AppSettings.swift`
  - Persistent user settings.
  - Hotkeys, output mode, device preferences, Whisper runtime/model config.
- `Domain/HotKey.swift`
  - Serializable hotkey representation.
  - Carbon and AppKit modifier bridging.
- `Domain/AudioDevice.swift`
  - Runtime audio device model.
  - Device priority resolution logic.
- `Domain/RecordingSession.swift`
  - Draft/session state machine model.
  - Placeholder insertion and transcript/manual block ordering.
- `Domain/TranscriptionEngine.swift`
  - Stable protocol boundary for STT backends and future post-processors.

### Services

- `Services/AppModel.swift`
  - Main orchestration hub.
  - Owns current settings, session state, device list, engine status, permissions exposure, and top-level user actions.
  - This is the place to extend first if you add new session behaviors.
- `Services/HotKeyService.swift`
  - Registers global hotkeys through Carbon.
- `Services/AudioCaptureService.swift`
  - Captures microphone audio using `AVAudioEngine`.
  - Rotates segment files at checkpoint boundaries.
- `Services/AudioDeviceMonitor.swift`
  - Uses CoreAudio to enumerate devices and observe changes.
- `Services/ModelManager.swift`
  - Resolves runtime/model locations in Application Support.
  - Downloads runtime/model artifacts from direct URLs.
- `Services/WhisperCPPTranscriptionEngine.swift`
  - Concrete STT adapter for a Whisper-compatible CLI.
  - Designed so new engines can sit beside it, not inside it.
- `Services/OutputService.swift`
  - Clipboard delivery and optional auto-paste.
- `Services/PermissionsService.swift`
  - Microphone and Accessibility status/request wrappers.
- `Services/WindowCoordinator.swift`
  - AppKit window lifecycle for Settings, onboarding, and the floating recording/draft panel.

### UI

- `UI/MenuBarMenuView.swift`
  - Menubar window content with start/stop readiness gating and navigation actions.
- `UI/SettingsView.swift`
  - Hotkeys, Whisper config, device priorities, permissions, and output settings.
- `UI/DraftWindowView.swift`
  - Unified floating surface for recording state and ordered draft presentation:
    - transcript blocks are read-only status-backed blocks
    - manual blocks remain editable
- `UI/OnboardingView.swift`
  - First-launch setup panel for permissions and setup orientation.
- `UI/HotKeyRecorder.swift`
  - AppKit-backed shortcut recorder control for settings.

## Recording and checkpoint flow

### Start

1. `AppModel.startSession()` checks microphone permission.
2. Start is only enabled once the runtime and model exist.
3. Whisper configuration is pushed into the engine and `prepare()` verifies runtime/model availability.
4. The active input device is resolved through `AudioDevicePolicy`.
5. `AudioCaptureService.start(device:)` configures `AVAudioEngine`, optionally binds the selected hardware input, installs a tap, and begins writing the first segment file.
6. The unified floating recording/draft panel is shown.

### Checkpoint

1. `AppModel.checkpoint()` asks `AudioCaptureService` to rotate to a new segment file.
2. The completed segment is enqueued for transcription.
3. `RecordingSession.insertCheckpointPlaceholder(for:)` appends:
   - one transcript placeholder block
   - one manual text block
4. When transcription returns, the placeholder is filled in place, preserving the manual insertion point that the user may already have started editing.

### Finalize

1. `AppModel.finalizeSession()` stops capture and appends the final transcript placeholder.
2. All pending segment transcriptions run to completion.
3. `RecordingSession.assembledDraft` concatenates the ordered blocks.
4. Optional post-processing runs here if a `PostProcessor` is wired in later.
5. `OutputService` copies or copies+pastes the final text.

## Why placeholders matter

Checkpoint transcriptions can finish out of order. The implementation avoids output reordering by inserting placeholder blocks at checkpoint time instead of append-on-completion time. That is the key structural choice that makes mixed spoken/manual drafting predictable.

## Device handling

- Device discovery and updates come from `AudioDeviceMonitor`.
- The settings store keeps a priority list of preferred device UIDs.
- `AudioDevicePolicy.resolve(...)` chooses the first preferred device that is currently available.
- If none of the preferred devices are present, the default input device wins.
- If the active device disappears during recording, `AppModel` finalizes the session instead of silently switching microphones mid-stream.

## First-launch behavior

- `TypeThisPleaseApp` boots the app model immediately at app launch, not only when the menubar item is opened.
- If onboarding has not been completed yet, `WindowCoordinator` presents the onboarding panel.
- Onboarding focuses on microphone permission first and positions Accessibility as optional.
- The user can dismiss onboarding, but recording still remains disabled until the runtime and model are present.

## Extension points

### Add another STT engine

1. Create a new type conforming to `TranscriptionEngine`.
2. Add settings for its runtime/model details.
3. Swap engine selection in `AppModel`.
4. Keep the UI and session model untouched if the new engine still works on audio segments.

### Add LLM cleanup or prompt-based post-processing

1. Implement `PostProcessor`.
2. Inject it into `AppModel`.
3. Leave capture, checkpointing, and draft ordering unchanged.

### Add history or exports

Do not overload `RecordingSession` for persistence. Introduce a separate stored transcript model and let `AppModel.completeSessionIfPossible()` emit finalized records into that new layer.

## Operational caveats

- The runtime downloader currently assumes direct file URLs, not archives.
- `AudioCaptureService` writes `.wav` files per segment and keeps the current implementation intentionally simple.
- Auto-paste uses simulated `Cmd+V` and therefore depends on Accessibility permission.
- The codebase favors a clean separable architecture over full production hardening in every subsystem. The next round of work should focus on:
  - stronger process argument handling
  - archive extraction for runtime installs
  - richer error surfacing in the draft UI
  - more exhaustive session/orchestration tests
