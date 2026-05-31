import SwiftUI

struct ConfigPanelView: View {
    @ObservedObject var store: SettingsStore
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
