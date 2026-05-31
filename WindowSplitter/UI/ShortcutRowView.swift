import SwiftUI

/// A single row showing an action's label, shortcut recorder button, and enabled toggle.
/// All mutations go through the `binding` — the caller's setter is responsible for persistence.
struct ShortcutRowView: View {
    let action: WindowAction
    @Binding var binding: ShortcutBinding

    var body: some View {
        HStack {
            Text(action.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderButton(binding: binding) { updated in
                binding = updated
            }

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
            .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }
}
