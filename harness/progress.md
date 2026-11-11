# Progress - WindowSplitter Corrections

**Plan:** docs/plans/2026-10-07-window-splitter-corrections.md
**Spec:** docs/specs/2026-10-07-window-splitter-corrections-design.md
**Started:** 2026-10-07
**State:** implementation completed; manual hardware/AX validation pending

## Tasks

| ID | Task | State | Blocked by | Blocks |
|----|------|-------|------------|--------|
| T1 | Geometry and default expectations | completed | none | T2 |
| T2 | Listener lifecycle and shortcut state | completed | T1 completed | T3 |
| T3 | Recording, validation and native panel | completed | T2 completed | final verification passed |

## Log

- 2026-10-07: User approved keeping WASD and the coordinated native-panel design.
- 2026-10-07: Baseline review: Debug/Release build; 19 XCTest tests, 1 failure;
  standalone regression probe reports 8 failures. AX permission absent in probe.
- 2026-10-07: Work is sequential. Existing user modifications are retained; no
  commits requested. Live window manipulation and permission changes excluded.
- 2026-10-07: T1 implemented; awaiting external spec-compliance review followed by
  code-quality review. Not completed; T2/T3 remain blocked and were not changed.
  Preserved existing WASD defaults and persistence; inspected the sole apply caller
  in GlobalHotkeyManager without editing it. No commits, branch switches, global
  configuration edits, permission changes or live AX window operations.
- 2026-10-07: T1 root causes: vertical actions used flipped Y in AppKit; screen
  selection used an unconverted AX position instead of the window's overlap;
  unchecked position-before-size writes could clamp a large window and hide errors.
  Production now uses pure flippedFrame/screenIndex helpers, checked AX reads/types/
  value extraction/creation/writes, and size-before-position. apply returns String?
  (nil on success); a position failure after resizing reports the error without rollback.
- 2026-10-07: Verified artifact parent with
  `ls /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode` before xcodebuild.
  Verified repository parent with `ls /Users/shadownox97/Desktop/PersonalProjects/window_spliter`
  before `xcodegen generate`; output: `Created project at /Users/shadownox97/Desktop/PersonalProjects/window_spliter/WindowSplitter.xcodeproj`.
  `git check-ignore WindowSplitter.xcodeproj` confirms the regenerated project is ignored.

## T1 Verification Evidence

All full-suite RED/GREEN runs used this exact command in the current worktree:

```sh
xcodebuild test -project WindowSplitter.xcodeproj -scheme WindowSplitter -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -derivedDataPath /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes CODE_SIGNING_ALLOWED=NO
```

| Run (2026-10-07, -0600) | Exact output summary | Evidence |
|------------------------|----------------------|----------|
| 09:26:12 geometry RED | Executed 21 tests, with 12 failures (0 unexpected); ** TEST FAILED ** | Six inverted vertical layouts and six offset-origin assertions fail; WASD/keycode zero pass. |
| 09:27:15 geometry GREEN | Executed 21 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | Only the six vertical Y formulas changed. |
| 09:31:55 new controller API RED | Type 'WindowController' has no member 'flippedFrame'; Type 'WindowController' has no member 'screenIndex'; Testing cancelled because the build failed.; ** TEST FAILED ** | Compile-time RED before adding the testable API/AX closures; not an executed XCTest assertion failure. |
| 09:33:37 controller runtime RED | Executed 35 tests, with 10 failures (0 unexpected); ** TEST FAILED ** | Extracted legacy height/origin selection/write ordering and ignored write errors reproduce the regressions with mocked AX only. |
| 09:34:46 conversion GREEN | Executed 2 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | Command above plus the two only-testing arguments below. |
| 09:35:43 overlap GREEN / writes RED | Executed 35 tests, with 6 failures (0 unexpected); ** TEST FAILED ** | Conversion/overlap pass; remaining failures are size-position ordering, clamping and swallowed write errors. |
| 09:37:15 full GREEN | Executed 35 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | Checked size-before-position writes pass. |
| 09:39:58 final full GREEN | Executed 35 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | Final test cleanup makes the simulated large size also be the size returned by AX reads. |

