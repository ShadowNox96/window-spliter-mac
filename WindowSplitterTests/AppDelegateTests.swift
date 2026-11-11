import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WindowSplitter

final class AppDelegateTests: XCTestCase {
    private var delegate: AppDelegate!
    private var manager: GlobalHotkeyManager!
    private var defaults: UserDefaults!
    private var callback: CGEventTapCallBack?
    private var refcon: UnsafeMutableRawPointer?
    private var trusted = true
    private var enabled = false
    private var tap: CFMachPort?
    private var actions: [WindowAction] = []

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AppDelegateTests")!
        defaults.removePersistentDomain(forName: "AppDelegateTests")
        manager = GlobalHotkeyManager(isTrusted: { self.trusted }, createTap: { callback, refcon in
            self.callback = callback
            self.refcon = refcon
            let tap = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, nil, nil)!
            self.tap = tap
            return tap
        }, enableTap: { _, enabled in self.enabled = enabled }, isTapEnabled: { _ in self.enabled },
           performAction: { self.actions.append($0); return "Injected AX failure" })
        delegate = AppDelegate(store: SettingsStore(defaults: defaults), hotkeyManager: manager)
    }

    override func tearDown() {
        (delegate as NSApplicationDelegate).applicationWillTerminate?(Notification(name: NSApplication.willTerminateNotification))
        manager.stop()
        delegate = nil
        manager = nil
        defaults.removePersistentDomain(forName: "AppDelegateTests")
        super.tearDown()
    }

    func test_launchWiresPanelCallbackAndCreatesOwnedNativePanel() {
        let priorWindows = Set(NSApp.windows.map(\.windowNumber))
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        XCTAssertNotNil(manager.onTogglePanel)
        XCTAssertTrue(manager.isListening)
        XCTAssertEqual(manager.currentBindings.count, WindowAction.allCases.count)
        manager.onTogglePanel?()
        let panels = NSApp.windows.filter { !priorWindows.contains($0.windowNumber) && $0 is NSPanel }
        XCTAssertEqual(panels.count, 1)
        panels.forEach { $0.close() }
    }

    func test_terminationStopsListeningAndClearsCallback() {
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        (delegate as NSApplicationDelegate).applicationWillTerminate?(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertFalse(manager.isListening)
        XCTAssertNil(manager.onTogglePanel)
        XCTAssertFalse(enabled)
        XCTAssertFalse(tap.map(CFMachPortIsValid) ?? true)
    }

    func test_statusClickAndEngineShortcutToggleSameReusableNonactivatingPanel() throws {
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let panel = try XCTUnwrap(delegate.panel)
        let button = try XCTUnwrap(delegate.statusItem?.button)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(button.target === delegate)
        button.performClick(nil)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost)
        let visible = try XCTUnwrap(button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        XCTAssertTrue(visible.contains(panel.frame))
        send(key: 49)
        drain()
        XCTAssertFalse(panel.isVisible)
        send(key: 49)
        drain()
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(delegate.panel === panel)
        panel.performClose(nil)
        XCTAssertFalse(panel.isVisible)
        button.performClick(nil)
        XCTAssertTrue(delegate.panel === panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(actions.isEmpty)
    }

    func test_recordingIsExclusiveAndSuspendsActionsUntilEscape() throws {
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.togglePanel()
        delegate.recordingAction = .leftHalf
        XCTAssertTrue(manager.isRecording)
        send(key: 0)
        drain()
        XCTAssertTrue(actions.isEmpty)
        delegate.recordingAction = .rightHalf
        settle()
        let captures = captureViews(in: try XCTUnwrap(delegate.panel?.contentView))
        let active = try XCTUnwrap(captures.first(where: \.isActive))
        XCTAssertEqual(captures.filter(\.isActive).count, 1)
        active.keyDown(with: localKey(53))
        XCTAssertNil(delegate.recordingAction)
        XCTAssertFalse(manager.isRecording)
        send(key: 0)
        drain()
        XCTAssertEqual(actions, [.leftHalf])
    }

    func test_hideCloseAndFocusLossCancelRecordingAndReleaseResponder() throws {
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let panel = try XCTUnwrap(delegate.panel)
        for end in [0, 1, 2, 3] {
            delegate.togglePanel()
            delegate.recordingAction = .leftHalf
            manager.isRecording = true
            settle()
            switch end {
            case 0: delegate.togglePanel()
            case 1: panel.performClose(nil)
            case 2: panel.resignKey()
            default: panel.orderOut(nil)
            }
            XCTAssertNil(delegate.recordingAction)
            XCTAssertFalse(manager.isRecording)
            XCTAssertFalse(panel.firstResponder is KeyCaptureView)
            panel.orderOut(nil)
        }
    }

    func test_hostedRecordingUsesCurrentEnabledAndUpdatesLatestEngineBindings() throws {
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.togglePanel()
        delegate.recordingAction = .leftHalf
        settle()
        let capture = try XCTUnwrap(captureViews(in: try XCTUnwrap(delegate.panel?.contentView)).first(where: \.isActive))
        var disabled = delegate.store.bindings[.leftHalf]!
        disabled.enabled = false
        delegate.store.save(action: .leftHalf, binding: disabled)
        settle()
        capture.keyDown(with: localKey(99))
        capture.keyDown(with: localKey(98))
        XCTAssertEqual(delegate.store.bindings[.leftHalf]?.keyCode, 99)
        XCTAssertFalse(delegate.store.bindings[.leftHalf]!.enabled)
        XCTAssertNil(manager.currentBindings[.leftHalf])
        XCTAssertNil(delegate.recordingAction)
        XCTAssertFalse(manager.isRecording)
    }

    func test_hostedPanelRedrawsOnAXErrorAndPermissionRevocation() throws {
        trusted = false
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.togglePanel()
        settle()
        let host = try XCTUnwrap(delegate.panel?.contentView)
        trusted = true
        manager.refreshPermission()
        settle()
        let trustedImage = try snapshot(host)
        send(key: 0)
        drain()
        settle()
        let errorImage = try snapshot(host)
        XCTAssertNotEqual(errorImage, trustedImage, "Published AX error must change the rendered panel")
        trusted = false
        manager.refreshPermission()
        settle()
        XCTAssertNotEqual(try snapshot(host), errorImage, "Permission revocation must redraw the banner")
    }

    func test_reRecordingLegacyPlainChordShowsErrorWithoutWritingOrUpdatingEngine() throws {
        defaults.set(99, forKey: "leftHalf.keyCode")
        defaults.set(0, forKey: "leftHalf.modifiers")
        delegate = AppDelegate(store: SettingsStore(defaults: defaults), hotkeyManager: manager)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.togglePanel()
        settle()
        let host = try XCTUnwrap(delegate.panel?.contentView)
        let initial = try snapshot(host)
        delegate.recordingAction = .leftHalf
        settle()
        let capture = try XCTUnwrap(captureViews(in: host).first(where: \.isActive))
        let plain = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                    timestamp: 0, windowNumber: 0, context: nil, characters: "a",
                                    charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 99)!
        capture.keyDown(with: plain)
        settle()
        XCTAssertNotEqual(try snapshot(host), initial, "Even an unchanged legacy chord is a new proposal and must show an error")
        XCTAssertNil(defaults.object(forKey: "leftHalf.enabled"), "Invalid recording must not persist anything")
        XCTAssertEqual(delegate.store.bindings[.leftHalf]?.modifiers, 0)
        XCTAssertEqual(manager.currentBindings[.leftHalf]?.modifiers, 0)
        XCTAssertNil(delegate.recordingAction)
        XCTAssertFalse(manager.isRecording)
    }

    func test_panelShortcutHidesDuringRecordingAndShutdownReleasesNativeObjects() throws {
        weak var releasedDelegate: AppDelegate?
        weak var releasedPanel: NSPanel?
        try autoreleasepool {
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            delegate.togglePanel()
            delegate.recordingAction = .leftHalf
            settle()
            send(key: 49)
            drain()
            XCTAssertFalse(try XCTUnwrap(delegate.panel).isVisible)
            XCTAssertNil(delegate.recordingAction)
            XCTAssertFalse(manager.isRecording)
            releasedDelegate = delegate
            releasedPanel = delegate.panel
            let button = try XCTUnwrap(delegate.statusItem?.button)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            XCTAssertNil(button.target)
            XCTAssertNil(button.action)
            XCTAssertNil(delegate.statusItem)
            XCTAssertNil(delegate.panel)
            delegate = nil
        }
        drain()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(releasedPanel)
        XCTAssertNil(releasedDelegate)
        delegate = AppDelegate(store: SettingsStore(defaults: defaults), hotkeyManager: manager)
    }

    func test_nativePanelDeliversControlOptionAndCommandCombinationsToRecorder() throws {
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.togglePanel()
        let panel = try XCTUnwrap(delegate.panel)
        for flags: NSEvent.ModifierFlags in [.control, .option, .command] {
            delegate.recordingAction = .leftHalf
            settle()
            XCTAssertTrue(panel.firstResponder is KeyCaptureView)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                        characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 99)!
            panel.sendEvent(event)
            XCTAssertNil(delegate.recordingAction)
            XCTAssertEqual(delegate.store.bindings[.leftHalf]?.modifiers, Int(flags.rawValue))
        }
        XCTAssertTrue(actions.isEmpty)
    }

    private func snapshot(_ view: NSView) throws -> Data {
        XCTAssertGreaterThan(view.bounds.height, 0)
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        return try XCTUnwrap(image.tiffRepresentation)
    }

    private func send(key: CGKeyCode) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        event.flags = [.maskAlternate, .maskShift]
        _ = callback?(OpaquePointer(bitPattern: 1)!, .keyDown, event, refcon)
    }

    private func localKey(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control,
                        timestamp: 0, windowNumber: 0, context: nil, characters: "a",
                        charactersIgnoringModifiers: "a", isARepeat: false, keyCode: code)!
    }

    private func captureViews(in view: NSView) -> [KeyCaptureView] {
        (view as? KeyCaptureView).map { [$0] } ?? view.subviews.flatMap { captureViews(in: $0) }
    }

    private func settle() {
        delegate.panel?.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func drain() {
        let drained = expectation(description: "main dispatch")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}
