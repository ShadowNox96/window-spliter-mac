import AppKit
import Combine
import XCTest
@testable import WindowSplitter

final class GlobalHotkeyManagerTests: XCTestCase {
    private var trusted = true
    private var creationFails = false
    private var enableFails = false
    private var enabled = false
    private var creations = 0
    private var enableCalls: [Bool] = []
    private var taps: [CFMachPort] = []
    private var callback: CGEventTapCallBack?
    private var refcon: UnsafeMutableRawPointer?
    private var actions: [WindowAction] = []
    private var actionError: String?
    private var manager: GlobalHotkeyManager!
    private let mods = Int(NSEvent.ModifierFlags([.option, .shift]).rawValue)

    override func setUp() {
        super.setUp()
        manager = makeManager()
    }

    override func tearDown() {
        manager?.stop()
        manager = nil
        taps.forEach { CFMachPortInvalidate($0) }
        callback = nil
        refcon = nil
        super.tearDown()
    }

    func test_latestBindingsSurviveUpdatesBeforePermissionGrant() {
        trusted = false
        manager.start(bindings: binding(key: 0))
        manager.update(bindings: binding(key: 2))
        XCTAssertEqual(manager.currentBindings[.leftHalf]?.keyCode, 2)
        trusted = true
        manager.refreshPermission()
        XCTAssertNil(send(key: 2))
        assertPassThrough(key: 0)
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf])
    }

    func test_repeatedStartWhilePendingUsesLatestBindingsAndOnePoller() {
        trusted = false
        manager.start(bindings: binding(key: 0))
        manager.start(bindings: binding(key: 2))
        trusted = true
        let granted = expectation(description: "real repeating timer grants permission")
        granted.assertForOverFulfill = false
        let observation = manager.$hasAccessibility.dropFirst().filter { $0 }.sink { _ in granted.fulfill() }
        wait(for: [granted], timeout: 2.5)
        withExtendedLifetime(observation) {}
        XCTAssertEqual(creations, 1)
        XCTAssertNil(send(key: 2))
        assertPassThrough(key: 0)
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf])
    }

    func test_updateAndRepeatedStartDoNotRecreateHealthyTap() {
        manager.start(bindings: binding(key: 0))
        manager.update(bindings: binding(key: 2))
        manager.start(bindings: binding(key: 2))
        XCTAssertEqual(creations, 1)
        XCTAssertNil(send(key: 2))
        assertPassThrough(key: 0)
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf])
    }

    func test_disabledBindingsPassThroughAndNeverDispatch() {
        manager.start(bindings: binding(key: 0, enabled: false))
        assertPassThrough(key: 0)
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
    }

    func test_recordingSuspendsWindowActionsAndCancellationRestoresThem() {
        manager.start(bindings: binding(key: 0))
        manager.isRecording = true
        assertPassThrough(key: 0)
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
        manager.isRecording = false
        XCTAssertNil(send(key: 0))
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf])
        XCTAssertEqual(creations, 1)
    }

    func test_queuedActionDoesNotRunAfterRecordingStartsOrStop() {
        manager.start(bindings: binding(key: 0))
        XCTAssertNil(send(key: 0))
        manager.isRecording = true
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
        manager.isRecording = false
        XCTAssertNil(send(key: 0))
        manager.stop()
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
    }

    func test_panelShortcutIsFixedReservedAndDispatchedAsynchronouslyDuringRecording() {
        manager.start(bindings: binding(key: 49))
        manager.isRecording = true
        var toggles = 0
        manager.onTogglePanel = { toggles += 1 }
        XCTAssertNil(send(key: 49))
        XCTAssertEqual(toggles, 0)
        drainMainQueue()
        XCTAssertEqual(toggles, 1)
        XCTAssertTrue(actions.isEmpty)
        manager.isRecording = false
        XCTAssertNil(send(key: 49))
        drainMainQueue()
        XCTAssertEqual(toggles, 2)
        XCTAssertTrue(actions.isEmpty)
        assertPassThrough(key: 49, flags: .maskAlternate)
        assertPassThrough(key: 49, flags: [.maskAlternate, .maskShift, .maskCommand])
    }

    func test_queuedActionStaysCancelledAfterRecordingEndsBeforeDispatch() {
        manager.start(bindings: binding(key: 0))
        XCTAssertNil(send(key: 0))
        manager.isRecording = true
        manager.isRecording = false
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
        XCTAssertNil(send(key: 0))
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf])
    }

    func test_stopAndRestartCancelOldQueuedActionAndPanelCallbacks() {
        manager.start(bindings: binding(key: 0))
        var toggles = 0
        manager.onTogglePanel = { toggles += 1 }
        XCTAssertNil(send(key: 0))
        XCTAssertNil(send(key: 49))
        manager.stop()
        manager.start(bindings: binding(key: 0))
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(toggles, 0)
    }

    func test_permissionRevokedBeforeDispatchPreventsAXActionWithoutWaitingForTimer() {
        manager.start(bindings: binding(key: 0))
        XCTAssertNil(send(key: 0))
        trusted = false
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
        XCTAssertFalse(manager.hasAccessibility)
        XCTAssertFalse(manager.isListening)
    }

    func test_incidentalModifiersAreIgnoredInEventAndPersistedBinding() {
        let incidental: CGEventFlags = [.maskAlphaShift, .maskNumericPad, .maskSecondaryFn]
        manager.start(bindings: [.leftHalf: ShortcutBinding(
            keyCode: 0, modifiers: mods | Int(incidental.rawValue), enabled: true)])
        XCTAssertNil(send(key: 0))
        XCTAssertNil(send(key: 0, flags: [.maskAlternate, .maskShift, incidental]))
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf, .leftHalf])
    }

    func test_allFourMeaningfulModifiersMustMatchWithoutRevalidatingPersistedBindings() {
        let flags: [CGEventFlags] = [.maskControl, .maskAlternate, .maskShift, .maskCommand, []]
        for flag in flags {
            manager.update(bindings: [.leftHalf: ShortcutBinding(
                keyCode: 0, modifiers: Int(flag.rawValue), enabled: true)])
            manager.start(bindings: manager.currentBindings)
            XCTAssertNil(send(key: 0, flags: flag))
            assertPassThrough(key: 0, flags: flag.symmetricDifference(.maskCommand))
        }
        drainMainQueue()
        XCTAssertEqual(actions, Array(repeating: .leftHalf, count: flags.count))
    }

    func test_unmatchedAndNonKeyEventsReturnOriginalWithoutExtraOwnership() {
        manager.start(bindings: binding(key: 0))
        assertPassThrough(key: 2)
        assertPassThrough(key: 0, type: .keyUp)
        weak var borrowed: CGEvent?
        autoreleasepool {
            let event = makeEvent(key: 2)
            borrowed = event
            XCTAssertTrue(invoke(event: event)?.takeUnretainedValue() === event)
        }
        XCTAssertNil(borrowed, "Pass-through must not retain the incoming event")
    }

    func test_nilRefconReturnsBorrowedOriginal() {
        manager.start(bindings: binding(key: 0))
        weak var borrowed: CGEvent?
        autoreleasepool {
            let event = makeEvent(key: 2)
            borrowed = event
            let result = callback?(OpaquePointer(bitPattern: 1)!, .keyDown, event, nil)
            XCTAssertTrue(result?.takeUnretainedValue() === event)
        }
        XCTAssertNil(borrowed)
    }

    func test_permissionRevocationTearsDownAndRegrantUsesLatestBindings() {
        manager.start(bindings: binding(key: 0))
        let firstTap = taps[0]
        trusted = false
        manager.refreshPermission()
        XCTAssertFalse(manager.hasAccessibility)
        XCTAssertFalse(manager.isListening)
        XCTAssertFalse(CFMachPortIsValid(firstTap))
        manager.update(bindings: binding(key: 2))
        trusted = true
        manager.refreshPermission()
        XCTAssertTrue(manager.hasAccessibility)
        XCTAssertTrue(manager.isListening)
        XCTAssertEqual(creations, 2)
        XCTAssertNil(send(key: 2))
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf])
    }

    func test_repeatingMonitorContinuesAfterInitialGrantAndDetectsRevocation() {
        manager.start(bindings: binding(key: 0))
        trusted = false
        let revoked = expectation(description: "monitor detects permission revocation")
        let observation = manager.$hasAccessibility.dropFirst().filter { !$0 }.sink { _ in revoked.fulfill() }
        wait(for: [revoked], timeout: 2.5)
        withExtendedLifetime(observation) {}
        XCTAssertFalse(manager.isListening)
        XCTAssertFalse(CFMachPortIsValid(taps[0]))
    }

    func test_tapCreationFailureIsObservableAndRetryable() {
        creationFails = true
        var errors: [String?] = []
        let observation = manager.$listenerError.sink { errors.append($0) }
        manager.start(bindings: binding(key: 0))
        XCTAssertTrue(manager.hasAccessibility)
        XCTAssertFalse(manager.isListening)
        XCTAssertNotNil(manager.listenerError)
        XCTAssertNotNil(errors.last!)
        creationFails = false
        manager.refreshPermission()
        XCTAssertTrue(manager.isListening)
        XCTAssertNil(manager.listenerError)
        XCTAssertEqual(creations, 2)
        withExtendedLifetime(observation) {}
    }

    func test_disabledNotificationsReenableTapWithoutDispatchingKeyAction() {
        manager.start(bindings: binding(key: 0))
        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            enabled = false
            let event = makeEvent(key: 0)
            XCTAssertTrue(invoke(event: event, type: type)?.takeUnretainedValue() === event)
            XCTAssertTrue(enabled)
            XCTAssertTrue(manager.isListening)
        }
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(enableCalls, [true, true, true])
    }

    func test_failedEnableAndRecoveryPublishFailureAndRetryWithLatestBindings() {
        enableFails = true
        manager.start(bindings: binding(key: 0))
        XCTAssertFalse(manager.isListening)
        XCTAssertNotNil(manager.listenerError)
        XCTAssertFalse(CFMachPortIsValid(taps[0]))
        enableFails = false
        manager.update(bindings: binding(key: 2))
        XCTAssertTrue(manager.isListening)
        XCTAssertEqual(creations, 2)
        enabled = false
        enableFails = true
        _ = send(key: 2, type: .tapDisabledByTimeout)
        XCTAssertFalse(manager.isListening)
        XCTAssertNotNil(manager.listenerError)
        XCTAssertFalse(CFMachPortIsValid(taps.last!))
        enableFails = false
        manager.refreshPermission()
        XCTAssertTrue(manager.isListening)
        XCTAssertNil(manager.listenerError)
        XCTAssertNil(send(key: 2))
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf])
    }

    func test_permissionLossDuringDisabledNotificationDoesNotReenable() {
        manager.start(bindings: binding(key: 0))
        trusted = false
        _ = send(key: 0, type: .tapDisabledByUserInput)
        XCTAssertFalse(manager.hasAccessibility)
        XCTAssertFalse(manager.isListening)
        XCTAssertEqual(enableCalls, [true, false])
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
    }

    func test_axErrorIsPublishedOnMainAndClearedByNextSuccess() {
        manager.start(bindings: binding(key: 0))
        actionError = "Cannot set AXSize (AX error -25204)."
        var errors: [String?] = []
        let observation = manager.$actionError.sink { errors.append($0) }
        XCTAssertNil(send(key: 0))
        XCTAssertTrue(actions.isEmpty)
        drainMainQueue()
        XCTAssertEqual(manager.actionError, actionError)
        XCTAssertEqual(errors.last!, actionError)
        actionError = nil
        XCTAssertNil(send(key: 0))
        drainMainQueue()
        XCTAssertNil(manager.actionError)
        XCTAssertEqual(actions, [.leftHalf, .leftHalf])
        withExtendedLifetime(observation) {}
    }

    func test_stopIsIdempotentPreventsPollingAndAllowsExplicitRestart() {
        manager.start(bindings: binding(key: 0))
        manager.isRecording = true
        manager.stop()
        manager.stop()
        manager.refreshPermission()
        manager.update(bindings: binding(key: 2))
        XCTAssertEqual(creations, 1)
        XCTAssertFalse(manager.isListening)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(CFMachPortIsValid(taps[0]))
        XCTAssertEqual(enableCalls, [true, false])
        manager.start(bindings: manager.currentBindings)
        XCTAssertEqual(creations, 2)
        XCTAssertNil(send(key: 2))
        drainMainQueue()
        XCTAssertEqual(actions, [.leftHalf])
    }

    func test_deinitInvalidatesTapAndTimerAndQueuedClosuresDoNotRetainManager() {
        manager.start(bindings: binding(key: 0))
        XCTAssertNil(send(key: 0))
        weak var released: GlobalHotkeyManager?
        released = manager
        manager = nil
        XCTAssertNil(released)
        XCTAssertFalse(CFMachPortIsValid(taps[0]))
        drainMainQueue()
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(enableCalls, [true, false])
    }

    private func makeManager() -> GlobalHotkeyManager {
        GlobalHotkeyManager(isTrusted: { self.trusted }, createTap: { callback, refcon in
            self.creations += 1
            self.callback = callback
            self.refcon = refcon
            guard !self.creationFails else { return nil }
            // A local Mach port, never an input event tap and never a TCC request.
            let tap = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, nil, nil)!
            self.taps.append(tap)
            return tap
        }, enableTap: { _, value in
            self.enableCalls.append(value)
            self.enabled = value && !self.enableFails
        }, isTapEnabled: { _ in self.enabled }, performAction: { action in
            XCTAssertTrue(Thread.isMainThread)
            self.actions.append(action)
            return self.actionError
        })
    }

    private func binding(key: Int, enabled: Bool = true) -> [WindowAction: ShortcutBinding] {
        [.leftHalf: ShortcutBinding(keyCode: key, modifiers: mods, enabled: enabled)]
    }

    private func makeEvent(key: Int, flags: CGEventFlags = [.maskAlternate, .maskShift]) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true)!
        event.flags = flags
        return event
    }

    private func invoke(event: CGEvent, type: CGEventType = .keyDown) -> Unmanaged<CGEvent>? {
        XCTAssertNotNil(callback, "Engine must create a listener before accepting input")
        return callback?(OpaquePointer(bitPattern: 1)!, type, event, refcon)
    }

    private func send(key: Int, flags: CGEventFlags = [.maskAlternate, .maskShift],
                      type: CGEventType = .keyDown) -> Unmanaged<CGEvent>? {
        invoke(event: makeEvent(key: key, flags: flags), type: type)
    }

    private func assertPassThrough(key: Int, flags: CGEventFlags = [.maskAlternate, .maskShift],
                                   type: CGEventType = .keyDown,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let event = makeEvent(key: key, flags: flags)
        XCTAssertTrue(invoke(event: event, type: type)?.takeUnretainedValue() === event,
                      "Expected original borrowed event", file: file, line: line)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue dispatched")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}