The conversion-only command appended:

```sh
-only-testing:WindowSplitterTests/WindowControllerTests/test_conversionUsesPrimaryScreenTopNotDesktopUnionOrHeight -only-testing:WindowSplitterTests/WindowControllerTests/test_coordinateConversionAcrossScreenArrangements
```

Result bundles are under
`/var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes/Logs/Test/`.
The runtime RED bundle is `Test-WindowSplitter-2026.10.07_09-33-37--0600.xcresult`;
final GREEN is `Test-WindowSplitter-2026.10.07_09-39-58--0600.xcresult`.
Final suite: SettingsStoreTests 4, WindowActionTests 17, WindowControllerTests 14.
`git diff --check` passed (no output).

Non-blocking environment diagnostics: XCTest libraries built for macOS 14 linked
against the macOS 13 test target; AppIntents metadata skipped without that framework;
test-host `com.apple.linkd.autoShortcut` connection errors (Code=4097). Tests pass.
Real cross-app AX behavior, app-specific sizing constraints and physical multi-monitor
validation remain unverified by design.

- 2026-10-07: T1 approved by independent spec-compliance and code-quality reviewers
  sequentially. Quality reviewer read the final xcresult: 35 passed, 0 failed,
  0 skipped. T1 completed; T2 unblocked and started. T3 still blocked.

## T2 Implementation And Review Handoff

- 2026-10-07: Implemented ONLY T2; state is review, NOT completed. Independent
  spec-compliance review followed by code-quality review remain pending. T3 stays
  blocked. No commits, branches, TCC prompts/changes, posted events or moved windows.
  Only GlobalHotkeyManager.swift, new GlobalHotkeyManagerTests.swift and this tracker
  were edited. Existing UI/AppDelegate/Store/Controller/model modifications retained.
- Root causes reproduced at runtime: the permission timer captured launch bindings
  and stopped after grant; update destroyed healthy listeners; permission revocation
  was not observed; tap creation/enable errors were ignored; disabled notifications
  were treated as key events; incidental flags prevented matching; passRetained
  leaked borrowed input; recording/panel dispatch was missing; AX errors were discarded.
  Disabled-binding filtering and meaningful/persisted modifier behavior already passed
  in the legacy engine and remain regression checks, not claimed as new fixes.
- Added only five native-operation closures: isTrusted, createTap, enableTap,
  isTapEnabled and performAction. Tests use trusted stubs, local CFMachPortCreate
  ports (NOT input taps), in-memory CGEvents and injected action results. They invoke
  the actual callback supplied by production and the same refreshPermission path
  used by the real repeating timer. No native AX action or input-event posting occurs.
- One weak repeating timer, every second in main common modes, observes grants,
  revocations and retries. currentBindings is always updated, including while stopped
  or untrusted; matching reads it directly. Healthy taps survive configuration edits.
  Teardown disables/invalidates the port, removes/invalidates the run-loop source;
  stop/deinit invalidate the timer. Queue closures are weak and capture no CGEvent.
- Additional runtime RED proved that simple boolean guards allowed old queued work
  after quick capture cancellation or stop/restart, and allowed actions after permission
  loss before polling. One dispatch-generation counter cancels old sessions; an
  unprompted trust check before the injected action prevents the stale AX dispatch.
- Regenerated ignored WindowSplitter.xcodeproj with xcodegen generate after verifying
  repo/artifact parent directories. git check-ignore returned WindowSplitter.xcodeproj.

### API For T3

All configuration/lifecycle calls and callbacks use the main thread/run loop.

- ObservableObject with read-only @Published hasAccessibility, isListening,
  listenerError and actionError. actionError receives WindowController.apply's String?
  result (nil success, string failure), clearing after the next successful action.
- currentBindings is read-only externally; start(bindings:) and update(bindings:)
  always replace it without modifying persisted data or revalidating older shortcuts.
- isRecording = true suspends window actions and cancels previously queued work;
  set false on completion/cancellation to restore actions without replacing the tap.
- onTogglePanel runs asynchronously on main for keycode 49 + exactly Option/Shift
  after modifier normalization, ahead of any persisted window binding, even during
  recording. Hiding the panel/cancelling its recorder belongs to T3, not this callback.
