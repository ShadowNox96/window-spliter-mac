import SwiftUI

/// A single row showing an action's label, shortcut recorder button, and enabled toggle.
/// Recording proposals and enabled toggles take separate persistence paths.
struct ShortcutRowView: View {
    let action: WindowAction
    @Binding var binding: ShortcutBinding
    @Binding var isRecording: Bool
    let onRecord: (ShortcutBinding) -> Void

    var body: some View {
        HStack {
            Text(action.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderButton(binding: binding, isRecording: $isRecording, onRecord: onRecord)

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
            .accessibilityLabel("Enable \(action.title)")
            .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }
}
