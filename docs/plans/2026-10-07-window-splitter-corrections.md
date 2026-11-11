# WindowSplitter Corrections Plan

Spec: docs/specs/2026-10-07-window-splitter-corrections-design.md
Execution: sequential, approved with the design. Preserve the current dirty worktree.
No commits or external permission changes were requested.

## T1: Geometry And Default Expectations

Objective: correct vertical layouts and screen coordinate selection.
Files: WindowSplitter/Models/WindowAction.swift,
WindowSplitter/Window/WindowController.swift,
WindowSplitterTests/WindowActionTests.swift,
WindowSplitterTests/WindowControllerTests.swift.
Blocked by: none. Blocks: T2.

1. Correct expectations for top/bottom/quarters and valid keycode zero; assert WASD.
2. Add failing coordinate and monitor-overlap regression tests, including above,
   below, negative X and nonzero visibleFrame origins.
3. Correct geometry and expose only the small pure math needed by production/tests.
4. Check AX reads/writes; apply size/position in an order that avoids large-window
   position clamping and return useful errors rather than swallowing failures.
5. Regenerate the ignored Xcode project to include new tests, run the suite and
   sequential spec/quality reviews before unblocking T2.

## T2: Listener Lifecycle And Shortcut State

Objective: maintain current settings and safely dispatch global events.
Files: WindowSplitter/Engine/GlobalHotkeyManager.swift,
WindowSplitterTests/GlobalHotkeyManagerTests.swift.
Blocked by: T1. Blocks: T3.

1. Write failing tests for updates before permission grant, disabled bindings,
   recording suspension, panel shortcut, modifier normalization, tap recovery,
   listener creation failure, permission loss and event pass-through identity.
2. Use the minimum injected native-operation closures needed for deterministic
   lifecycle tests without touching the machine's Accessibility authorization.
3. Keep current bindings; monitor permission changes; expose observable permission
   and failure status; create/recover/tear down taps with clear ownership.
4. Dispatch Option+Shift+Space through a panel callback and return unretained
   incoming events. Ignore Caps Lock/numeric-pad metadata when matching key chords.
5. Run suite and sequential spec/quality reviews before unblocking T3.

## T3: Recording, Validation And Native Panel

Objective: safely configure shortcuts and open the panel through native APIs.
Files: WindowSplitter/Store/SettingsStore.swift,
WindowSplitter/UI/ShortcutRecorderButton.swift,
WindowSplitter/UI/ShortcutRowView.swift,
WindowSplitter/UI/ConfigPanelView.swift,
WindowSplitter/AppDelegate.swift,
WindowSplitter/WindowSplitterApp.swift,
WindowSplitterTests/SettingsStoreTests.swift,
WindowSplitterTests/ShortcutRecorderTests.swift,
WindowSplitterTests/AppDelegateTests.swift,
docs/superpowers/specs/2026-05-30-window-splitter-design.md,
docs/superpowers/plans/2026-05-31-window-splitter.md.
Blocked by: T2. Blocks: final verification.

1. Write failing tests for inactive/one-shot capture, fresh callbacks, Escape and
   focus cancellation, modifier/duplicate/reserved validation, enabled-state
   preservation and panel click/keyboard toggle lifecycle.
2. Correct the NSView bridge and coordinate recording suspension centrally in the
   panel. Keep user errors visible without overwriting saved settings.
3. Own NSStatusItem/NSPanel in AppDelegate, hosting ConfigPanelView; wire launch,
   panel callback, cancellation on hide/focus loss and shutdown. Use public APIs.
4. Open Accessibility preferences directly. Provide listener/AX errors in the panel.
5. Update original documentation to point to this correction spec and reflect WASD.
6. Regenerate project; run full suite and both builds. Obtain sequential spec and
   quality reviews; address findings with failing tests before fixes.
7. Check non-destructive startup and record real evidence plus unverified AX/UI
   hardware cases. Do not mark manual cross-app validation completed without it.
