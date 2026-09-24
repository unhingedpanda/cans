import XCTest

/// UI end-to-end tests: the real app, talking to a real, connected WH-1000XM4.
/// Every assertion waits for state the headphones reported back, never an optimistic UI value.
/// Run via scripts/e2e.sh with Cans and Sound Connect closed.
final class AppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ui-test-host", "-AppleLanguages", "(en)"]
        app.launch()
        // A menu bar app is not frontmost after launch; menus only open for the active app.
        app.activate()
        XCTAssertTrue(app.buttons["noiseControl.anc"].waitForExistence(timeout: 20), "control link never became ready")
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private func waitSelected(_ element: XCUIElement, _ selected: Bool = true, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "isSelected == %@", NSNumber(value: selected))
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout) == .completed
    }

    /// Opens Inserts and a section, waiting for each transition to settle.
    private func openSection(_ name: String) {
        app.buttons["inserts.open"].click()
        let section = app.buttons["section.\(name)"]
        XCTAssertTrue(section.waitForExistence(timeout: 3))
        section.click()
        XCTAssertTrue(waitSelected(section), "section \(name) did not open")
    }

    private func latch(_ title: String) -> XCUIElement { app.buttons["latch.\(title)"] }

    /// Sliders report numbers, not strings.
    private func waitNumber(_ element: XCUIElement, _ number: Int, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "value == %d", number)
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout) == .completed
    }

    private func waitValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout) == .completed
    }

    @MainActor
    func testNoiseControlButtonsDriveTheHeadphones() {
        let modes = ["off", "ambient", "anc"].map { app.buttons["noiseControl.\($0)"] }
        let original = modes.first { $0.isSelected }
        for button in modes {
            button.click()
            XCTAssertTrue(waitSelected(button), "\(button.identifier) was not confirmed by the headphones")
        }
        original?.click()
        if let original { XCTAssertTrue(waitSelected(original)) }
    }

    @MainActor
    func testKeyboardShortcutsSwitchModes() {
        let original = ["off", "ambient", "anc"].map { app.buttons["noiseControl.\($0)"] }.first { $0.isSelected }
        app.typeKey("3", modifierFlags: [])
        XCTAssertTrue(waitSelected(app.buttons["noiseControl.ambient"]))
        app.typeKey("2", modifierFlags: [])
        XCTAssertTrue(waitSelected(app.buttons["noiseControl.anc"]))
        original?.click()
    }

    @MainActor
    func testScenesApplyTheirSettings() {
        let original = ["off", "ambient", "anc"].map { app.buttons["noiseControl.\($0)"] }.first { $0.isSelected }
        app.buttons["Aware"].click()
        XCTAssertTrue(waitSelected(app.buttons["noiseControl.ambient"]))
        let level = app.sliders["Ambient level"]
        XCTAssertTrue(waitNumber(level, 20), "ambient level reads \(String(describing: level.value))")
        app.buttons["Office"].click()
        XCTAssertTrue(waitNumber(level, 8), "ambient level reads \(String(describing: level.value))")
        XCTAssertTrue(waitValue(app.buttons["Focus on Voice"], "On"))
        original?.click()
    }

    @MainActor
    func testEqualizerPresetMenu() {
        let menu = app.menuButtons["equalizer.preset"]
        let original = menu.value as? String ?? "Off"
        menu.click()
        XCTAssertTrue(app.menuItems["Bass Boost"].waitForExistence(timeout: 3))
        app.menuItems["Bass Boost"].click()
        XCTAssertTrue(waitValue(menu, "Bass Boost"))
        // Verified on hardware: Bass Boost reports Clear Bass +7.
        let clearBass = app.sliders["Clear Bass"]
        XCTAssertTrue(waitNumber(clearBass, 7), "Clear Bass reads \(String(describing: clearBass.value))")
        menu.click()
        let restore = app.menuItems[original == "Manual" ? "Off" : original]
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        restore.click()
    }

    @MainActor
    func testInsertsTogglesAreConfirmedAfterSync() {
        openSection("controls")
        let touch = latch("Touch controls")
        XCTAssertTrue(touch.waitForExistence(timeout: 3))
        let original = touch.value as? String
        touch.click()
        // Prove it: re-read everything from the headphones, then check the value survived.
        app.buttons["section.diagnostics"].click()
        app.buttons["Sync now"].click()
        app.buttons["section.controls"].click()
        let flipped = original == "On" ? "Off" : "On"
        XCTAssertTrue(waitSelected(app.buttons["section.controls"]))
        XCTAssertTrue(waitValue(latch("Touch controls"), flipped))
        latch("Touch controls").click()
        XCTAssertTrue(waitValue(latch("Touch controls"), original ?? "On"))
    }

    @MainActor
    func testMultipointAsksBeforeChanging() {
        openSection("controls")
        let multipoint = latch("Connect to 2 devices")
        XCTAssertTrue(multipoint.waitForExistence(timeout: 3))
        let before = multipoint.value as? String
        multipoint.click()
        let cancel = app.sheets.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3), "no confirmation before a restart-prone change")
        cancel.click()
        XCTAssertEqual(multipoint.value as? String, before)
    }

    @MainActor
    func testSpeakToChatRevealsItsOptions() {
        openSection("speakToChat")
        let stc = latch("Speak-to-Chat")
        XCTAssertTrue(stc.waitForExistence(timeout: 3))
        if stc.value as? String == "Off" {
            stc.click()
            XCTAssertTrue(waitValue(stc, "On"))
            XCTAssertTrue(app.buttons["Auto"].waitForExistence(timeout: 5))
            stc.click()
            XCTAssertTrue(waitValue(stc, "Off"))
        } else {
            XCTAssertTrue(app.buttons["Auto"].waitForExistence(timeout: 3),
                          "speak-to-chat options missing:\n\(app.windows.firstMatch.buttons.debugDescription)")
        }
    }

    @MainActor
    func testEveryInsertsSectionOpens() {
        app.buttons["inserts.open"].click()
        for section in ["headphones", "speakToChat", "noiseCancelling", "sound", "controls", "app", "diagnostics"] {
            let button = app.buttons["section.\(section)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3), section)
            button.click()
            XCTAssertTrue(waitSelected(button), section)
        }
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(app.buttons["noiseControl.anc"].waitForExistence(timeout: 3))
    }

    /// The headphones never get track metadata from macOS; Cans reads the system Now Playing,
    /// so any app works. Needs something loaded in Now Playing (e.g. a paused Spotify track).
    @MainActor
    func testNowPlayingShowsTheSystemTrackAndControlsIt() throws {
        let play = app.buttons["Play"], pause = app.buttons["Pause"]
        XCTAssertTrue(play.waitForExistence(timeout: 8) || pause.exists)
        try XCTSkipIf(app.staticTexts["Nothing playing"].waitForExistence(timeout: 3),
                      "Load a track in any player to run this test.")
        let wasPlaying = pause.exists
        (wasPlaying ? pause : play).click()
        XCTAssertTrue((wasPlaying ? play : pause).waitForExistence(timeout: 6), "the player did not change state")
        (wasPlaying ? play : pause).click()
        XCTAssertTrue((wasPlaying ? pause : play).waitForExistence(timeout: 6))
    }
}
