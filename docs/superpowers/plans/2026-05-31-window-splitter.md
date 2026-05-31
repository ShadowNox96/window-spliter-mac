# WindowSplitter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app in Swift that repositions the focused window via global keyboard shortcuts, with a floating panel to configure and toggle each shortcut.

**Architecture:** Three layers — `GlobalHotkeyManager` intercepts key events via CGEventTap, `WindowController` applies frames via AXUIElement, and a SwiftUI `ConfigPanelView` inside an NSPanel lets users toggle and re-bind shortcuts. `SettingsStore` persists config to UserDefaults.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, Accessibility API (AXUIElement), CGEventTap, UserDefaults, XCTest, xcodegen

---

## File Map

| File | Responsibility |
|---|---|
| `project.yml` | xcodegen project definition |
| `WindowSplitter/Info.plist` | App metadata, LSUIElement to hide Dock icon |
| `WindowSplitter/WindowSplitter.entitlements` | No sandbox (required for Accessibility) |
| `WindowSplitter/WindowSplitterApp.swift` | `@main` App, MenuBarExtra, wires all components |
| `WindowSplitter/Models/WindowAction.swift` | Enum of 12 actions, default key bindings, frame computation |
| `WindowSplitter/Store/SettingsStore.swift` | `@Observable` class, UserDefaults read/write per action |
| `WindowSplitter/Engine/GlobalHotkeyManager.swift` | CGEventTap registration, shortcut matching, permission polling |
| `WindowSplitter/Window/WindowController.swift` | AXUIElement: get focused window, set position+size |
| `WindowSplitter/UI/ConfigPanelView.swift` | SwiftUI root view of the floating panel |
| `WindowSplitter/UI/ShortcutRowView.swift` | Single row: action label + shortcut button + toggle |
| `WindowSplitter/UI/ShortcutRecorderButton.swift` | Button that enters recording state and captures next key press |
| `WindowSplitterTests/WindowActionTests.swift` | Tests for frame computation logic |
| `WindowSplitterTests/SettingsStoreTests.swift` | Tests for UserDefaults persistence |

---

## Task 1: Project scaffolding with xcodegen

**Files:**
- Create: `project.yml`
- Create: `WindowSplitter/Info.plist`
- Create: `WindowSplitter/WindowSplitter.entitlements`

- [ ] **Step 1: Install xcodegen if not present**

```bash
brew install xcodegen
```

Expected: `xcodegen` available in PATH.

- [ ] **Step 2: Create `project.yml`**

```yaml
name: WindowSplitter
options:
  bundleIdPrefix: com.local
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
targets:
  WindowSplitter:
    type: application
    platform: macOS
    sources:
      - path: WindowSplitter
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.local.WindowSplitter
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        CODE_SIGN_STYLE: Automatic
        ENABLE_HARDENED_RUNTIME: YES
        INFOPLIST_FILE: WindowSplitter/Info.plist
    entitlements:
      path: WindowSplitter/WindowSplitter.entitlements
      properties:
        com.apple.security.app-sandbox: false
  WindowSplitterTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: WindowSplitterTests
    dependencies:
      - target: WindowSplitter
    settings:
      base:
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
```

- [ ] **Step 3: Create `WindowSplitter/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.local.WindowSplitter</string>
    <key>CFBundleName</key>
    <string>WindowSplitter</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>WindowSplitter needs Accessibility access to move and resize windows.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create `WindowSplitter/WindowSplitter.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 5: Create source directories**

```bash
mkdir -p WindowSplitter/Models
mkdir -p WindowSplitter/Store
mkdir -p WindowSplitter/Engine
mkdir -p WindowSplitter/Window
mkdir -p WindowSplitter/UI
mkdir -p WindowSplitterTests
```

- [ ] **Step 6: Generate the Xcode project**

```bash
xcodegen generate
```

Expected: `WindowSplitter.xcodeproj` created with no errors.

- [ ] **Step 7: Commit**

```bash
git add project.yml WindowSplitter/ WindowSplitterTests/
git commit -m "chore: scaffold Xcode project with xcodegen"
```

