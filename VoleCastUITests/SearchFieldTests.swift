import XCTest

/// The search field is hand-drawn: a `TextField` inside a capsule, with an
/// icon and padding around it. The capsule is what reads as the field, so a
/// tap anywhere on it has to start typing — not only a tap that happens to
/// land on the text itself.
final class SearchFieldTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openSearch() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["Show name or RSS URL"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        return (app, field)
    }

    /// Taps a point given in points from the text field's own frame.
    @MainActor
    private func tap(_ field: XCUIElement, dx: CGFloat, dy: CGFloat) {
        field.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: dx, dy: dy))
            .tap()
    }

    /// The control: if this fails, the simulator is not showing its keyboard
    /// at all — a connected hardware keyboard hides it — and the two below
    /// prove nothing.
    @MainActor
    func testTappingTheTextStartsTyping() {
        let (app, field) = openSearch()
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testTappingTheMagnifyingGlassStartsTyping() {
        let (app, field) = openSearch()
        // Left of the text, on the icon inside the capsule.
        tap(field, dx: -16, dy: field.frame.height / 2)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }

    /// The capsule's own tap must not swallow the Clear button inside it.
    @MainActor
    func testClearStillClears() {
        let (app, field) = openSearch()
        field.tap()
        field.typeText("vergecast")
        app.buttons["Clear"].tap()
        XCTAssertEqual(field.value as? String, "Show name or RSS URL")
    }

    @MainActor
    func testTappingThePaddingAboveTheTextStartsTyping() {
        let (app, field) = openSearch()
        // Inside the capsule, in the padding above the text.
        tap(field, dx: field.frame.width / 2, dy: -5)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }
}
