import XCTest
@testable import Cans

/// End-to-end tests against a real, powered-on, connected WH-1000XM4 over Bluetooth.
/// Every test changes a setting, makes the app forget everything, re-reads it from the
/// headphones, asserts the headphones hold the new value, then restores the original.
/// Run with scripts/e2e.sh (quit Cans and Sound Connect first: one owner per channel).
/// Opt-in destructive cases: CANS_E2E_MULTIPOINT=1 (may restart the headphones).
@MainActor
final class HardwareE2ETests: XCTestCase {
    private static var shared: SonyHeadphonesController?
    private var hp: SonyHeadphonesController { Self.shared! }
    private var dev: SonyDeviceSettings { hp.deviceSettings }

    override func setUp() async throws {
        if Self.shared == nil { Self.shared = SonyHeadphonesController() }
        try await until("control link ready", timeout: 25) { self.hp.isReady && self.dev.modelName != nil }
    }

    override class func tearDown() {
        MainActor.assumeIsolated {
            shared?.disconnect()
            shared = nil
        }
        super.tearDown()
    }

    // MARK: Helpers

    private func until(_ what: String, timeout: TimeInterval = 8, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw Timeout(what: what) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    struct Timeout: Error, CustomStringConvertible {
        let what: String
        var description: String { "Timed out waiting for: \(what)" }
    }

    /// Forget and re-read everything, then wait for `field` to come back from the headphones.
    private func reload<T>(_ label: String, _ field: @escaping () -> T?) async throws -> T {
        // Let the headphones finish applying the last write, then wait until every re-read is answered.
        try await Task.sleep(for: .milliseconds(300))
        await withCheckedContinuation { done in hp.reloadFromDevice { done.resume() } }
        // A reply can land after its request's wait (e.g. codec renegotiation); allow it to arrive.
        try await until("\(label) re-read from headphones", timeout: 8) { field() != nil }
        return field()!
    }

    /// Flip a setting, prove the headphones hold it, restore it, prove the restore.
    private func roundTrip<T: Equatable>(
        _ label: String,
        read: @escaping () -> T?,
        other: (T) -> T,
        write: (T) -> Void
    ) async throws {
        let original = try await reload(label, read)
        let changed = other(original)
        XCTAssertNotEqual(changed, original, "\(label): test must pick a different value")
        write(changed)
        let held = try await reload(label, read)
        XCTAssertEqual(held, changed, "\(label): headphones did not keep the new value")
        write(original)
        let restored = try await reload(label, read)
        XCTAssertEqual(restored, original, "\(label): headphones did not restore the original value")
    }

    // MARK: Link and telemetry

    func testLinkReportsIdentityAndTelemetry() async throws {
        XCTAssertEqual(hp.protocolDescription.hasPrefix("MDR v1"), true)
        XCTAssertEqual(dev.modelName, "WH-1000XM4")
        let battery = try await reload("battery") { self.hp.batteryLevel }
        XCTAssertTrue((1...100).contains(battery))
        try await until("firmware") { self.hp.firmwareVersion != nil }
        XCTAssertFalse(hp.firmwareVersion!.isEmpty)
        let codec = try await reload("codec") { self.dev.codec }
        XCTAssertTrue(["SBC", "AAC", "LDAC", "aptX", "aptX HD"].contains(codec))
        let v2 = try await reload("air pressure") { self.dev.pressureAtm }
        XCTAssertNotNil(v2)
    }

    // MARK: Noise control

    func testEveryNoiseModeIsHeldByTheHeadphones() async throws {
        let original = try await reload("noise mode") { self.hp.noiseControlMode }
        let originalLevel = hp.ambientLevel, originalVoice = hp.focusOnVoice
        for mode in [NoiseControlMode.off, .ambient, .anc] {
            hp.setNoiseControl(mode)
            let held = try await reload("noise mode \(mode)") { self.hp.noiseControlMode }
            XCTAssertEqual(held, mode)
        }
        hp.applyPreset(mode: original, ambientLevel: max(1, originalLevel), focusOnVoice: originalVoice)
        let v3 = try await reload("noise mode restore") { self.hp.noiseControlMode }
        XCTAssertEqual(v3, original)
    }

    func testAmbientLevelAndFocusOnVoice() async throws {
        let original = try await reload("noise mode") { self.hp.noiseControlMode }
        let originalLevel = hp.ambientLevel, originalVoice = hp.focusOnVoice
        hp.applyPreset(mode: .ambient, ambientLevel: 7, focusOnVoice: true)
        _ = try await reload("ambient") { self.hp.noiseControlMode }
        XCTAssertEqual(hp.noiseControlMode, .ambient)
        XCTAssertEqual(hp.ambientLevel, 7)
        XCTAssertTrue(hp.focusOnVoice)

        hp.setFocusOnVoice(false)
        try await Task.sleep(for: .milliseconds(300))
        hp.setAmbientLevel(18)
        _ = try await reload("ambient 18") { self.hp.noiseControlMode }
        XCTAssertEqual(hp.ambientLevel, 18)
        XCTAssertFalse(hp.focusOnVoice)

        hp.applyPreset(mode: original, ambientLevel: max(1, originalLevel), focusOnVoice: originalVoice)
        let v4 = try await reload("restore") { self.hp.noiseControlMode }
        XCTAssertEqual(v4, original)
    }

    // MARK: Equalizer

    func testEqualizerPresetAndCustomCurve() async throws {
        let originalPreset = try await reload("EQ") { self.hp.equalizerPreset }
        let originalCurve = hp.customEqualizer

        hp.setEqualizerPreset(.bassBoost)
        let v5 = try await reload("bass boost") { self.hp.equalizerPreset }
        XCTAssertEqual(v5, .bassBoost)
        // Verified on hardware: Bass Boost reports Clear Bass +7 and flat bands.
        XCTAssertEqual(hp.customEqualizer, EqualizerSettings(clearBass: 7, bands: [0, 0, 0, 0, 0]))

        let curve = EqualizerSettings(clearBass: 2, bands: [1, -1, 3, 0, -2])
        hp.setCustomEqualizer(curve)
        let v6 = try await reload("manual") { self.hp.equalizerPreset }
        XCTAssertEqual(v6, .manual)
        XCTAssertEqual(hp.customEqualizer, curve)

        if originalPreset == .manual { hp.setCustomEqualizer(originalCurve) } else { hp.setEqualizerPreset(originalPreset) }
        let v7 = try await reload("EQ restore") { self.hp.equalizerPreset }
        XCTAssertEqual(v7, originalPreset)
    }

    /// Custom 1/2 (A1/A2) were read as unknown and locked the EQ (issue #2).
    func testCustomSlotsReadBack() async throws {
        let originalPreset = try await reload("EQ") { self.hp.equalizerPreset }
        let originalCurve = hp.customEqualizer
        for slot in [EqualizerPreset.custom1, .custom2] {
            hp.setEqualizerPreset(slot)
            let held = try await reload(slot.title) { self.hp.equalizerPreset }
            XCTAssertEqual(held, slot)
        }
        if originalPreset == .manual { hp.setCustomEqualizer(originalCurve) } else { hp.setEqualizerPreset(originalPreset) }
        let restored = try await reload("EQ restore") { self.hp.equalizerPreset }
        XCTAssertEqual(restored, originalPreset)
    }

    // MARK: Inserts

    func testDSEEExtreme() async throws {
        try await roundTrip("DSEE Extreme", read: { self.dev.dseeExtreme }, other: { !$0 }, write: { self.dev.setDSEEExtreme($0) })
    }

    func testSoundQualityPriority() async throws {
        try await roundTrip("connection priority", read: { self.dev.prefersStableConnection }, other: { !$0 },
                            write: { self.dev.setPrefersStableConnection($0) })
        // Switching priority renegotiates the codec; it must come back.
        let v8 = try await reload("codec after renegotiation") { self.dev.codec }
        XCTAssertNotNil(v8)
    }

    func testTouchPanel() async throws {
        try await roundTrip("touch panel", read: { self.dev.touchPanel }, other: { !$0 }, write: { self.dev.setTouchPanel($0) })
    }

    func testPauseWhenTakenOff() async throws {
        try await roundTrip("pause when removed", read: { self.dev.pauseWhenRemoved }, other: { !$0 },
                            write: { self.dev.setPauseWhenRemoved($0) })
    }

    func testAutoPowerOff() async throws {
        try await roundTrip("auto power off", read: { self.dev.autoPowerOff },
                            other: { $0 == .whenRemoved ? .never : .whenRemoved }, write: { self.dev.setAutoPowerOff($0) })
    }

    func testSpeakToChatOnOff() async throws {
        try await roundTrip("speak-to-chat", read: { self.dev.speakToChat }, other: { !$0 }, write: { self.dev.setSpeakToChat($0) })
    }

    func testSpeakToChatConfig() async throws {
        try await roundTrip("speak-to-chat config", read: { self.dev.speakToChatConfig }, other: { config in
            .init(sensitivity: config.sensitivity == .high ? .low : .high,
                  focusOnVoice: !config.focusOnVoice,
                  timeout: config.timeout == .long ? .standard : .long)
        }, write: { self.dev.setSpeakToChatConfig($0) })
    }

    /// Ambient control always works; an assistant is only accepted if it was set up on a phone.
    /// Either way the app must show what the headphones actually hold, never the optimistic pick.
    func testCustomButtonShowsWhatTheHeadphonesAccepted() async throws {
        let original = try await reload("custom button") { self.dev.customButton }
        dev.setCustomButton(.googleAssistant)
        let afterAssistant = try await reload("custom button after assistant") { self.dev.customButton }
        XCTAssertTrue([.googleAssistant, original].contains(afterAssistant))
        dev.setCustomButton(.ambientControl)
        let v = try await reload("custom button ambient") { self.dev.customButton }
        XCTAssertEqual(v, .ambientControl)
        if original != .ambientControl { dev.setCustomButton(original) }
    }

    func testVoiceGuidance() async throws {
        try await roundTrip("voice guidance", read: { self.dev.voiceGuidance }, other: { !$0 }, write: { self.dev.setVoiceGuidance($0) })
    }


    func testPlayPause() async throws {
        let original = try await reload("play state") { self.dev.isPlaying }
        dev.playback(original ? .pause : .play)
        let v9 = try await reload("play state flipped") { self.dev.isPlaying }
        XCTAssertEqual(v9, !original)
        dev.playback(original ? .play : .pause)
        let v10 = try await reload("play state restored") { self.dev.isPlaying }
        XCTAssertEqual(v10, original)
    }

    func testNCOptimizerStartsAndCancels() async throws {
        dev.startOptimizer()
        // .starting is Cans's own state; only a reported phase proves the headphones began measuring.
        try await until("optimizer measuring", timeout: 6) { self.dev.optimizer == .measuringWear }
        try await Task.sleep(for: .milliseconds(800))
        dev.cancelOptimizer()
        try await until("optimizer idle", timeout: 6) { self.dev.optimizer == .idle }
        // The headphones re-apply noise control after the optimizer; it must still report a mode.
        let v11 = try await reload("mode after optimizer") { self.hp.noiseControlMode }
        XCTAssertNotNil(v11)
    }

    func testMultipoint() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CANS_E2E_MULTIPOINT"] == "1",
                          "Toggling multipoint can restart the headphones; set CANS_E2E_MULTIPOINT=1 to run.")
        try await roundTrip("multipoint", read: { self.dev.multipoint }, other: { !$0 }, write: { self.dev.setMultipoint($0) })
    }

    func testSyncNowRecoversEverySetting() async throws {
        hp.reloadFromDevice()
        try await until("all settings re-read", timeout: 10) {
            [self.dev.codec as Any?, self.dev.dseeExtreme, self.dev.prefersStableConnection, self.dev.touchPanel,
             self.dev.multipoint, self.dev.pauseWhenRemoved, self.dev.autoPowerOff, self.dev.speakToChat,
             self.dev.speakToChatConfig, self.dev.customButton, self.dev.voiceGuidance,
             self.dev.isPlaying, self.dev.pressureAtm, self.hp.batteryLevel, self.hp.equalizerPreset,
             self.hp.noiseControlMode].allSatisfy { $0 != nil }
        }
    }
}
