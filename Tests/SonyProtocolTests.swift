import Foundation
import XCTest
@testable import Cans

final class SonyProtocolTests: XCTestCase {
    func testReconnectBackoffCapsAtThirtySeconds() {
        XCTAssertEqual((0...6).map(ReconnectBackoff.delay), [2, 4, 8, 15, 30, 30, 30])
    }

    func testFrameRoundTripIncludingEscapedBytes() {
        let payload: [UInt8] = [0x68, 0x3C, 0x3D, 0x3E, 0x01]
        let encoded = SonyFrameCodec.encode(type: 0x0C, sequence: 1, payload: payload)
        XCTAssertEqual(SonyFrameCodec.decode(encoded), SonyFrame(type: 0x0C, sequence: 1, payload: payload))
    }

    func testStreamReassemblesSplitFrames() {
        let encoded = SonyFrameCodec.encode(type: 0x0C, sequence: 0, payload: [0x00, 0x00])
        var stream = SonyFrameStream()
        XCTAssertTrue(stream.append(encoded.prefix(3)).isEmpty)
        XCTAssertEqual(stream.append(encoded.dropFirst(3)).first?.payload, [0x00, 0x00])
    }

    func testRejectsBadChecksum() {
        var encoded = SonyFrameCodec.encode(type: 0x0C, sequence: 0, payload: [0x06, 0x00])
        encoded[encoded.count - 2] ^= 0x01
        XCTAssertNil(SonyFrameCodec.decode(encoded))
    }

    func testEqualizerPresetProtocolValues() {
        XCTAssertEqual(EqualizerPreset.off.rawValue, 0x00)
        XCTAssertEqual(EqualizerPreset.bassBoost.rawValue, 0x16)
        XCTAssertEqual(EqualizerPreset.manual.rawValue, 0xA0)
        XCTAssertFalse(EqualizerPreset.selectableCases.contains(.manual))
        XCTAssertEqual(EqualizerPreset(sonyByte: 0x16), .bassBoost)
        XCTAssertEqual(EqualizerPreset(sonyByte: 0xA1), .custom1)
        XCTAssertEqual(EqualizerPreset(sonyByte: 0xA2), .custom2)
        XCTAssertEqual(EqualizerPreset(sonyByte: 0xFF), .manual)
        XCTAssertFalse(EqualizerPreset.selectableCases.contains(.custom1))
    }

    func testCustomEqualizerPayloadRoundTripAndClamping() {
        let settings = EqualizerSettings(clearBass: 12, bands: [-12, -4, 0, 6, 14])
        XCTAssertEqual(settings, EqualizerSettings(clearBass: 10, bands: [-10, -4, 0, 6, 10]))
        XCTAssertEqual(settings.sonySetPayload, [0x58, 0x00, 0xA0, 0x06, 20, 0, 6, 10, 16, 20])

        let response = [UInt8(0x57)] + Array(settings.sonySetPayload.dropFirst())
        XCTAssertEqual(EqualizerSettings(sonyPayload: response), settings)
    }

    /// Replies captured from a real WH-1000XM4 (firmware 3.0.1).
    @MainActor
    func testDeviceSettingsParseRealXM4Replies() {
        let settings = SonyDeviceSettings()
        var sent: [[UInt8]] = []
        settings.send = { payload, _ in sent.append(payload) }
        let replies: [[UInt8]] = [
            [0x05, 0x01, 0x0A] + Array("WH-1000XM4".utf8),
            [0x19, 0x00, 0x02], [0x15, 0x00, 0x02, 0x01], [0xE7, 0x01, 0x00, 0x00], [0xE7, 0x02, 0x00, 0x01],
            [0xD7, 0xD1, 0x01, 0x01], [0xD7, 0xD2, 0x01, 0x00], [0xF7, 0x03, 0x00, 0x01], [0xF7, 0x04, 0x01, 0x10, 0x00],
            [0xF7, 0x05, 0x00, 0x01], [0xFB, 0x05, 0x00, 0x00, 0x01, 0x00], [0xF7, 0x06, 0x01, 0x00],
            [0xA7, 0x01, 0x20, 0x10], [0xA3, 0x01, 0x00, 0x02], [0x87, 0x01, 0x01, 0x01, 0x01, 0x09],
        ]
        for reply in replies { XCTAssertTrue(settings.handle(reply, tableTwo: false), "\(reply)") }
        XCTAssertTrue(settings.handle([0x47, 0x01, 0x01, 0x01], tableTwo: true))

        XCTAssertEqual(settings.modelName, "WH-1000XM4")
        XCTAssertEqual(settings.codec, "AAC")
        XCTAssertEqual(settings.dseeActive, true)
        XCTAssertEqual(settings.prefersStableConnection, false)
        XCTAssertEqual(settings.dseeExtreme, true)
        XCTAssertEqual(settings.touchPanel, true)
        XCTAssertEqual(settings.multipoint, false)
        XCTAssertEqual(settings.pauseWhenRemoved, true)
        XCTAssertEqual(settings.autoPowerOff, .whenRemoved)
        XCTAssertEqual(settings.speakToChat, true)
        XCTAssertEqual(settings.speakToChatConfig, .init(sensitivity: .auto, focusOnVoice: true, timeout: .short))
        XCTAssertEqual(settings.customButton, .ambientControl)
        XCTAssertEqual(settings.isPlaying, false)
        XCTAssertEqual(settings.pressureAtm, 0.9)
        XCTAssertEqual(settings.voiceGuidance, true)

        // The speak-to-chat "preview" notify (type 02) must not flip the setting.
        settings.handle([0xF9, 0x05, 0x02, 0x00], tableTwo: false)
        XCTAssertEqual(settings.speakToChat, true)

        // Setters emit the verified command bytes.
        settings.setMultipoint(true)
        settings.setSpeakToChat(false)
        settings.setAutoPowerOff(.never)
        XCTAssertEqual(sent.suffix(3), [[0xD8, 0xD2, 0x01, 0x01], [0xF8, 0x05, 0x01, 0x00], [0xF8, 0x04, 0x01, 0x11, 0x00]])
    }
}
