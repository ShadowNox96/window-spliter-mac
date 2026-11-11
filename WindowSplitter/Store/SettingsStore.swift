import AppKit
import Combine

struct ShortcutBinding {
    var keyCode: Int
    var modifiers: Int
    var enabled: Bool
}

final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    @Published var bindings: [WindowAction: ShortcutBinding] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in WindowAction.allCases {
            bindings[action] = ShortcutBinding(
                keyCode: defaults.object(forKey: keyCodeKey(action)) as? Int ?? action.defaultKeyCode,
                modifiers: defaults.object(forKey: modifiersKey(action)) as? Int ?? action.defaultModifiers,
                enabled: defaults.object(forKey: enabledKey(action)) as? Bool ?? true
            )
        }
    }

    @discardableResult
    /// Toggles preserve legacy chords; recording always validates, even an unchanged chord.
    func save(action: WindowAction, binding proposal: ShortcutBinding, recording: Bool = false) -> String? {
        var binding = proposal
        if let current = bindings[action],
           recording || current.keyCode != binding.keyCode || current.modifiers != binding.modifiers {
            let mask = Int(NSEvent.ModifierFlags([.control, .option, .command, .shift]).rawValue)
            binding.modifiers &= mask
            guard binding.modifiers & Int(NSEvent.ModifierFlags([.control, .option, .command]).rawValue) != 0 else {
                return "Use Control, Option or Command in a new shortcut."
            }
            guard binding.keyCode != 49 || binding.modifiers != Int(NSEvent.ModifierFlags([.option, .shift]).rawValue) else {
                return "Option+Shift+Space is reserved for the panel."
            }
            guard !bindings.contains(where: { other, saved in
                other != action && saved.keyCode == binding.keyCode && saved.modifiers & mask == binding.modifiers
            }) else {
                return "That shortcut is already assigned to another action."
            }
            binding.enabled = current.enabled
        }
        bindings[action] = binding
        defaults.set(binding.keyCode, forKey: keyCodeKey(action))
        defaults.set(binding.modifiers, forKey: modifiersKey(action))
        defaults.set(binding.enabled, forKey: enabledKey(action))
        return nil
    }

    var enabledBindings: [WindowAction: ShortcutBinding] {
        bindings.filter { $0.value.enabled }
    }

    private func keyCodeKey(_ action: WindowAction) -> String { "\(action.rawValue).keyCode" }
    private func modifiersKey(_ action: WindowAction) -> String { "\(action.rawValue).modifiers" }
    private func enabledKey(_ action: WindowAction) -> String { "\(action.rawValue).enabled" }
}
