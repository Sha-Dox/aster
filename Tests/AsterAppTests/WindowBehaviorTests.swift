import XCTest
import AppKit
@testable import Aster

@MainActor final class WindowBehaviorTests: XCTestCase {
    func testNormalWindowDoesNotDragFromBodyOrStayAboveOtherApps() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.level = .floating; window.isMovableByWindowBackground = true
        WindowBehavior.configure(window)
        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.isMovable)
    }
    func testTextAndBackdropNeverParticipateInWindowDragging() {
        XCTAssertFalse(FormalisingTextView(frame: .zero).mouseDownCanMoveWindow)
        XCTAssertFalse(SelectionScrollView(frame: .zero).mouseDownCanMoveWindow)
        let backdrop = DesktopGlassEffectView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(backdrop.mouseDownCanMoveWindow)
        XCTAssertNil(backdrop.hitTest(NSPoint(x: 20, y: 20)))
    }
}