- refreshPermission() supports explicit retry as well as timer monitoring;
  stop() is idempotent and requires explicit start to listen again. onPermissionGranted
  is temporarily preserved for the current ConfigPanelView; T3 can remove it when
  the view observes hasAccessibility. T3 owns recorder validation and native NSPanel.

### RED/GREEN Evidence

Every full-suite run below used exactly:

```sh
xcodebuild test -project WindowSplitter.xcodeproj -scheme WindowSplitter -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -derivedDataPath /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes CODE_SIGNING_ALLOWED=NO
```

Raw stdout/stderr logs named below are in
`/Users/shadownox97/.local/share/opencode/tool-output/`.
Failures in XCTest summaries count assertions, not distinct failed test cases.

| Run (2026-10-07, -0600) | Exact output summary | Raw log / change |
|------------------------|----------------------|------------------|
| 09:55:29 API compile RED | Value of type 'GlobalHotkeyManager' has no member 'currentBindings'; Argument passed to call that takes no arguments; Testing cancelled because the build failed.; ** TEST FAILED ** | Session tool output; missing observable/lifecycle/DI API, not runtime evidence. |
| 09:56:33 first runtime RED | Executed 55 tests, with 60 failures (1 unexpected); ** TEST FAILED ** | tool_11714b5ae001AMCAPfqi1xECAE; injected native seams retain legacy behavior. Duplicate polling overfulfilled an expectation; test adjusted without changing production. |
| 09:57:55 clean runtime RED | Executed 55 tests, with 60 failures (0 unexpected); ** TEST FAILED ** | tool_11715f846001oVad1dzg7qMMoZ; legacy root causes reproduced before fixes; all 35 T1 tests pass. |
| 09:59:04 lifecycle partial | Fatal error: Index out of range; ** TEST FAILED ** | tool_1171705df001pDKYy9YGJtK2T8; lifecycle tests pass, missing enable recovery means second test port does not exist. Replaced test index with last plus an explicit creation-count assertion. Not a clean full-suite result. |
| 10:00:17 lifecycle GREEN / remaining RED | Executed 55 tests, with 36 failures (0 unexpected); ** TEST FAILED ** | tool_117182bf2001vwVQGquFDSOETh; latest bindings, grant/revoke polling, healthy tap reuse and cleanup pass. |
| 10:01:29 recovery GREEN / remaining RED | Executed 55 tests, with 15 failures (0 unexpected); ** TEST FAILED ** | tool_117193e50001XHMHxg6GThPvl2; creation/enable failures, retries and both disabled notifications pass. |
| 10:02:34 dispatch GREEN / AX-error RED | Executed 55 tests, with 2 failures (0 unexpected); ** TEST FAILED ** | tool_1171a3b15001tzdaHppc3g2s43; recording, fixed panel callback, normalized modifiers and borrowed-event ownership pass; AX error still discarded. |
| 10:03:33 first full GREEN | Executed 55 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_1171b2b7c001ZgWLQsB7RdLBiv; action error published and cleared on success. |
| 10:05:35 queued-session runtime RED | Executed 58 tests, with 7 failures (0 unexpected); ** TEST FAILED ** | tool_1171d06670012mrzrIGearigfT; three new tests reproduce late action/panel dispatch and permission-loss race. |
| 10:06:27 queued-session GREEN | Executed 58 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_1171dca5a001gVtMml7OxBcj79; dispatch generation and pre-action trust check. |
| 10:09:08 final refactor GREEN | Executed 58 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_117203cdb001zqshxZOg1u51Qz; removed duplicated registeredShortcuts state and test warning. |

Final suite: GlobalHotkeyManagerTests 23, SettingsStoreTests 4, WindowActionTests 17,
WindowControllerTests 14. Final bundle:
`/var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes/Logs/Test/Test-WindowSplitter-2026.10.07_10-09-08--0600.xcresult`.

Read final bundle with:

```sh
xcrun xcresulttool get test-results summary --path /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes/Logs/Test/Test-WindowSplitter-2026.10.07_10-09-08--0600.xcresult
```

