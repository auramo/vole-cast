import XCTest

/// Captures the App Store screenshots, in English and Finnish, on whichever
/// simulator it runs on.
///
/// Unlike most screenshot setups there is no sample data: the simulator is
/// signed into a real Apple Account, so the library arrives by iCloud sync.
/// That keeps the shots honest and means whatever is on the phone is what gets
/// photographed — worth remembering before running it.
///
/// Run it through `scripts/screenshots.sh`, which picks the devices whose
/// screens are the sizes App Store Connect asks for, sets a clean status bar,
/// and says where the images went.
final class ScreenshotTests: XCTestCase {

    /// The labels to tap, per language. Tabs are matched inside the tab bar
    /// because "Search" and "Haku" each name both a tab and a segment, and the
    /// plain button query would find either.
    private struct Script {
        let language: String
        let locale: String
        let subscriptions: String
        let search: String
        let discover: String
        let retry: String
    }

    private let scripts = [
        Script(
            language: "en", locale: "en_US",
            subscriptions: "Subscriptions", search: "Search", discover: "Discover",
            retry: "Try Again"
        ),
        Script(
            language: "fi", locale: "fi_FI",
            subscriptions: "Tilaukset", search: "Haku", discover: "Selaa",
            retry: "Yritä uudelleen"
        ),
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() throws {
        for script in scripts {
            try capture(script)
        }
    }

    @MainActor
    private func capture(_ script: Script) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(script.language))",
            "-AppleLocale", script.locale,
        ]
        app.launch()
        defer { app.terminate() }

        // Latest: the newest episodes across everything subscribed to. Given a
        // generous wait — a cold launch may be refreshing feeds, and an empty
        // list is not worth photographing.
        let firstEpisode = app.cells.firstMatch
        XCTAssertTrue(
            firstEpisode.waitForExistence(timeout: 30),
            "No episodes on the Latest tab. Is this simulator signed into iCloud?"
        )
        try snapshot("1-latest", script)

        // One episode's own screen: its notes, and the way into its show.
        firstEpisode.tap()
        try snapshot("2-episode", script)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The shows being followed.
        app.tabBars.buttons[script.subscriptions].tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10))
        try snapshot("3-subscriptions", script)

        // Discover, which needs a round trip to Apple before it has anything
        // to show.
        app.tabBars.buttons[script.search].tap()
        app.buttons[script.discover].tap()
        XCTAssertTrue(
            chartArrives(app, script),
            "The chart never arrived, and Try Again did not rescue it."
        )
        // The rows arrive before their artwork, which is fetched a show at a
        // time from Apple. Unlike Latest, nothing here is cached from an
        // earlier screen, so snapping the instant the cells exist can catch a
        // column of grey placeholders — which is what the store would then
        // show. Give the images a moment to land.
        Thread.sleep(forTimeInterval: 5)
        try snapshot("4-discover", script)
    }

    /// Waits for the chart, tapping Try Again whenever it fails to turn up.
    ///
    /// Apple's chart host hangs often enough to matter: probing
    /// `rss.marketingtools.apple.com` directly, one call in four never answered
    /// inside thirty seconds while the rest came back in about one. A single
    /// wait therefore makes an eight-shot run a coin flip, and the failure
    /// lands on the last shot after ten minutes of work. Both failure states
    /// offer the same button a person would reach for, so take it.
    @MainActor
    private func chartArrives(_ app: XCUIApplication, _ script: Script) -> Bool {
        for _ in 0..<4 {
            if app.cells.firstMatch.waitForExistence(timeout: 30) { return true }
            // Absent means the request is still in flight rather than failed;
            // going round again simply keeps waiting.
            let again = app.buttons[script.retry]
            if again.waitForExistence(timeout: 2) { again.tap() }
        }
        return false
    }

    /// Writes the image where `screenshots.sh` asked for it, under the pixel
    /// size it came out at — which is the thing App Store Connect sorts its
    /// upload slots by, so the folder name says which slot it belongs in.
    @MainActor
    private func snapshot(_ name: String, _ script: Script) throws {
        let shot = XCUIScreen.main.screenshot()
        guard let root = ProcessInfo.processInfo.environment["VOLECAST_SCREENSHOT_DIR"] else {
            // Still useful when run from Xcode rather than the script: the
            // image goes to the test report instead of to disk.
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "\(script.language)-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            return
        }

        let pixels = CGSize(
            width: shot.image.size.width * shot.image.scale,
            height: shot.image.size.height * shot.image.scale
        )
        let folder = URL(fileURLWithPath: root)
            .appendingPathComponent(script.language)
            .appendingPathComponent("\(Int(pixels.width))x\(Int(pixels.height))")
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        try shot.pngRepresentation.write(
            to: folder.appendingPathComponent("\(name).png")
        )
    }
}
