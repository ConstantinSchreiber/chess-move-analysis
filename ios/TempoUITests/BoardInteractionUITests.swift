import XCTest

/// Drives the analysis board with real touches: drag-and-drop, tap-tap, navigation.
final class BoardInteractionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demoAnalysis", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]
        app.launch()
    }

    /// Centre of a square on a board shown from White's side.
    private func point(_ square: String, on board: XCUIElement) -> XCUICoordinate {
        let chars = Array(square)
        let file = Double(chars[0].asciiValue! - 97), rank = Double(chars[1].wholeNumberValue! - 1)
        return board.coordinate(withNormalizedOffset: CGVector(dx: (file + 0.5) / 8, dy: (7.5 - rank) / 8))
    }

    func testDragTapAndNavigate() throws {
        let board = app.otherElements["board"]
        XCTAssertTrue(board.waitForExistence(timeout: 20))

        // Drag e2 → e4.
        point("e2", on: board).press(forDuration: 0.15, thenDragTo: point("e4", on: board))
        XCTAssertTrue(app.buttons["e4"].waitForExistence(timeout: 5), "drag should play e4")

        // Tap e7, then e5.
        point("e7", on: board).tap()
        point("e5", on: board).tap()
        XCTAssertTrue(app.buttons["e5"].waitForExistence(timeout: 5), "tap-tap should play e5")

        // An illegal drag (Ng1 → g4) does nothing.
        point("g1", on: board).press(forDuration: 0.15, thenDragTo: point("g4", on: board))
        XCTAssertFalse(app.buttons["Ng4"].exists)

        // Navigate back and branch: after 1.e4, play 1…c5 instead.
        app.buttons["Previous move"].tap()
        point("c7", on: board).press(forDuration: 0.15, thenDragTo: point("c5", on: board))
        XCTAssertTrue(app.buttons["c5"].waitForExistence(timeout: 5), "branching move c5")

        // The engine produces a best move for the new position.
        XCTAssertTrue(app.staticTexts["Best move"].waitForExistence(timeout: 60) ||
                      app.staticTexts["BEST MOVE"].waitForExistence(timeout: 1))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
