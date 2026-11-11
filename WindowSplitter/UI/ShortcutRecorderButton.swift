import SwiftUI
import AppKit
import Carbon

/// A button that displays the current shortcut. When clicked, enters recording mode
/// and captures the next key press + modifiers, then calls `onRecord`.
struct ShortcutRecorderButton: View {
    let binding: ShortcutBinding
    @Binding var isRecording: Bool
    let onRecord: (ShortcutBinding) -> Void

    var body: some View {
        Button(action: { isRecording = true }) {
            Text(isRecording ? "Press keys…" : label(for: binding))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .foregroundColor(isRecording ? .accentColor : .primary)
        .background(KeyRecorderOverlay(isActive: isRecording, onCancel: { isRecording = false }) { keyCode, modifiers in
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
        case 0:   return "A"
        case 1:   return "S"
        case 2:   return "D"
        case 13:  return "W"
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

struct KeyRecorderOverlay: NSViewRepresentable {
    let isActive: Bool
    var onCancel: () -> Void = {}
    let onCapture: (Int, Int) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        KeyCaptureView(onCapture: onCapture)
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        nsView.isActive = isActive
        if isActive {
            nsView.window?.makeFirstResponder(nsView)
        } else if nsView.window?.firstResponder === nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    static func dismantleNSView(_ nsView: KeyCaptureView, coordinator: ()) {
        nsView.cancel()
    }
}

final class KeyCaptureView: NSView {
    var onCapture: (Int, Int) -> Void
    var onCancel: () -> Void = {}
    var isActive = false

    init(onCapture: @escaping (Int, Int) -> Void) {
        self.onCapture = onCapture
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { isActive }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isActive { window?.makeFirstResponder(self) }
    }

    override func keyDown(with event: NSEvent) {
        guard isActive else { return }
        guard event.keyCode != 53 else { cancel(); return }
        isActive = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        let modifiers = Int(event.modifierFlags.intersection([.control, .option, .shift, .command]).rawValue)
        onCapture(Int(event.keyCode), modifiers)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { cancel() }
        return resigned
    }

    func cancel() {
        guard isActive else { return }
        isActive = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        onCancel()
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
