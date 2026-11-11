import AppKit
import ApplicationServices
import XCTest
@testable import WindowSplitter

final class WindowControllerTests: XCTestCase {
    private let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let app = AXUIElementCreateApplication(0)
    private let window = AXUIElementCreateApplication(1)

    func test_coordinateConversionAcrossScreenArrangements() {
        let pairs: [(CGRect, CGRect)] = [
            (CGRect(x: 100, y: 80, width: 600, height: 400),
             CGRect(x: 100, y: 600, width: 600, height: 400)),
            (CGRect(x: 100, y: -700, width: 600, height: 400),
             CGRect(x: 100, y: 1380, width: 600, height: 400)),
            (CGRect(x: 100, y: 1200, width: 600, height: 400),
             CGRect(x: 100, y: -520, width: 600, height: 400)),
            (CGRect(x: -1200, y: 100, width: 600, height: 400),
             CGRect(x: -1200, y: 580, width: 600, height: 400))
        ]
        for (ax, appKit) in pairs {
            XCTAssertEqual(WindowController.flippedFrame(ax, primaryScreenFrame: primary), appKit)
            XCTAssertEqual(WindowController.flippedFrame(appKit, primaryScreenFrame: primary), ax)
        }
    }

    func test_conversionUsesPrimaryScreenTopNotDesktopUnionOrHeight() {
        let shiftedPrimary = CGRect(x: 0, y: 100, width: 1920, height: 1080)
        XCTAssertEqual(
            WindowController.flippedFrame(CGRect(x: -600, y: 200, width: 400, height: 300),
                                          primaryScreenFrame: shiftedPrimary),
            CGRect(x: -600, y: 680, width: 400, height: 300)
        )
    }

    func test_screenSelectionUsesLargestOverlapNotOrigin() {
        let right = CGRect(x: 1920, y: 0, width: 1280, height: 1080)
        XCTAssertEqual(WindowController.screenIndex(
            for: CGRect(x: 1800, y: 200, width: 800, height: 500),
            screenFrames: [primary, right]), 1)
    }

    func test_screenSelectionAllowsOriginOutsideAllScreens() {
        XCTAssertEqual(WindowController.screenIndex(
            for: CGRect(x: -100, y: 800, width: 500, height: 400),
            screenFrames: [CGRect(x: -1280, y: 0, width: 1280, height: 720), primary]), 1)
    }

