import XCTest

/// Walks through both modes of the app like a user would and takes a screenshot of every step.
/// Each screenshot is kept as a test attachment and, when the `SCREENSHOT_DIR` environment variable
/// is set (CI passes `TEST_RUNNER_SCREENSHOT_DIR` to xcodebuild), also written there as `<name>.png`.
///
/// XCUIAutomation types are main-actor isolated in recent SDKs, so every method that touches them
/// is `@MainActor` (and no `setUp` override is needed: each test launches its own app).
final class AppTourUITests: XCTestCase {

    // MARK: - Tests

    /// Demo screenshots → stitch → result → seam editor.
    @MainActor
    func test01StitchFlow() throws {
        let app = launchApp()
        snapshot("01-inicio")

        let demoButton = app.buttons["demoButton"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 10), "No aparece el botón de ejemplo")
        revealIfNeeded(demoButton, in: app)
        demoButton.tap()

        let stitchButton = app.buttons["stitchButton"]
        XCTAssertTrue(stitchButton.waitForExistence(timeout: 20), "No se cargaron las capturas de ejemplo")
        waitUntilEnabled(stitchButton, timeout: 20)
        snapshot("02-capturas")

        stitchButton.tap()
        let resultView = app.descendants(matching: .any)["resultView"]
        XCTAssertTrue(resultView.waitForExistence(timeout: 60), "No apareció el resultado")
        pause(1.5)
        snapshot("03-resultado")

        let seamEditorButton = app.buttons["seamEditorButton"]
        XCTAssertTrue(seamEditorButton.waitForExistence(timeout: 10), "Falta el botón «Ajustar»")
        seamEditorButton.tap()
        let seamEditor = app.descendants(matching: .any)["seamEditorView"]
        XCTAssertTrue(seamEditor.waitForExistence(timeout: 15), "No se abrió el editor de uniones")
        pause(1.5)
        snapshot("04-uniones")
    }

    /// Web tab → open example.com → capture the whole page → result.
    @MainActor
    func test02WebFlow() throws {
        let app = launchApp()

        let webTab = app.tabBars.buttons["Web"]
        XCTAssertTrue(webTab.waitForExistence(timeout: 10), "Falta la pestaña «Web»")
        webTab.tap()
        pause(0.5)
        snapshot("05-web-inicio")

        let urlField = app.textFields["urlField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10), "Falta el campo de dirección")
        urlField.tap()
        urlField.typeText("example.com\n")

        // example.com has changed its wording over time; every version mentions "domain".
        let heading = app.webViews.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "domain"))
            .firstMatch
        guard heading.waitForExistence(timeout: 45) else {
            snapshot("06-web-sin-red")
            throw XCTSkip("Sin red")
        }
        pause(1)
        snapshot("06-web-pagina")

        let captureButton = app.buttons["captureButton"]
        XCTAssertTrue(captureButton.waitForExistence(timeout: 10), "Falta el botón «Capturar página»")
        waitUntilEnabled(captureButton, timeout: 30)
        captureButton.tap()

        let resultView = app.descendants(matching: .any)["resultView"]
        XCTAssertTrue(resultView.waitForExistence(timeout: 60), "No apareció la captura de la página")
        pause(1.5)
        snapshot("07-web-resultado")
    }

    // MARK: - Helpers

    @MainActor
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITests"]
        app.launch()
        return app
    }

    /// Full-screen screenshot kept in the test report and, if `SCREENSHOT_DIR` is set, saved as a PNG.
    @MainActor
    private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? ""
        guard !directory.isEmpty else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        let fileURL = folder.appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: fileURL, options: .atomic)
        } catch {
            print("No se pudo guardar la captura \(fileURL.path): \(error)")
        }
    }

    /// Waits until `element` is enabled (fails the test after `timeout` seconds).
    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "«\(element.identifier)» no se activó a tiempo",
                       file: file, line: line)
    }

    /// Scrolls the screen up a little (at most three times) until `element` can be tapped.
    @MainActor
    private func revealIfNeeded(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable && attempts < 3 {
            app.swipeUp()
            attempts += 1
        }
    }

    /// Lets animations and rendering settle before a screenshot.
    @MainActor
    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }
}
