# WindowSplitter — Design Spec
**Date:** 2026-05-30
**Status:** Approved

**Superseded behavior (2026-10-07):** The approved
[correction design](../../specs/2026-10-07-window-splitter-corrections-design.md)
and [correction plan](../../plans/2026-10-07-window-splitter-corrections.md)
take precedence over this historical document. Keep saved bindings and macOS 13.
AppDelegate now owns a native NSStatusItem and reusable nonactivating NSPanel;
SwiftUI hosts the content. Recording is exclusive, suspends window actions and
cancels on Escape, focus loss, hide or close. New proposals require Control,
Option or Command and reject duplicates and reserved Option+Shift+Space.
Permission monitoring continues through revocation; listener/AX/validation errors
are visible. Accessibility settings open directly without a TCC prompt.

---

## Overview

A lightweight macOS menu bar utility built with Swift + SwiftUI that lets users split and position windows using global keyboard shortcuts. A small floating panel allows enabling/disabling shortcuts and customizing key bindings.

---

## Architecture

Three distinct layers:

```
┌─────────────────────────────────────┐
│           UI Layer (SwiftUI)        │
│  NSStatusItem + NSPanel / SwiftUI   │
├─────────────────────────────────────┤
│         Shortcut Engine             │
│  GlobalHotkeyManager (CGEventTap)   │
├─────────────────────────────────────┤
│         Window Manager              │
│  WindowController (Accessibility)   │
└─────────────────────────────────────┘
```

### Components

- **NSStatusItem** — Owned by AppDelegate. Click and Option+Shift+Space toggle the same ConfigPanel.
- **GlobalHotkeyManager** — Registers global shortcuts via `CGEventTap`. Listens even when the app is not focused. Fires the appropriate window action when a shortcut is detected.
- **WindowController** — Uses `AXUIElement` (Accessibility API) to get the currently focused window and apply a layout frame calculated from the active screen bounds.
- **ConfigPanel** — `NSPanel` floating window built in SwiftUI. Lists all actions with their current shortcut (clickable to record a new one) and a toggle to enable/disable each action individually.
- **SettingsStore** — Persists configuration to `UserDefaults`. Stores enabled state (`Bool`) and key binding (keyCode + modifiers as `Int`) for each action.

---

## Actions & Default Shortcuts

All defaults use `⌥⇧` (Option + Shift) as the modifier base.

| Action | Default Shortcut |
|---|---|
| Left half | `⌥⇧ A` |
| Right half | `⌥⇧ D` |
| Top half | `⌥⇧ W` |
| Bottom half | `⌥⇧ S` |
| Left third | `⌥⇧ 1` |
| Center third | `⌥⇧ 2` |
| Right third | `⌥⇧ 3` |
| Top-left quarter | `⌥⇧ U` |
| Top-right quarter | `⌥⇧ I` |
| Bottom-left quarter | `⌥⇧ J` |
| Bottom-right quarter | `⌥⇧ K` |
| Fullscreen | `⌥⇧ ↩` |

Each action computes the exact pixel frame from the active screen's `visibleFrame` and applies it to the focused window via `AXUIElement`.

---

## UI — ConfigPanel

Opens on menu bar icon click or via the global shortcut `⌥⇧ Space`.

```
┌─────────────────────────────────┐
│  🪟 WindowSplitter          [×] │
├─────────────────────────────────┤
│  Left half          [⌥⇧A]  [●] │
│  Right half         [⌥⇧D]  [●] │
│  Top half           [⌥⇧W]  [●] │
│  Bottom half        [⌥⇧S]  [●] │
│  ─────────────────────────────  │
│  Left third         [⌥⇧1]  [●] │
│  Center third       [⌥⇧2]  [●] │
│  Right third        [⌥⇧3]  [●] │
│  ─────────────────────────────  │
│  Top-left quarter   [⌥⇧U]  [●] │
│  Top-right quarter  [⌥⇧I]  [●] │
│  Bottom-left quarter[⌥⇧J]  [●] │
│  Bottom-right quarter[⌥⇧K] [●] │
│  ─────────────────────────────  │
│  Fullscreen         [⌥⇧↩]  [●] │
├─────────────────────────────────┤
│  ⚠️ Accessibility: [Enable]     │
└─────────────────────────────────┘
```

- **Shortcut button** `[⌥⇧A]` — click to record one valid combination, preserving the current enabled state. Escape cancels; invalid combinations show an error without overwriting settings.
- **Toggle** `[●]` — enables or disables that specific action. Disabled actions are not registered as global shortcuts.
- **Accessibility banner** — shown at the bottom when `AXIsProcessTrusted()` returns false. The "Enable" button opens `System Settings → Privacy & Security → Accessibility` directly. All shortcuts remain inactive until permission is granted.

---

## Persistence

Stored in `UserDefaults` per action:
- `enabled`: `Bool` — whether the shortcut is active
- `keyCode`: `Int` — the key code of the binding
- `modifiers`: `Int` — the modifier flags bitmask

On app launch, `SettingsStore` loads saved config and `GlobalHotkeyManager` registers only the enabled shortcuts.

---

## Permissions

- On first launch, `AXIsProcessTrusted()` is checked.
- If not granted: banner shown in ConfigPanel, shortcuts disabled, button to open System Settings.
- A `Timer` polls `AXIsProcessTrusted()` every second until shutdown, observing both grants and revocations and retrying listener failures with current bindings. No app restart required.

---

## Out of Scope

- Multi-monitor layout targeting (actions always apply to the screen the active window is on)
- Snap zones (drag-to-snap)
- Per-app shortcut profiles
- App Store distribution (Accessibility API requires entitlements not available on sandbox)
