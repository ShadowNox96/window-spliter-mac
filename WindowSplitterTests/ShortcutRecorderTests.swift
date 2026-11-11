import AppKit
import SwiftUI
import XCTest
@testable import WindowSplitter

final class ShortcutRecorderTests: XCTestCase {
    func test_inactiveCaptureNeverCallsCallback() {
        var captures = 0
        let view = KeyCaptureView { _, _ in captures += 1 }
        view.keyDown(with: key(0))
        view.keyDown(with: key(53))
        XCTAssertEqual(captures, 0)
        XCTAssertFalse(view.acceptsFirstResponder)
    }

    func test_activeCaptureIsOneShotAndNormalizesModifiers() {
        var captures: [(Int, Int)] = []
        let view = KeyCaptureView { captures.append(($0, $1)) }
        view.isActive = true
        view.keyDown(with: key(0, flags: [.option, .shift, .capsLock, .numericPad, .function]))
        view.keyDown(with: key(2))
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures.first?.0, 0)
        XCTAssertEqual(captures.first?.1, Int(NSEvent.ModifierFlags([.option, .shift]).rawValue))
        XCTAssertFalse(view.isActive)
    }

    func test_escapeCancelsWithoutSavingAndLosingFocusDeactivates() {
        var captures = 0
        var cancellations = 0
        let view = KeyCaptureView { _, _ in captures += 1 }
        view.onCancel = { cancellations += 1 }
        view.isActive = true
        view.keyDown(with: key(53))
        XCTAssertEqual(captures, 0)
        XCTAssertFalse(view.isActive)
        XCTAssertEqual(cancellations, 1)
        view.isActive = true
        XCTAssertTrue(view.resignFirstResponder())
        XCTAssertFalse(view.isActive)
        view.cancel()
        XCTAssertEqual(cancellations, 2)
    }

    func test_hostedBridgeUsesFreshCallbackAndReleasesFirstResponderWhenInactive() throws {
        var oldCaptures = 0
        var latestCaptures = 0
        let host = NSHostingView(rootView: KeyRecorderOverlay(isActive: true) { _, _ in oldCaptures += 1 })
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 180, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        settle(host)
        let capture = try XCTUnwrap(captureViews(in: host).first)
        window.makeFirstResponder(capture)
        host.rootView = KeyRecorderOverlay(isActive: true) { _, _ in latestCaptures += 1 }
        settle(host)
        capture.keyDown(with: key(0))
        XCTAssertEqual(oldCaptures, 0)
        XCTAssertEqual(latestCaptures, 1)
        host.rootView = KeyRecorderOverlay(isActive: false) { _, _ in latestCaptures += 1 }
        settle(host)
        XCTAssertFalse(window.firstResponder === capture)
        capture.keyDown(with: key(2))
        XCTAssertEqual(latestCaptures, 1)
    }

    private func captureViews(in view: NSView) -> [KeyCaptureView] {
        (view as? KeyCaptureView).map { [$0] } ?? view.subviews.flatMap { captureViews(in: $0) }
    }

    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [.control]) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                        timestamp: 0, windowNumber: 0, context: nil, characters: "a",
                        charactersIgnoringModifiers: "a", isARepeat: false, keyCode: code)!
    }
}
