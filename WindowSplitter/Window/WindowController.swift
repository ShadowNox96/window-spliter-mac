import AppKit
import ApplicationServices

final class WindowController {
    private let copyAttribute: (AXUIElement, CFString) -> (AXError, CFTypeRef?)
    private let setAttribute: (AXUIElement, CFString, CFTypeRef) -> AXError

    init(
        copyAttribute: @escaping (AXUIElement, CFString) -> (AXError, CFTypeRef?) = { element, attribute in
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            return (result, value)
        },
        setAttribute: @escaping (AXUIElement, CFString, CFTypeRef) -> AXError = AXUIElementSetAttributeValue
    ) {
        self.copyAttribute = copyAttribute
        self.setAttribute = setAttribute
    }

    /// Returns nil on success, or a message suitable for the configuration panel.
    @discardableResult
    func apply(_ action: WindowAction) -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return "No frontmost application available."
        }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        return apply(action, to: appElement,
                     screens: NSScreen.screens.map { (frame: $0.frame, visibleFrame: $0.visibleFrame) })
    }

    /// The same reflection converts in either direction; X and size are unchanged.
    static func flippedFrame(_ frame: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenFrame.maxY - frame.maxY,
               width: frame.width, height: frame.height)
    }

    static func screenIndex(for frame: CGRect, screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        var selected = 0
        var largestArea: CGFloat = 0
        for (index, screenFrame) in screenFrames.enumerated() {
            let overlap = frame.intersection(screenFrame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > largestArea {
                selected = index
                largestArea = area
            }
        }
        return selected
    }

    func apply(_ action: WindowAction, to appElement: AXUIElement,
               screens: [(frame: CGRect, visibleFrame: CGRect)]) -> String? {
        guard let primary = screens.first else { return "No screen available." }
        let (windowResult, windowRef) = copyAttribute(appElement, kAXFocusedWindowAttribute as CFString)
        guard windowResult == .success else {
            return "Cannot read \(kAXFocusedWindowAttribute) (AX error \(windowResult.rawValue))."
        }
        guard let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            return "Invalid \(kAXFocusedWindowAttribute) value."
        }
        let window = windowRef as! AXUIElement

        let (positionResult, positionRef) = copyAttribute(window, kAXPositionAttribute as CFString)
        guard positionResult == .success else {
            return "Cannot read \(kAXPositionAttribute) (AX error \(positionResult.rawValue))."
        }
        guard let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID() else {
            return "Invalid \(kAXPositionAttribute) value."
        }
        let positionValue = positionRef as! AXValue
        var position = CGPoint.zero
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetValue(positionValue, .cgPoint, &position) else {
            return "Invalid \(kAXPositionAttribute) value."
        }

        let (sizeResult, sizeRef) = copyAttribute(window, kAXSizeAttribute as CFString)
        guard sizeResult == .success else {
            return "Cannot read \(kAXSizeAttribute) (AX error \(sizeResult.rawValue))."
        }
        guard let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return "Invalid \(kAXSizeAttribute) value."
        }
        let sizeValue = sizeRef as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return "Invalid \(kAXSizeAttribute) value."
        }
        guard position.x.isFinite, position.y.isFinite,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return "Invalid window frame."
        }

        let windowFrame = Self.flippedFrame(CGRect(origin: position, size: size),
                                           primaryScreenFrame: primary.frame)
        guard let index = Self.screenIndex(for: windowFrame, screenFrames: screens.map(\.frame)) else {
            return "No screen available."
        }
        let target = Self.flippedFrame(action.frame(in: screens[index].visibleFrame),
                                       primaryScreenFrame: primary.frame)
        position = target.origin
        size = target.size
        guard let targetPosition = AXValueCreate(.cgPoint, &position),
              let targetSize = AXValueCreate(.cgSize, &size) else {
            return "Cannot create AX frame values."
        }
        // Shrink before moving so the old size cannot clamp the target position.
        let resizeResult = setAttribute(window, kAXSizeAttribute as CFString, targetSize)
        guard resizeResult == .success else {
            return "Cannot set \(kAXSizeAttribute) (AX error \(resizeResult.rawValue))."
        }
        let moveResult = setAttribute(window, kAXPositionAttribute as CFString, targetPosition)
        guard moveResult == .success else {
            return "Cannot set \(kAXPositionAttribute) (AX error \(moveResult.rawValue))."
        }
        return nil
    }
}
