import SwiftUI

@main
struct WindowSplitterApp: App {
    @StateObject private var store = SettingsStore()
    private let hotkeyManager = GlobalHotkeyManager()

    var body: some Scene {
        MenuBarExtra("WindowSplitter", systemImage: "rectangle.split.2x2") {
            ConfigPanelView(store: store, hotkeyManager: hotkeyManager)
                .onAppear { startHotkeyManager() }
        }
        .menuBarExtraStyle(.window)
    }

    private func startHotkeyManager() {
        hotkeyManager.start(bindings: store.enabledBindings)
        registerToggleShortcut()
    }

    private func registerToggleShortcut() {
        // ⌥⇧Space (keyCode 49) opens the panel by simulating a status item click.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isOptionShift = mods == [.option, .shift]
            if isOptionShift && event.keyCode == 49 {
                DispatchQueue.main.async { self.toggleMenuBarPanel() }
            }
        }
    }

    private func toggleMenuBarPanel() {
        guard let statusItem = NSStatusBar.system.statusItems.first(where: {
            $0.button?.window?.title.contains("WindowSplitter") == true
                || $0.button?.accessibilityTitle() == "WindowSplitter"
        }) else { return }
        statusItem.button?.performClick(nil)
    }
}