Exact summary fields: result Passed, totalTestCount 58, passedTests 58, failedTests 0,
skippedTests 0, expectedFailures 0, testFailures []. The host is macOS 26.6.2/arm64;
the deployment target remains macOS 13. Older xcresult paths (including the earliest
T2 RED and historical T1 bundles) were pruned from DerivedData during build/test
housekeeping. The recorded raw stdout logs above remain available; do not rely on
an older bundle still existing. No manual artifact deletion was performed.

Both application builds used the following command, with CONFIG replaced by Release
(10:09:58) and Debug (10:11:29):

```sh
xcodebuild build -project WindowSplitter.xcodeproj -scheme WindowSplitter -configuration CONFIG -destination 'platform=macOS,arch=arm64' -derivedDataPath /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes CODE_SIGNING_ALLOWED=NO
```

Both returned ** BUILD SUCCEEDED **; Release raw log: tool_117210171001uRtedDQ8K0OErP.
git diff --check passed (no output). Only existing non-blocking XCTest macOS-14 linkage,
AppIntents metadata and linkd connection diagnostics were observed in final tests.

Unverified by design: real TCC grant/revocation, Quartz input delivery/timeout behavior,
cross-app AX window operations and physical monitor behavior; actual macOS 13 runtime
was not available. Native panel/recorder wiring and validation remain exclusively T3.
No final manual validation is claimed.

- 2026-10-07: T2 approved by independent spec-compliance and code-quality reviewers
  sequentially; 58 tests passed, 0 failed, Debug/Release builds succeeded. T2
  completed; T3 unblocked and started.

## T3 Implementation And Review Handoff

- 2026-10-08: ONLY T3 implemented and verified; state is review, NOT completed.
  Independent spec-compliance review followed by code-quality review remain pending.
  No reviewer approval is claimed: this session has no subagent-dispatch tool.
  T1 code/tests were not edited; all pre-existing worktree changes were preserved.
  No commits, branch creation/switches, permission prompts/changes, globally posted
  events or cross-app window operations. No dependencies or new interfaces.
- Runtime root causes: unvalidated save overwrote invalid/conflicting/reserved chords
  and trusted stale enabled state; capture had no active/one-shot gate, treated Escape
  as a binding and retained the initial SwiftUI callback; focus/hide/close did not end
  recording or suspend actions; AppDelegate had neither native panel callback nor
  shutdown cleanup; ConfigPanelView's local permission snapshot ignored revocation
  and did not observe listener/AX errors.
- Native NSPanel.sendEvent regression exposed an additional attachment-order bug:
  SwiftUI update could activate the capture before it had a window, so the first
  recording session lacked a first responder. viewDidMoveToWindow now acquires it.
  Control, Option and Command all pass through our own native panel in tests without
  activating the target app. No key-equivalent override was needed on this host.

### API And Wiring

- SettingsStore.save(action:binding:recording:) now returns String? (nil success,
  visible error on rejection). Chord edits and every recording proposal validate
  Control/Option/Command, normalized duplicates including disabled actions, and
  reserved Option+Shift+Space. An unchanged re-recorded legacy chord still validates.
  Toggles retain saved legacy chords without revalidation. Recording preserves the
  current enabled value. UserDefaults keys/loading and WASD defaults are unchanged.
- ShortcutRecorderButton uses a caller-owned Binding<Bool>. KeyRecorderOverlay
  updates both mutable callbacks and isActive on every NSView update. Capture closes
  its gate before invoking a callback, normalizes meaningful modifiers, releases the
  responder and cancels on Escape/focus loss/dismantling. Inactive input is ignored.
- AppDelegate is ObservableObject with one published recordingAction; its synchronous
  didSet suspends/restores the existing engine and cancels the previous row. The
  SwiftUI per-row setter ignores cancellation from a different, formerly active row.
  ConfigPanelView observes the delegate, store and manager and displays validation,
  listener/retry, AX and permission state. Accessibility uses NSWorkspace.open with
  x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility;
  tests do not open that URL or System Settings. Quit is explicit in the panel.