    func test_screenSelectionHandlesAboveBelowAndNegativeX() {
        let frames = [primary,
                      CGRect(x: 0, y: 1080, width: 1920, height: 1080),
                      CGRect(x: 0, y: -1080, width: 1920, height: 1080),
                      CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        let axFrames = [CGRect(x: 100, y: -700, width: 600, height: 400),
                        CGRect(x: 100, y: 1200, width: 600, height: 400),
                        CGRect(x: -1200, y: 100, width: 600, height: 400)]
        for (index, frame) in axFrames.enumerated() {
            XCTAssertEqual(WindowController.screenIndex(
                for: WindowController.flippedFrame(frame, primaryScreenFrame: primary),
                screenFrames: frames), index + 1)
        }
    }

    func test_screenSelectionFallbackAndTiesAreDeterministic() {
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        XCTAssertNil(WindowController.screenIndex(for: primary, screenFrames: []))
        XCTAssertEqual(WindowController.screenIndex(
            for: CGRect(x: 8000, y: 8000, width: 100, height: 100),
            screenFrames: [primary, right]), 0)
        XCTAssertEqual(WindowController.screenIndex(
            for: CGRect(x: 1820, y: 100, width: 200, height: 100),
            screenFrames: [primary, right]), 0)
    }

    func test_applyUsesOverlapVisibleFrameAndResizesBeforePositionToAvoidClamping() {
        var currentSize = CGSize(width: 2400, height: 1400)
        var actualPosition = CGPoint.zero
        var attributes: [String] = []
        let controller = makeController(size: currentSize, set: { _, attribute, value in
            attributes.append(attribute as String)
            let axValue = value as! AXValue
            if attribute as String == kAXSizeAttribute {
                XCTAssertTrue(AXValueGetValue(axValue, .cgSize, &currentSize))
            } else {
                var requested = CGPoint.zero
                XCTAssertTrue(AXValueGetValue(axValue, .cgPoint, &requested))
                // Simulate a window server that clamps position using the current size.
                actualPosition = CGPoint(x: min(requested.x, 3200 - currentSize.width),
                                         y: min(requested.y, 1080 - currentSize.height))
            }
            return .success
        })
        let right = CGRect(x: 1920, y: 0, width: 1280, height: 1080)
        let visible = CGRect(x: 1940, y: 40, width: 1240, height: 1000)
        XCTAssertNil(controller.apply(.bottomRightQuarter, to: app,
                                      screens: [(primary, primary), (right, visible)]))
        XCTAssertEqual(attributes, [kAXSizeAttribute, kAXPositionAttribute])
        XCTAssertEqual(currentSize, CGSize(width: 620, height: 500))
        XCTAssertEqual(actualPosition, CGPoint(x: 2560, y: 540))
    }

    func test_applyConvertsInputAndOutputForAboveBelowAndLeftScreens() {
        let screens = [(primary, primary),
                       (CGRect(x: 0, y: 1080, width: 1920, height: 1080),
                        CGRect(x: 0, y: 1103, width: 1920, height: 1030)),
                       (CGRect(x: 0, y: -1080, width: 1920, height: 1080),
                        CGRect(x: 0, y: -1040, width: 1920, height: 1000)),
                       (CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                        CGRect(x: -1900, y: 40, width: 1880, height: 1000))]
        let cases: [(CGPoint, CGPoint, CGSize)] = [
            (CGPoint(x: 100, y: -700), CGPoint(x: 0, y: -1053), CGSize(width: 1920, height: 1030)),
            (CGPoint(x: 100, y: 1200), CGPoint(x: 0, y: 1120), CGSize(width: 1920, height: 1000)),
            (CGPoint(x: -1200, y: 100), CGPoint(x: -1900, y: 40), CGSize(width: 1880, height: 1000))
        ]
        for (position, expectedPosition, expectedSize) in cases {
            var writtenPosition = CGPoint.zero
            var writtenSize = CGSize.zero
            let controller = makeController(position: position, set: { _, attribute, value in
                let axValue = value as! AXValue
                if attribute as String == kAXPositionAttribute {
                    XCTAssertTrue(AXValueGetValue(axValue, .cgPoint, &writtenPosition))
                } else {
                    XCTAssertTrue(AXValueGetValue(axValue, .cgSize, &writtenSize))
                }
                return .success
            })
            XCTAssertNil(controller.apply(.fullscreen, to: app, screens: screens))
            XCTAssertEqual(writtenPosition, expectedPosition)
            XCTAssertEqual(writtenSize, expectedSize)
        }
    }

    func test_applyReportsEveryReadFailureWithoutWriting() {
        for attribute in [kAXFocusedWindowAttribute, kAXPositionAttribute, kAXSizeAttribute] {
            let controller = makeController(readOverride: (attribute, .apiDisabled, nil))
            XCTAssertEqual(controller.apply(.leftHalf, to: app, screens: [(primary, primary)]),
                           "Cannot read \(attribute) (AX error \(AXError.apiDisabled.rawValue)).")
        }
    }

    func test_applyRejectsMissingAndWrongCFTypesWithoutWriting() {
        for attribute in [kAXFocusedWindowAttribute, kAXPositionAttribute, kAXSizeAttribute] {
            for value: CFTypeRef? in [nil, "invalid" as CFString] {
                let controller = makeController(readOverride: (attribute, .success, value))
                XCTAssertEqual(controller.apply(.leftHalf, to: app, screens: [(primary, primary)]),
                               "Invalid \(attribute) value.")
            }
        }
    }

    func test_applyRejectsWrongAXValueKindsWithoutWriting() {
        var point = CGPoint.zero
        var size = CGSize(width: 800, height: 600)
        let values: [(String, CFTypeRef)] = [
            (kAXPositionAttribute, AXValueCreate(.cgSize, &size)!),
            (kAXSizeAttribute, AXValueCreate(.cgPoint, &point)!)
        ]
        for (attribute, value) in values {
            let controller = makeController(readOverride: (attribute, .success, value))
            XCTAssertEqual(controller.apply(.leftHalf, to: app, screens: [(primary, primary)]),
                           "Invalid \(attribute) value.")
        }
    }

    func test_applyRejectsInvalidGeometryWithoutWriting() {
        for position in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity)] {
            XCTAssertEqual(makeController(position: position).apply(
                .leftHalf, to: app, screens: [(primary, primary)]), "Invalid window frame.")
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 600),
                     CGSize(width: CGFloat.infinity, height: 600)] {
            XCTAssertEqual(makeController(size: size).apply(
                .leftHalf, to: app, screens: [(primary, primary)]), "Invalid window frame.")
        }
    }

    func test_applyReportsNoScreensWithoutWriting() {
        XCTAssertEqual(makeController().apply(.leftHalf, to: app, screens: []),
                       "No screen available.")
    }

    func test_applyReportsEveryWriteFailureAndStops() {
        for (attribute, expectedWrites) in [(kAXSizeAttribute, [kAXSizeAttribute]),
                                            (kAXPositionAttribute, [kAXSizeAttribute, kAXPositionAttribute])] {
            var writes: [String] = []
            let controller = makeController(set: { _, name, _ in
                writes.append(name as String)
                return name as String == attribute ? .cannotComplete : .success
            })
            XCTAssertEqual(controller.apply(.leftHalf, to: app, screens: [(primary, primary)]),
                           "Cannot set \(attribute) (AX error \(AXError.cannotComplete.rawValue)).")
            XCTAssertEqual(writes, expectedWrites)
        }
    }

    private func makeController(
        position: CGPoint = CGPoint(x: 1800, y: 100),
        size: CGSize = CGSize(width: 800, height: 500),
        readOverride: (String, AXError, CFTypeRef?)? = nil,
        set: @escaping (AXUIElement, CFString, CFTypeRef) -> AXError = { _, _, _ in
            XCTFail("Invalid reads must not write a window frame")
            return .failure
        }
    ) -> WindowController {
        var position = position
        var size = size
        let values: [String: CFTypeRef] = [
            kAXFocusedWindowAttribute: window,
            kAXPositionAttribute: AXValueCreate(.cgPoint, &position)!,
            kAXSizeAttribute: AXValueCreate(.cgSize, &size)!
        ]
        return WindowController(copyAttribute: { element, attribute in
            let name = attribute as String
            XCTAssertTrue(CFEqual(element, name == kAXFocusedWindowAttribute ? self.app : self.window))
            if let (overriddenName, error, value) = readOverride, name == overriddenName {
                return (error, value)
            }
            return (.success, values[name])
        }, setAttribute: set)
    }
}
