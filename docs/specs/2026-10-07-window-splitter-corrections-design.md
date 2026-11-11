# WindowSplitter Corrections

Status: approved by the user on 2026-10-07, including WASD defaults.

## Objective

Correct all functional findings from the project review without new dependencies,
while retaining macOS 13 support and existing persisted shortcuts.

## Design Principles

- Keep WASD defaults for halves and preserve UserDefaults keys and saved values.
- Use AppKit screen coordinates consistently; convert only at AX boundaries.
- Record exactly one valid combination, using the current enabled state.
- Escape cancels; losing the panel cancels; existing actions do not fire during recording.
- Require Command, Control or Option for newly recorded bindings; reject duplicates
  and reserve Option+Shift+Space for the panel. Show validation failures to the user.
- Maintain current bindings while permission is pending and report listener failures.
- Recover taps disabled by timeout/user input, and return borrowed incoming events.
- Use existing SwiftUI content inside an owned NSPanel and NSStatusItem so both
  click and Option+Shift+Space can toggle it using public macOS 13 APIs.

## Files And Architecture

- Models/WindowAction.swift: correct upper/lower AppKit rectangles; WASD defaults.
- Window/WindowController.swift: shared coordinate conversion, correct screen
  selection, checked AX operations and actionable failure reporting.
- Store/SettingsStore.swift: existing persistence, validation of proposed bindings.
- Engine/GlobalHotkeyManager.swift: latest bindings, permission/listener lifecycle,
  recording suspension, panel callback, normalized modifiers and tap recovery.
- UI/ShortcutRecorderButton.swift: fresh callbacks, active capture gate, one-shot
  completion, cancellation and first-responder cleanup.
- UI/ShortcutRowView.swift and ConfigPanelView.swift: record/toggle coordination,
  errors and a direct link to Accessibility settings.
- AppDelegate.swift and WindowSplitterApp.swift: native status item/panel ownership
  and launch/shutdown wiring; SwiftUI remains responsible for panel content.
- WindowSplitterTests/: regression tests for geometry, persistence, capture,
  lifecycle, shortcut matching and panel integration without granting permissions.

## Components And Responsibilities

WindowController converts AX frames into AppKit before selecting the window's
screen, using overlap for windows spanning screens. It uses visibleFrame for all
layouts, including maximization (not native macOS fullscreen), and checks the
results of position/size changes. Tests exercise coordinate math without AX access.

The hotkey manager owns its latest bindings and the event tap. Configuration
updates do not use snapshots captured by a permission timer. Permission loss
disables listening; granting permission activates the latest configuration.
Creation failure is visible and retryable. Incoming events are never additionally
retained when passed through. Disabled-tap notifications are handled explicitly.

The recorder updates NSView callbacks/state on every SwiftUI update. It releases
capture after a successful record or cancellation. The panel coordinates active
recording and suspends window actions during capture. Invalid proposals do not
overwrite existing bindings or enabled state.

AppDelegate owns the status item and a reusable floating panel. The panel opens
near the status item on click or the fixed global shortcut, and closing/hiding it
cancels recording. App shutdown stops the manager. No private SwiftUI introspection
or additional libraries are needed.

## Data Flow

Launch -> SettingsStore loads saved bindings -> manager starts permission checks.
Settings edit -> validation -> save -> manager receives current bindings.
Recording start/end -> panel coordinates suspension and capture lifecycle.
Global key -> panel toggle or window action -> AX result -> visible error on failure.
Permission change -> current listener state and current bindings, not launch snapshot.

## Verification

Tests must fail before each production correction. Run the complete XCTest suite,
Debug/Release builds, spec review followed by quality review, and a non-destructive
startup check. Real cross-application AX operation and multi-monitor hardware
validation remain explicitly unverified when the test process lacks permission.

## Exclusions

No new dependencies, snap zones, per-app profiles, native macOS fullscreen,
distribution/notarization, permission changes, or unsolicited commits. Do not
overwrite the user's other work. This supersedes contradictory behavior/defaults
in the original docs/superpowers design and plan.
