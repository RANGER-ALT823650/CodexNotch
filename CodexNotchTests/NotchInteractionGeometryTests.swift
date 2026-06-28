@testable import CodexNotch
import AppKit
import XCTest

final class NotchInteractionGeometryTests: XCTestCase {
    func testCentersInteractionFrameOnPhysicalNotchAndIncludesSideUsage() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let left = NSRect(x: 0, y: 944, width: 666, height: 38)
        let right = NSRect(x: 846, y: 944, width: 666, height: 38)

        let frame = NotchInteractionGeometry.compactFrame(
            screenFrame: screen,
            safeAreaTop: 38,
            menuBarHeight: 38,
            auxiliaryLeft: left,
            auxiliaryRight: right
        )

        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.width, 340)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertTrue(frame.contains(NSPoint(x: screen.midX, y: 960)))
    }

    func testUsesCenteredFallbackOnNotchlessDisplay() {
        let screen = NSRect(x: 2000, y: 0, width: 1920, height: 1080)
        let frame = NotchInteractionGeometry.compactFrame(
            screenFrame: screen,
            safeAreaTop: 0,
            menuBarHeight: 24,
            auxiliaryLeft: nil,
            auxiliaryRight: nil
        )

        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.width, 460)
        XCTAssertEqual(frame.height, 28)
    }
}