- AppDelegate owns NSStatusItem and one reusable floating, titled/closable,
  nonactivating NSPanel hosting SwiftUI. Status target/action and onTogglePanel use
  togglePanel. Placement uses the status button's screen anchor and clamps to that
  screen's visibleFrame. No NSApp.activate, dummy Settings scene, global monitor or
  private SwiftUI introspection. A small NSPanel override observes direct orderOut;
  NSWindowDelegate handles resign-key/close. Shutdown stops the manager, clears
  callback/target/action/window delegate/content and removes the status item.
- WindowSplitterApp is an @main enum using NSApplication.shared, app.run and
  withExtendedLifetime(delegate). The real entry point runs as the XCTest host.
- ONLY engine change relative to completed T2: removed onPermissionGranted, its
  temporary declaration and grant-only invocation after observable UI tests passed.
  The sole T2 test using it was migrated to $hasAccessibility (two-line subscription/
  lifetime adapter); the same real-timer test passed BEFORE callback removal. No
  engine lifecycle/dispatch/action implementation was otherwise changed for T3.
- Original docs/superpowers design/plan now reflect WASD and link to the superseding
  correction spec/plan. Historical implementation snippets were not broadly rewritten
  and their manual permission/cross-app/hardware checkboxes remain unchecked.

### RED/GREEN Evidence

Every full-suite run below used exactly:

```sh
xcodebuild test -project WindowSplitter.xcodeproj -scheme WindowSplitter -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -derivedDataPath /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes CODE_SIGNING_ALLOWED=NO
```

Times below are the xcresult run-start timestamp, UTC-0600. XCTest failure counts
are assertion failures, not distinct test cases. Raw log names are under
`/Users/shadownox97/.local/share/opencode/tool-output/`. Build-only/API failures are
explicitly separate from executed runtime RED. Xcode prunes older result bundles;
the saved raw logs/session stdout are the historical evidence, not a guarantee
that each old xcresult still exists.

