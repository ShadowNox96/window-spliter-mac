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