---

## Task 2: WindowAction model and frame computation

**Files:**
- Create: `WindowSplitter/Models/WindowAction.swift`
- Create: `WindowSplitterTests/WindowActionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `WindowSplitterTests/WindowActionTests.swift`:

```swift
import XCTest
@testable import WindowSplitter

final class WindowActionTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func test_leftHalf_frame() {
        let frame = WindowAction.leftHalf.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 960, height: 1080))
    }

    func test_rightHalf_frame() {
        let frame = WindowAction.rightHalf.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 960, y: 0, width: 960, height: 1080))
    }

    func test_topHalf_frame() {
        let frame = WindowAction.topHalf.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 1920, height: 540))
    }

    func test_bottomHalf_frame() {
        let frame = WindowAction.bottomHalf.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 540, width: 1920, height: 540))
    }

    func test_leftThird_frame() {
        let frame = WindowAction.leftThird.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 640, height: 1080))
    }

    func test_centerThird_frame() {
        let frame = WindowAction.centerThird.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 640, y: 0, width: 640, height: 1080))
    }

    func test_rightThird_frame() {
        let frame = WindowAction.rightThird.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 1280, y: 0, width: 640, height: 1080))
    }

    func test_topLeftQuarter_frame() {
        let frame = WindowAction.topLeftQuarter.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 960, height: 540))
    }

    func test_topRightQuarter_frame() {
        let frame = WindowAction.topRightQuarter.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 960, y: 0, width: 960, height: 540))
    }

    func test_bottomLeftQuarter_frame() {
        let frame = WindowAction.bottomLeftQuarter.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 540, width: 960, height: 540))
    }

    func test_bottomRightQuarter_frame() {
        let frame = WindowAction.bottomRightQuarter.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 960, y: 540, width: 960, height: 540))
    }

    func test_fullscreen_frame() {
        let frame = WindowAction.fullscreen.frame(in: screen)
        XCTAssertEqual(frame, screen)
    }

    func test_allCasesHaveDefaultKeyCode() {
        for action in WindowAction.allCases {
            XCTAssertGreaterThan(action.defaultKeyCode, 0, "\(action) has invalid keyCode")
        }
    }

    func test_defaultModifiersAreOptionShift() {
        let expected = Int(NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        for action in WindowAction.allCases {
            XCTAssertEqual(action.defaultModifiers, expected)
        }
    }

    func test_frameWithOffset_screen() {
        let offsetScreen = CGRect(x: 1920, y: 0, width: 1280, height: 800)
        let frame = WindowAction.leftHalf.frame(in: offsetScreen)
        XCTAssertEqual(frame, CGRect(x: 1920, y: 0, width: 640, height: 800))
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure (WindowAction not defined)**

```bash
xcodebuild test -scheme WindowSplitter -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: compile error — `WindowAction` not found.

- [ ] **Step 3: Create `WindowSplitter/Models/WindowAction.swift`**

```swift
import AppKit

enum WindowAction: String, CaseIterable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case leftThird
    case centerThird
    case rightThird
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case fullscreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf:           return "Left half"
        case .rightHalf:          return "Right half"
        case .topHalf:            return "Top half"
        case .bottomHalf:         return "Bottom half"
        case .leftThird:          return "Left third"
        case .centerThird:        return "Center third"
        case .rightThird:         return "Right third"
        case .topLeftQuarter:     return "Top-left quarter"
        case .topRightQuarter:    return "Top-right quarter"
        case .bottomLeftQuarter:  return "Bottom-left quarter"
        case .bottomRightQuarter: return "Bottom-right quarter"
        case .fullscreen:         return "Fullscreen"
        }
    }

    // Virtual key codes (Carbon / CGKeyCode)
    var defaultKeyCode: Int {
        switch self {
        case .leftHalf:           return 123 // Left arrow
        case .rightHalf:          return 124 // Right arrow
        case .topHalf:            return 126 // Up arrow
        case .bottomHalf:         return 125 // Down arrow
        case .leftThird:          return 18  // 1
        case .centerThird:        return 19  // 2
        case .rightThird:         return 20  // 3
        case .topLeftQuarter:     return 32  // U
        case .topRightQuarter:    return 34  // I
        case .bottomLeftQuarter:  return 38  // J
        case .bottomRightQuarter: return 40  // K
        case .fullscreen:         return 36  // Return
        }
    }

    var defaultModifiers: Int {
        Int(NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    }

    /// Computes the target frame within `screenFrame` (AppKit coordinates).
    func frame(in screenFrame: CGRect) -> CGRect {
        let w = screenFrame.width
        let h = screenFrame.height
        let x = screenFrame.minX
        let y = screenFrame.minY
        switch self {
        case .leftHalf:           return CGRect(x: x,           y: y,           width: w / 2,   height: h)
        case .rightHalf:          return CGRect(x: x + w / 2,   y: y,           width: w / 2,   height: h)
        case .topHalf:            return CGRect(x: x,           y: y,           width: w,       height: h / 2)
        case .bottomHalf:         return CGRect(x: x,           y: y + h / 2,   width: w,       height: h / 2)
        case .leftThird:          return CGRect(x: x,           y: y,           width: w / 3,   height: h)
        case .centerThird:        return CGRect(x: x + w / 3,   y: y,           width: w / 3,   height: h)
        case .rightThird:         return CGRect(x: x + 2 * w / 3, y: y,         width: w / 3,   height: h)
        case .topLeftQuarter:     return CGRect(x: x,           y: y,           width: w / 2,   height: h / 2)
        case .topRightQuarter:    return CGRect(x: x + w / 2,   y: y,           width: w / 2,   height: h / 2)
        case .bottomLeftQuarter:  return CGRect(x: x,           y: y + h / 2,   width: w / 2,   height: h / 2)
        case .bottomRightQuarter: return CGRect(x: x + w / 2,   y: y + h / 2,   width: w / 2,   height: h / 2)
        case .fullscreen:         return CGRect(x: x,           y: y,           width: w,       height: h)
        }
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test -scheme WindowSplitter -destination 'platform=macOS' -only-testing WindowSplitterTests/WindowActionTests 2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: all 13 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add WindowSplitter/Models/WindowAction.swift WindowSplitterTests/WindowActionTests.swift
git commit -m "feat: add WindowAction model with frame computation"
```

---

## Task 3: SettingsStore

**Files:**
- Create: `WindowSplitter/Store/SettingsStore.swift`
- Create: `WindowSplitterTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `WindowSplitterTests/SettingsStoreTests.swift`:

```swift
import XCTest
@testable import WindowSplitter

final class SettingsStoreTests: XCTestCase {
    var store: SettingsStore!
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SettingsStoreTests")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests")
        store = SettingsStore(defaults: defaults)
    }

    func test_defaultsLoadCorrectly() {
        for action in WindowAction.allCases {
            let binding = store.bindings[action]!
            XCTAssertEqual(binding.keyCode, action.defaultKeyCode)
            XCTAssertEqual(binding.modifiers, action.defaultModifiers)
            XCTAssertTrue(binding.enabled)
        }
    }

    func test_saveAndReload() {
        let newBinding = ShortcutBinding(keyCode: 99, modifiers: 123456, enabled: false)
        store.save(action: .leftHalf, binding: newBinding)

        let reloadedStore = SettingsStore(defaults: defaults)
        let loaded = reloadedStore.bindings[.leftHalf]!
        XCTAssertEqual(loaded.keyCode, 99)
        XCTAssertEqual(loaded.modifiers, 123456)
        XCTAssertFalse(loaded.enabled)
    }

    func test_saveDoesNotAffectOtherActions() {
        let newBinding = ShortcutBinding(keyCode: 99, modifiers: 0, enabled: false)
        store.save(action: .leftHalf, binding: newBinding)

        let reloadedStore = SettingsStore(defaults: defaults)
        let rightHalf = reloadedStore.bindings[.rightHalf]!
        XCTAssertEqual(rightHalf.keyCode, WindowAction.rightHalf.defaultKeyCode)
        XCTAssertTrue(rightHalf.enabled)
    }

    func test_enabledBindings_excludesDisabled() {
        var binding = store.bindings[.leftHalf]!
        binding.enabled = false
        store.save(action: .leftHalf, binding: binding)

        let enabled = store.enabledBindings
        XCTAssertNil(enabled[.leftHalf])
        XCTAssertNotNil(enabled[.rightHalf])
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test -scheme WindowSplitter -destination 'platform=macOS' -only-testing WindowSplitterTests/SettingsStoreTests 2>&1 | tail -20
```

Expected: compile error — `SettingsStore`, `ShortcutBinding` not found.

- [ ] **Step 3: Create `WindowSplitter/Store/SettingsStore.swift`**

```swift
import Foundation
import Observation

struct ShortcutBinding {
    var keyCode: Int
    var modifiers: Int
    var enabled: Bool
}

@Observable
final class SettingsStore {
    private let defaults: UserDefaults
    var bindings: [WindowAction: ShortcutBinding] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in WindowAction.allCases {
            bindings[action] = ShortcutBinding(
                keyCode: defaults.object(forKey: keyCodeKey(action)) as? Int ?? action.defaultKeyCode,
                modifiers: defaults.object(forKey: modifiersKey(action)) as? Int ?? action.defaultModifiers,
                enabled: defaults.object(forKey: enabledKey(action)) as? Bool ?? true
            )
        }
    }

    func save(action: WindowAction, binding: ShortcutBinding) {
        bindings[action] = binding
        defaults.set(binding.keyCode, forKey: keyCodeKey(action))
        defaults.set(binding.modifiers, forKey: modifiersKey(action))
        defaults.set(binding.enabled, forKey: enabledKey(action))
    }

    var enabledBindings: [WindowAction: ShortcutBinding] {
        bindings.filter { $0.value.enabled }
    }

    private func keyCodeKey(_ action: WindowAction) -> String { "\(action.rawValue).keyCode" }
    private func modifiersKey(_ action: WindowAction) -> String { "\(action.rawValue).modifiers" }
    private func enabledKey(_ action: WindowAction) -> String { "\(action.rawValue).enabled" }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test -scheme WindowSplitter -destination 'platform=macOS' -only-testing WindowSplitterTests/SettingsStoreTests 2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add WindowSplitter/Store/SettingsStore.swift WindowSplitterTests/SettingsStoreTests.swift
git commit -m "feat: add SettingsStore with UserDefaults persistence"
```

---

## Task 4: WindowController (AXUIElement)

**Files:**
- Create: `WindowSplitter/Window/WindowController.swift`

> Note: AXUIElement calls cannot be unit tested without Accessibility permission and a real running app. This file is integration-tested manually.

- [ ] **Step 1: Create `WindowSplitter/Window/WindowController.swift`**

```swift
import AppKit
import ApplicationServices

final class WindowController {

    /// Applies `action` to the currently focused window.
    func apply(_ action: WindowAction) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )
        guard result == .success, let ref = focusedWindowRef else { return }
        let window = ref as! AXUIElement

        guard let screen = screen(for: window) else { return }
        let targetFrame = action.frame(in: screen.visibleFrame)
        setFrame(targetFrame, on: window, screen: screen)
    }

    // MARK: - Private

    private func screen(for window: AXUIElement) -> NSScreen? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              let posVal = posRef else { return NSScreen.main }
        var point = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func setFrame(_ frame: CGRect, on window: AXUIElement, screen: NSScreen) {
        // AX coordinate system has origin at top-left of the primary screen.
        // Convert AppKit (bottom-left origin) to AX (top-left origin).
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let axY = primaryScreenHeight - frame.maxY

        var position = CGPoint(x: frame.minX, y: axY)
        var size = CGSize(width: frame.width, height: frame.height)

        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -scheme WindowSplitter -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 3: Commit**

```bash
git add WindowSplitter/Window/WindowController.swift
git commit -m "feat: add WindowController using AXUIElement"
```

---

## Task 5: GlobalHotkeyManager (CGEventTap)

**Files:**
- Create: `WindowSplitter/Engine/GlobalHotkeyManager.swift`

- [ ] **Step 1: Create `WindowSplitter/Engine/GlobalHotkeyManager.swift`**

```swift
import AppKit

final class GlobalHotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var registeredShortcuts: [(keyCode: Int, modifiers: Int, action: WindowAction)] = []
    private let windowController = WindowController()
    private var permissionTimer: Timer?

    /// Called on the main thread once Accessibility permission is granted.
    var onPermissionGranted: (() -> Void)?

    // MARK: - Public

    /// Starts listening. If Accessibility is not yet granted, begins polling.
    func start(bindings: [WindowAction: ShortcutBinding]) {
        if AXIsProcessTrusted() {
            register(bindings: bindings)
        } else {
            startPermissionPolling(bindings: bindings)
        }
    }

    /// Re-registers shortcuts with updated bindings (e.g. after user changes a shortcut).
    func update(bindings: [WindowAction: ShortcutBinding]) {
        tearDown()
        if AXIsProcessTrusted() {
            register(bindings: bindings)
        }
    }

    func stop() {
        tearDown()
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - Private

    private func register(bindings: [WindowAction: ShortcutBinding]) {
        registeredShortcuts = bindings.compactMap { action, binding in
            guard binding.enabled else { return nil }
            return (keyCode: binding.keyCode, modifiers: binding.modifiers, action: action)
        }

        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let deviceMask = NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
        let modifiers = Int(event.flags.rawValue & deviceMask)

        for shortcut in registeredShortcuts {
            let expected = shortcut.modifiers & Int(deviceMask)
            if shortcut.keyCode == keyCode && expected == modifiers {
                let action = shortcut.action
                DispatchQueue.main.async { [weak self] in
                    self?.windowController.apply(action)
                }
                return nil // consume the event
            }
        }
        return Unmanaged.passRetained(event)
    }

    private func tearDown() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        registeredShortcuts = []
    }

    private func startPermissionPolling(bindings: [WindowAction: ShortcutBinding]) {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.register(bindings: bindings)
            self?.onPermissionGranted?()
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -scheme WindowSplitter -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add WindowSplitter/Engine/GlobalHotkeyManager.swift
git commit -m "feat: add GlobalHotkeyManager with CGEventTap and permission polling"
```

---

## Task 6: ShortcutRecorderButton

**Files:**
- Create: `WindowSplitter/UI/ShortcutRecorderButton.swift`

- [ ] **Step 1: Create `WindowSplitter/UI/ShortcutRecorderButton.swift`**

```swift
import SwiftUI
import AppKit

/// A button that displays the current shortcut. When clicked, enters recording mode
/// and captures the next key press + modifiers, then calls `onRecord`.
struct ShortcutRecorderButton: View {
    let binding: ShortcutBinding
    let onRecord: (ShortcutBinding) -> Void

    @State private var isRecording = false

    var body: some View {
        Button(action: { isRecording = true }) {
            Text(isRecording ? "Press keys…" : label(for: binding))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .foregroundColor(isRecording ? .accentColor : .primary)
        .background(KeyRecorderOverlay(isActive: isRecording) { keyCode, modifiers in
            isRecording = false
            let updated = ShortcutBinding(keyCode: keyCode, modifiers: modifiers, enabled: binding.enabled)
            onRecord(updated)
        })
    }

    private func label(for b: ShortcutBinding) -> String {
        let mods = NSEvent.ModifierFlags(rawValue: UInt(b.modifiers))
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option)  { parts.append("⌥") }
        if mods.contains(.shift)   { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: b.keyCode))
        return parts.joined()
    }

    private func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 36:  return "↩"
        case 49:  return "Space"
        case 18:  return "1"
        case 19:  return "2"
        case 20:  return "3"
        case 32:  return "U"
        case 34:  return "I"
        case 38:  return "J"
        case 40:  return "K"
        default:
            return NSEvent.keyCodeToString(keyCode: UInt16(keyCode))
        }
    }
}