| Run | Exact output summary | Evidence / scope |
|-----|----------------------|------------------|
| 2026-10-07 13:59:07 runtime RED | Executed 63 tests, with 20 failures (0 unexpected); ** TEST FAILED ** | tool_117f2d3830014efxOGfEU7AUHB; plain/Shift, duplicates/reserved, stale enabled and inactive capture. All 31 T1 tests and 23 T2 tests pass. |
| 14:02:00 store/gate GREEN, capture RED | Executed 66 tests, with 9 failures (0 unexpected); ** TEST FAILED ** | tool_117f56e61001ivJsvXj8PAY0uK; Store 8/0; one-shot, Escape/focus, hosted bridge still fail. |
| 14:02:43 targeted runtime RED | Executed 4 tests, with 10 failures (0 unexpected); ** TEST FAILED ** | Session stdout; active bridge reproduces OLD callback called once, NEW callback zero, retained responder, extra modifiers and repeated capture. Only-testing ShortcutRecorderTests. |
| 14:05:43 DI API compile RED | Argument passed to call that takes no arguments; Testing cancelled because the build failed.; ** TEST FAILED ** | Session stdout; no injected AppDelegate initializer yet, not runtime evidence. |
| 14:06:38 initializer diagnostic | Fatal error: Use of unimplemented initializer 'init()' for class 'WindowSplitter.AppDelegate'; ** TEST FAILED ** | tool_117f9ab37001UTW5Jln0LXfU6C; SwiftUI adaptor still called ObjC init(). Added override convenience init, not claimed as legacy bug RED. |
| 14:08:06 capture GREEN, native runtime RED | Executed 68 tests, with 5 failures (0 unexpected); ** TEST FAILED ** | tool_117fb0541001amUY2t2Wq93myr; launch has no callback/panel, termination leaves listener/port enabled. |
| 14:09:44 native basic GREEN | Executed 68 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_117fc81a000120jj1XrCHV2lqW; owned panel/callback/shutdown and native app entry point. |
| 14:10:47 recording API compile RED | Value of type 'AppDelegate' has no member 'recordingAction'; Testing cancelled because the build failed.; ** TEST FAILED ** | Session stdout; property introduced without coordination to permit runtime reproduction, not counted as runtime RED. |
| 14:11:18 coordination runtime RED | Executed 72 tests, with 12 failures (0 unexpected); ** TEST FAILED ** | tool_117fdef47001tViWlesL6Ghf7N; missing suspension, no active hosted row, no hide/close/resign-key/orderOut cancellation. Native click/engine toggle/reuse/frontmost/clamping already pass. |
| 14:19:55 rendered UI runtime RED | Executed 1 test, with 2 failures (0 unexpected); ** TEST FAILED ** | Session stdout; both snapshots remain identical (707986 bytes) on AX error and permission revocation. Only-testing AppDelegateTests/test_hostedPanelRedrawsOnAXErrorAndPermissionRevocation. |
| 14:21:47 coordinated UI GREEN | Executed 73 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_118078f0d001LcQ8dCj9uVvzdX; single row, suspension, cancellation, latest enabled/engine settings and real NSHostingView redraws. |
| 14:22:44 unchanged legacy proposal RED | Executed 9 tests, with 4 failures (0 unexpected); ** TEST FAILED ** | tool_1180872f8001yAKDw2I3dq0pWB; 2 assertions prove silent acceptance/write of unchanged legacy plain chord. Other 2 were premature weak-release assertions; isolated below, not production-leak evidence. Only-testing AppDelegateTests. |
| 14:23:48 proposal GREEN | Executed 75 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_1180969e7001OSsmtx62C6S6u0; explicit recording validation. Release test now drains an autoreleasepool/run loop, WITHOUT any production cleanup change. |
| 14:24:52 native delivery runtime RED | Executed 77 tests, with 3 failures (0 unexpected); ** TEST FAILED ** | tool_1180a68ff001dLw3MYL5jWobui; first native Control session has no capture responder, does not complete or store modifier 262144. |
| 14:25:55 native delivery GREEN | Executed 1 test, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_1180b5473001hij9vE7jxnp8Gv; viewDidMoveToWindow fix. Only-testing AppDelegateTests/test_nativePanelDeliversControlOptionAndCommandCombinationsToRecorder. |
| 14:26:17 full GREEN before callback removal | Executed 77 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_1180bb323001N0KM3n1tw158VK; T2 permission-timer test already observes published state. |
| 14:28:10 full GREEN after cleanup | Executed 77 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_1180d61db001pJhKeMd91aGe3l; engine compatibility callback removed. |
| 2026-10-08 06:52:38 final full GREEN | Executed 77 tests, with 0 failures (0 unexpected); ** TEST SUCCEEDED ** | tool_11b92c765001YodLoMD7Dt0Nub; fresh final suite after Debug/Release builds, unchanged source. |

Initial rendered-text experiments at 14:12:43, 14:16:10 and 14:18:55 failed because
this host returned empty NSHostingView accessibilityChildren, including the positive
header control. Those experiments were discarded and are NOT claimed as valid
application regression RED. Native bitmap snapshots reproduced the actual missing
redraw before changing ConfigPanelView; no AX permission was requested for snapshots.

The final suite is AppDelegateTests 10, GlobalHotkeyManagerTests 23,
SettingsStoreTests 9, ShortcutRecorderTests 4, WindowActionTests 17,
WindowControllerTests 14. The T3 native tests use a dedicated UserDefaults suite,
trusted/tap/action stubs and local Mach ports, never real input taps or AX actions.
CGEvents are in-memory inputs to the injected tap callback, never posted. NSEvents
are delivered directly to our own KeyCaptureView/NSPanel. Tests may show/close only
our own panel/window. Native frontmost PID remains unchanged on panel opening.

Final result bundle:
`/var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes/Logs/Test/Test-WindowSplitter-2026.10.08_06-52-38--0600.xcresult`.

Read with:

```sh
xcrun xcresulttool get test-results summary --path /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes/Logs/Test/Test-WindowSplitter-2026.10.08_06-52-38--0600.xcresult
```

The final bundle was read with that command: result Passed, totalTestCount 77,
passedTests 77, failedTests 0, skippedTests 0, expectedFailures 0, testFailures [].
The preceding 14:28:10 bundle was also read: result Passed, totalTestCount 77,
passedTests 77, failedTests 0, skippedTests 0, expectedFailures 0, testFailures [].

