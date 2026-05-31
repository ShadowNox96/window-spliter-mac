import XCTest
@testable import WindowSplitter

final class WindowActionTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func test_leftHalf_frame() {
        let frame = WindowAction.leftHalf.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 960, height: 1080))
    }

    func test_rightHalf_frame() {
        let frame = WindowAction.rightHalf.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 960, y: 0, width: 960, height: 1080))
    }

    func test_topHalf_frame() {
        let frame = WindowAction.topHalf.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 1920, height: 540))
    }

    func test_bottomHalf_frame() {
        let frame = WindowAction.bottomHalf.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 540, width: 1920, height: 540))
    }

    func test_leftThird_frame() {
        let frame = WindowAction.leftThird.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 640, height: 1080))
    }

    func test_centerThird_frame() {
        let frame = WindowAction.centerThird.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 640, y: 0, width: 640, height: 1080))
    }

    func test_rightThird_frame() {
        let frame = WindowAction.rightThird.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 1280, y: 0, width: 640, height: 1080))
    }

    func test_topLeftQuarter_frame() {
        let frame = WindowAction.topLeftQuarter.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 960, height: 540))
    }

    func test_topRightQuarter_frame() {
        let frame = WindowAction.topRightQuarter.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 960, y: 0, width: 960, height: 540))
    }

    func test_bottomLeftQuarter_frame() {
        let frame = WindowAction.bottomLeftQuarter.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 0, y: 540, width: 960, height: 540))
    }

    func test_bottomRightQuarter_frame() {
        let frame = WindowAction.bottomRightQuarter.frame(in: screen)
        XCTAssertEqual(frame, CGRect(x: 960, y: 540, width: 960, height: 540))
    }

    func test_fullscreen_frame() {
        let frame = WindowAction.fullscreen.frame(in: screen)
        XCTAssertEqual(frame, screen)
    }

    func test_allCasesHaveDefaultKeyCode() {
        for action in WindowAction.allCases {
            XCTAssertGreaterThan(action.defaultKeyCode, 0, "\(action) has invalid keyCode")
        }
    }

    func test_defaultModifiersAreOptionShift() {
        let expected = Int(NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        for action in WindowAction.allCases {
            XCTAssertEqual(action.defaultModifiers, expected)
        }
    }

    func test_frameWithOffset_screen() {
        let offsetScreen = CGRect(x: 1920, y: 0, width: 1280, height: 800)
        let frame = WindowAction.leftHalf.frame(in: offsetScreen)
        XCTAssertEqual(frame, CGRect(x: 1920, y: 0, width: 640, height: 800))
    }
}
