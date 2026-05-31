import AppKit
import ApplicationServices

final class WindowController {

    /// Applies `action` to the currently focused window.
    func apply(_ action: WindowAction) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )
        guard result == .success, let ref = focusedWindowRef else { return }
        let window = ref as! AXUIElement

        guard let screen = screen(for: window) else { return }
        let targetFrame = action.frame(in: screen.visibleFrame)
        setFrame(targetFrame, on: window, screen: screen)
    }

    // MARK: - Private

    private func screen(for window: AXUIElement) -> NSScreen? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              let posVal = posRef else { return NSScreen.main }
        var point = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func setFrame(_ frame: CGRect, on window: AXUIElement, screen: NSScreen) {
        // AX coordinate system has origin at top-left of the primary screen.
        // Convert AppKit (bottom-left origin) to AX (top-left origin).
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let axY = primaryScreenHeight - frame.maxY

        var position = CGPoint(x: frame.minX, y: axY)
        var size = CGSize(width: frame.width, height: frame.height)

        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }
}
