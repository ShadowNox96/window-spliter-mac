import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    let store: SettingsStore
    let hotkeyManager: GlobalHotkeyManager
    private(set) var statusItem: NSStatusItem?
    private(set) var panel: NSPanel?
    @Published var recordingAction: WindowAction? {
        didSet {
            hotkeyManager.isRecording = recordingAction != nil
            if oldValue != recordingAction {
                (panel?.firstResponder as? KeyCaptureView)?.cancel()
            }
        }
    }

    override convenience init() {
        self.init(store: SettingsStore(), hotkeyManager: GlobalHotkeyManager())
    }

    init(store: SettingsStore, hotkeyManager: GlobalHotkeyManager) {
        self.store = store
        self.hotkeyManager = hotkeyManager
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "WindowSplitter")
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item

        let panel = ConfigPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 520),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "WindowSplitter"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onHide = { [weak self] in self?.recordingAction = nil }
        panel.contentView = NSHostingView(rootView: ConfigPanelView(appDelegate: self))
        self.panel = panel
        hotkeyManager.onTogglePanel = { [weak self] in self?.togglePanel() }
        hotkeyManager.start(bindings: store.enabledBindings)
    }

    @objc func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let button = statusItem?.button
        let anchor = button.flatMap { $0.window?.convertToScreen($0.convert($0.bounds, to: nil)) }
        let screen = button?.window?.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let point = CGPoint(x: (anchor?.midX ?? visible.midX) - panel.frame.width / 2,
                                y: (anchor?.minY ?? visible.maxY) - panel.frame.height)
            panel.setFrameOrigin(CGPoint(
                x: max(visible.minX, min(point.x, visible.maxX - panel.frame.width)),
                y: max(visible.minY, min(point.y, visible.maxY - panel.frame.height))))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingAction = nil
        hotkeyManager.onTogglePanel = nil
        hotkeyManager.stop()
        panel?.close()
        panel?.delegate = nil
        panel?.contentView = nil
        panel = nil
        if let statusItem {
            statusItem.button?.target = nil
            statusItem.button?.action = nil
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func windowDidResignKey(_ notification: Notification) { recordingAction = nil }
    func windowWillClose(_ notification: Notification) { recordingAction = nil }
}

private final class ConfigPanel: NSPanel {
    var onHide: (() -> Void)?

    override func orderOut(_ sender: Any?) {
        onHide?()
        super.orderOut(sender)
    }
}