// MARK: - Key recorder overlay (NSView bridged into SwiftUI)

private struct KeyRecorderOverlay: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (Int, Int) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        KeyCaptureView(onCapture: onCapture)
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        if isActive {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCaptureView: NSView {
    let onCapture: (Int, Int) -> Void

    init(onCapture: @escaping (Int, Int) -> Void) {
        self.onCapture = onCapture
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = Int(event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
        onCapture(Int(event.keyCode), modifiers)
    }
}

// MARK: - Helper extension

private extension NSEvent {
    static func keyCodeToString(keyCode: UInt16) -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        UCKeyTranslate(
            keyboardLayout, keyCode, UInt16(kUCKeyActionDisplay),
            0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState, 4, &length, &chars
        )
        return length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "?"
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -scheme WindowSplitter -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add WindowSplitter/UI/ShortcutRecorderButton.swift
git commit -m "feat: add ShortcutRecorderButton with key capture"
```

---

## Task 7: ShortcutRowView and ConfigPanelView

**Files:**
- Create: `WindowSplitter/UI/ShortcutRowView.swift`
- Create: `WindowSplitter/UI/ConfigPanelView.swift`

- [ ] **Step 1: Create `WindowSplitter/UI/ShortcutRowView.swift`**

```swift
import SwiftUI

/// A single row showing an action's label, shortcut recorder button, and enabled toggle.
/// All mutations go through the `binding` — the caller's setter is responsible for persistence.
struct ShortcutRowView: View {
    let action: WindowAction
    @Binding var binding: ShortcutBinding

    var body: some View {
        HStack {
            Text(action.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderButton(binding: binding) { updated in
                binding = updated
            }

            Toggle("", isOn: Binding(
                get: { binding.enabled },
                set: { newValue in
                    binding = ShortcutBinding(
                        keyCode: binding.keyCode,
                        modifiers: binding.modifiers,
                        enabled: newValue
                    )
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Create `WindowSplitter/UI/ConfigPanelView.swift`**

```swift
import SwiftUI

struct ConfigPanelView: View {
    @State var store: SettingsStore
    let hotkeyManager: GlobalHotkeyManager
    @State private var hasAccessibility = AXIsProcessTrusted()

    private let halves: [WindowAction] = [.leftHalf, .rightHalf, .topHalf, .bottomHalf]
    private let thirds: [WindowAction] = [.leftThird, .centerThird, .rightThird]
    private let quarters: [WindowAction] = [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.split.2x2")
                Text("WindowSplitter")
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    actionGroup(actions: halves)
                    Divider().padding(.vertical, 4)
                    actionGroup(actions: thirds)
                    Divider().padding(.vertical, 4)
                    actionGroup(actions: quarters)
                    Divider().padding(.vertical, 4)
                    actionGroup(actions: [.fullscreen])
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            if !hasAccessibility {
                Divider()
                accessibilityBanner
            }
        }
        .frame(width: 340)
        .onAppear { checkAccessibility() }
    }

    private func actionGroup(actions: [WindowAction]) -> some View {
        ForEach(actions) { action in
            ShortcutRowView(
                action: action,
                binding: Binding(
                    get: { store.bindings[action]! },
                    set: { newBinding in
                        store.save(action: action, binding: newBinding)
                        hotkeyManager.update(bindings: store.enabledBindings)
                    }
                )
            )
        }
    }

    private var accessibilityBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text("Accessibility access required")
                .font(.caption)
            Spacer()
            Button("Enable") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.1))
    }

    private func checkAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
        hotkeyManager.onPermissionGranted = {
            hasAccessibility = true
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild build -scheme WindowSplitter -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add WindowSplitter/UI/ShortcutRowView.swift WindowSplitter/UI/ConfigPanelView.swift
git commit -m "feat: add ConfigPanelView and ShortcutRowView"
```

---

## Task 8: App entry point and MenuBarExtra

**Files:**
- Create: `WindowSplitter/WindowSplitterApp.swift`

- [ ] **Step 1: Create `WindowSplitter/WindowSplitterApp.swift`**

```swift
import SwiftUI

@main
struct WindowSplitterApp: App {
    @State private var store = SettingsStore()
    private let hotkeyManager = GlobalHotkeyManager()
    @State private var isPanelVisible = false

    var body: some Scene {
        MenuBarExtra("WindowSplitter", systemImage: "rectangle.split.2x2") {
            ConfigPanelView(store: store, hotkeyManager: hotkeyManager)
                .onAppear { startHotkeyManager() }
        }
        .menuBarExtraStyle(.window)
    }

    private func startHotkeyManager() {
        hotkeyManager.start(bindings: store.enabledBindings)
        // Register ⌥⇧Space to open/close the menu bar panel
        // (The MenuBarExtra handles click natively; ⌥⇧Space is managed via a
        // separate event monitor that triggers the menu bar icon click.)
        registerToggleShortcut()
    }

    private func registerToggleShortcut() {
        // ⌥⇧Space (keyCode 49) opens the panel by simulating a status item click.
        // We use a global NSEvent monitor here since this is a single fixed shortcut.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isOptionShift = mods == [.option, .shift]
            if isOptionShift && event.keyCode == 49 {
                // Toggle the MenuBarExtra window by sending the status item a click.
                // SwiftUI MenuBarExtra doesn't expose a programmatic open API in macOS 13/14,
                // so we locate and click the status item via NSStatusBar.
                DispatchQueue.main.async { toggleMenuBarPanel() }
            }
        }
    }

    private func toggleMenuBarPanel() {
        // Find the WindowSplitter status item and simulate a left click to toggle the panel.
        guard let statusItem = NSStatusBar.system.statusItems.first(where: {
            $0.button?.window?.title.contains("WindowSplitter") == true
                || $0.button?.accessibilityTitle() == "WindowSplitter"
        }) else { return }
        statusItem.button?.performClick(nil)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -scheme WindowSplitter -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Run all tests one final time**

```bash
xcodebuild test -scheme WindowSplitter -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:|TEST"
```

Expected: all tests PASS, `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add WindowSplitter/WindowSplitterApp.swift
git commit -m "feat: add app entry point with MenuBarExtra and toggle shortcut"
```

---

## Task 9: Manual smoke test

These steps require running the app on a real Mac with a display.

- [ ] **Step 1: Run the app from Xcode**

Open `WindowSplitter.xcodeproj` in Xcode and press `⌘R`. The app should appear in the menu bar with a rectangle icon and no Dock icon.

- [ ] **Step 2: Verify Accessibility banner**

Click the menu bar icon. The ConfigPanel should open. If Accessibility is not yet granted, the yellow banner should appear at the bottom. Click "Enable" and grant access in System Settings.

- [ ] **Step 3: Verify permission auto-activation**

After granting Accessibility without restarting the app, the banner should disappear within 1 second and shortcuts should activate automatically.

- [ ] **Step 4: Test shortcuts**

Focus any window (e.g., Finder). Press `⌥⇧ ←`. The window should snap to the left half of the screen.

Test all 12 shortcuts:
- `⌥⇧←` → left half
- `⌥⇧→` → right half
- `⌥⇧↑` → top half
- `⌥⇧↓` → bottom half
- `⌥⇧1` → left third
- `⌥⇧2` → center third
- `⌥⇧3` → right third
- `⌥⇧U` → top-left quarter
- `⌥⇧I` → top-right quarter
- `⌥⇧J` → bottom-left quarter
- `⌥⇧K` → bottom-right quarter
- `⌥⇧↩` → fullscreen

- [ ] **Step 5: Test toggle and re-bind**

In the ConfigPanel, disable a shortcut with its toggle. Verify the shortcut no longer works. Re-enable it. Verify it works again.

Click a shortcut button, press a new key combination, verify the label updates and the new shortcut works.

- [ ] **Step 6: Verify persistence across relaunches**

Change a shortcut, quit and relaunch the app, verify the changed shortcut is still saved.

- [ ] **Step 7: Final commit**

```bash
git add .
git commit -m "chore: complete WindowSplitter implementation"
```
