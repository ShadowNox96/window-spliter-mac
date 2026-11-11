import SwiftUI

struct ConfigPanelView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var hotkeyManager: GlobalHotkeyManager
    @ObservedObject var appDelegate: AppDelegate
    @State private var shortcutError: String?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.store = appDelegate.store
        self.hotkeyManager = appDelegate.hotkeyManager
    }

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

            if let shortcutError {
                Text(shortcutError).foregroundColor(.red).font(.caption).padding(12)
            }
            if let error = hotkeyManager.listenerError {
                Text(error).foregroundColor(.red).font(.caption).padding(12)
                Button("Retry Listener") { hotkeyManager.refreshPermission() }.padding(.horizontal, 12)
            }
            if let error = hotkeyManager.actionError {
                Text(error).foregroundColor(.red).font(.caption).padding(12)
            }
            if !hotkeyManager.hasAccessibility {
                Divider()
                accessibilityBanner
            }
            Divider()
            HStack {
                Text("Option+Shift+Space: toggle panel").font(.caption)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }.padding(12)
        }
        .frame(width: 340)
    }

    private func actionGroup(actions: [WindowAction]) -> some View {
        ForEach(actions) { action in
            ShortcutRowView(
                action: action,
                binding: Binding(
                    get: { store.bindings[action]! },
                    set: { newBinding in
                        save(newBinding, for: action)
                    }
                ),
                isRecording: Binding(
                    get: { appDelegate.recordingAction == action },
                    set: { active in
                        if active { appDelegate.recordingAction = action }
                        else if appDelegate.recordingAction == action { appDelegate.recordingAction = nil }
                    }
                ),
                onRecord: { save($0, for: action, recording: true) }
            )
        }
    }

    private func save(_ binding: ShortcutBinding, for action: WindowAction, recording: Bool = false) {
        shortcutError = store.save(action: action, binding: binding, recording: recording)
        if shortcutError == nil { hotkeyManager.update(bindings: store.enabledBindings) }
    }

    private var accessibilityBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text("Accessibility access required")
                .font(.caption)
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.1))
    }
}
