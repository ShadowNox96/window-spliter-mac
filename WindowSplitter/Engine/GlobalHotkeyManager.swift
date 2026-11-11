import AppKit
import Combine

/// Configuration, lifecycle and callbacks use the main run loop.
final class GlobalHotkeyManager: ObservableObject {
    private static let modifierMask = Int(NSEvent.ModifierFlags([.control, .option, .shift, .command]).rawValue)
    @Published private(set) var hasAccessibility = false
    @Published private(set) var isListening = false
    @Published private(set) var listenerError: String?
    @Published private(set) var actionError: String?
    private(set) var currentBindings: [WindowAction: ShortcutBinding] = [:]
    /// T3 sets this on capture start and clears it on completion or cancellation.
    var isRecording = false {
        didSet {
            if isRecording && !oldValue { dispatchGeneration &+= 1 }
        }
    }
    var onTogglePanel: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var started = false
    private var dispatchGeneration = 0
    private let isTrusted: () -> Bool
    private let createTap: (CGEventTapCallBack, UnsafeMutableRawPointer?) -> CFMachPort?
    private let enableTap: (CFMachPort, Bool) -> Void
    private let isTapEnabled: (CFMachPort) -> Bool
    private let performAction: (WindowAction) -> String?

    init(
        isTrusted: @escaping () -> Bool = AXIsProcessTrusted,
        createTap: @escaping (CGEventTapCallBack, UnsafeMutableRawPointer?) -> CFMachPort? = { callback, refcon in
            CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                              options: .defaultTap, eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                              callback: callback, userInfo: refcon)
        },
        enableTap: @escaping (CFMachPort, Bool) -> Void = { CGEvent.tapEnable(tap: $0, enable: $1) },
        isTapEnabled: @escaping (CFMachPort) -> Bool = { CGEvent.tapIsEnabled(tap: $0) },
        performAction: @escaping (WindowAction) -> String? = { WindowController().apply($0) }
    ) {
        self.isTrusted = isTrusted
        self.createTap = createTap
        self.enableTap = enableTap
        self.isTapEnabled = isTapEnabled
        self.performAction = performAction
    }

    // MARK: - Public

    /// Keeps monitoring grants and revocations until stopped.
    func start(bindings: [WindowAction: ShortcutBinding]) {
        started = true
        currentBindings = bindings
        if permissionTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.refreshPermission()
            }
            permissionTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        refreshPermission()
    }

    /// Stores updates even while authorization is absent or the manager is stopped.
    func update(bindings: [WindowAction: ShortcutBinding]) {
        currentBindings = bindings
        refreshPermission()
    }

    func stop() {
        started = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        tearDown()
        isRecording = false
    }

    deinit { stop() }

    func refreshPermission() {
        guard started else { return }
        let trusted = isTrusted()
        if hasAccessibility != trusted { hasAccessibility = trusted }
        if trusted {
            register()
        } else {
            tearDown()
        }
    }

    // MARK: - Private

    private func register() {
        if let tap = eventTap {
            if CFMachPortIsValid(tap) {
                if !isTapEnabled(tap) { enableListener() }
                return
            }
            tearDown()
        }

        eventTap = createTap(
            { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else {
            listenerError = "Cannot create the global shortcut listener. Retrying automatically."
            return
        }
        guard CFMachPortIsValid(tap),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            tearDown()
            listenerError = "Cannot attach the global shortcut listener. Retrying automatically."
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        enableListener()
    }

    private func enableListener() {
        guard let tap = eventTap else { return }
        enableTap(tap, true)
        guard CFMachPortIsValid(tap), isTapEnabled(tap) else {
            tearDown()
            listenerError = "Cannot enable the global shortcut listener. Retrying automatically."
            return
        }
        if listenerError != nil { listenerError = nil }
        if !isListening { isListening = true }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if started {
                if isTrusted() {
                    enableListener()
                } else {
                    refreshPermission()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, started, isListening else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Int(event.flags.rawValue & UInt64(Self.modifierMask))
        let generation = dispatchGeneration

        if keyCode == 49 && modifiers == Int(NSEvent.ModifierFlags([.option, .shift]).rawValue) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.started, self.isListening,
                      self.dispatchGeneration == generation else { return }
                self.onTogglePanel?()
            }
            return nil
        }
        guard !isRecording else { return Unmanaged.passUnretained(event) }

        for (action, binding) in currentBindings where binding.enabled {
            let expected = binding.modifiers & Self.modifierMask
            if binding.keyCode == keyCode && expected == modifiers {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.started, self.isListening, !self.isRecording,
                          self.dispatchGeneration == generation else { return }
                    guard self.isTrusted() else {
                        self.refreshPermission()
                        return
                    }
                    self.actionError = self.performAction(action)
                }
                return nil // consume the event
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func tearDown() {
        // Queued work from a previous listener must not run after a restart.
        dispatchGeneration &+= 1
        if let tap = eventTap {
            enableTap(tap, false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap = eventTap { CFMachPortInvalidate(tap) }
        eventTap = nil
        runLoopSource = nil
        if isListening { isListening = false }
    }
}
