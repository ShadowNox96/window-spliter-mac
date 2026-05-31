import SwiftUI
import AppKit

/// A button that displays the current shortcut. When clicked, enters recording mode
/// and captures the next key press + modifiers, then calls `onRecord`.
struct ShortcutRecorderButton: View {
    let binding: ShortcutBinding
    let onRecord: (ShortcutBinding) -> Void

    @State private var isRecording = false

    var body: some View {
        Button(action: { isRecording = true }) {
            Text(isRecording ? "Press keys…" : label(for: binding))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .foregroundColor(isRecording ? .accentColor : .primary)
        .background(KeyRecorderOverlay(isActive: isRecording) { keyCode, modifiers in
            isRecording = false
            let updated = ShortcutBinding(keyCode: keyCode, modifiers: modifiers, enabled: binding.enabled)
            onRecord(updated)
        })
    }

    private func label(for b: ShortcutBinding) -> String {
        let mods = NSEvent.ModifierFlags(rawValue: UInt(b.modifiers))
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option)  { parts.append("⌥") }
        if mods.contains(.shift)   { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: b.keyCode))
        return parts.joined()
    }

    private func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 36:  return "↩"
        case 49:  return "Space"
        case 18:  return "1"
        case 19:  return "2"
        case 20:  return "3"
        case 32:  return "U"
        case 34:  return "I"
        case 38:  return "J"
        case 40:  return "K"
        default:
            return NSEvent.keyCodeToString(keyCode: UInt16(keyCode))
        }
    }
}

// MARK: - Key recorder overlay (NSView bridged into SwiftUI)

private struct KeyRecorderOverlay: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (Int, Int) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        KeyCaptureView(onCapture: onCapture)
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        if isActive {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCaptureView: NSView {
    let onCapture: (Int, Int) -> Void

    init(onCapture: @escaping (Int, Int) -> Void) {
        self.onCapture = onCapture
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = Int(event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
        onCapture(Int(event.keyCode), modifiers)
    }
}

// MARK: - Helper extension

private extension NSEvent {
    static func keyCodeToString(keyCode: UInt16) -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        UCKeyTranslate(
            keyboardLayout, keyCode, UInt16(kUCKeyActionDisplay),
            0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState, 4, &length, &chars
        )
        return length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "?"
    }
}
