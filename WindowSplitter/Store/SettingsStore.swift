import Foundation
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

    func save(action: WindowAction, binding: ShortcutBinding) {
        bindings[action] = binding
        defaults.set(binding.keyCode, forKey: keyCodeKey(action))
        defaults.set(binding.modifiers, forKey: modifiersKey(action))
        defaults.set(binding.enabled, forKey: enabledKey(action))
    }

    var enabledBindings: [WindowAction: ShortcutBinding] {
        bindings.filter { $0.value.enabled }
    }

    private func keyCodeKey(_ action: WindowAction) -> String { "\(action.rawValue).keyCode" }
    private func modifiersKey(_ action: WindowAction) -> String { "\(action.rawValue).modifiers" }
    private func enabledKey(_ action: WindowAction) -> String { "\(action.rawValue).enabled" }
}