Both application builds used this command with CONFIG replaced by Debug
(2026-10-07 14:36:42) and Release (2026-10-08 06:51:28):

```sh
xcodebuild build -project WindowSplitter.xcodeproj -scheme WindowSplitter -configuration CONFIG -destination 'platform=macOS,arch=arm64' -derivedDataPath /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes CODE_SIGNING_ALLOWED=NO
```

Both returned ** BUILD SUCCEEDED **. git diff --check passed with no output.
xcodegen generate was run after verifying the repository parent with ls; artifact
parent was verified with ls before testing. git check-ignore returned
WindowSplitter.xcodeproj. Generated project remains ignored.

Non-destructive startup evidence: every final XCTest launch executes the real
NSApplication entry point successfully; native launch/toggle/close/reopen/shutdown
tests pass with injected operations. This is NOT a manual hardware/cross-app smoke
test. Tests verify responder attachment, local native key delivery, floating/
nonactivating configuration, rendered error/revocation changes and object cleanup.

Non-blocking host/toolchain diagnostics: XCTest macOS-14 linkage against deployment
target 13, skipped AppIntents metadata, linkd Code=4097, status-item scene disconnect
messages and TSM UI-server messages. The final rebuild additionally reports parser
warnings for bundled XCTAutomationSupport/XCUIAutomation executables; tests still
run and pass. No production compile error is present.

### Pending And Unverified

- Independent spec-compliance and then code-quality reviews approved T3 on
  2026-10-08. Final verification evidence follows below.
- Real TCC grants/revocations, actual Quartz input delivery and timeout recovery,
  cross-app AX operations, physical keyboard/input-source variations and monitor
  hardware: not exercised. No app/window belonging to another application was moved.
- Actual macOS 13 runtime is unavailable; builds target 13, native tests ran on
  macOS 26.6.2/arm64. No claim of hardware keyboard-focus behavior on macOS 13.
- Accessibility preferences link and Quit click were not invoked in tests (to avoid
  opening System Settings or terminating XCTest). Native shutdown was tested directly.
- Bitmap tests prove redraws, not OCR of exact text or a manual visual/accessibility
  audit. No fixed image baselines or screenshot dependencies were added.

## Final Verification - 2026-10-08

- T3 approved by two independent reviewers in sequence (spec, then quality),
  with no blocking findings. T1/T2 approvals and regression evidence remain above.
- Main-session rerun at 07:16:00 used the full-suite command documented above:
  `Executed 77 tests, with 0 failures (0 unexpected)`; `** TEST SUCCEEDED **`.
  Result: `Test-WindowSplitter-2026.10.08_07-16-00--0600.xcresult` under the same
  temporary DerivedData Logs/Test directory. No skipped tests.
- Main-session builds at 07:16:14 (Debug) and 07:16:21 (Release) used the build
  command above: both `** BUILD SUCCEEDED **`. Code signing was disabled only
  for these local checks; distribution signing/notarization was not verified.
- Coverage query:
  `xcrun xccov view --report --only-targets /var/folders/5r/fttwpggd6td24kv__1ylyj880000gn/T/opencode/window-splitter-fixes/Logs/Test/Test-WindowSplitter-2026.10.08_07-16-00--0600.xcresult`.
  Application output: `94.08% (842/895)`, compared with review baseline 17.08%.
  This includes native local-panel tests and injected AX/Quartz operations, not
  actual permission changes or cross-app hardware tests.
- Spawned the standalone Release executable, waited three seconds and checked
  it had not exited: `PASS: Release app remained running for 3 seconds`.
  Terminated only that spawned process afterwards; no other windows were moved.
- `git diff --check`: no output. Existing worktree changes retained, new tests
  and source remain uncommitted. No dependencies or global configuration changed.
- All planned implementation tasks complete. Manual validation remains explicit:
  run from Xcode, grant Accessibility via Open Settings, exercise the twelve
  physical shortcuts, grant/revoke permissions and test real monitor arrangements.
  No claim of completed live AX, macOS 13 or physical keyboard validation.
