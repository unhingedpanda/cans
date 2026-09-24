import Combine
import Foundation

/// Everything beyond noise control / EQ / battery that the headphones expose over MDR v1 (WH-1000XM4).
/// Byte layouts were verified against a WH-1000XM4 on firmware 3.0.1. A nil property means the
/// headphones have not reported it (or, on XM5, that it is not implemented), and the UI hides it.
@MainActor
final class SonyDeviceSettings: ObservableObject {
    enum AutoPowerOff: UInt8, CaseIterable, Identifiable, Sendable {
        case whenRemoved = 0x10
        case never = 0x11
        var id: Self { self }
        var title: String { self == .whenRemoved ? "When taken off" : "Never" }
    }

    enum SpeakToChatSensitivity: UInt8, CaseIterable, Identifiable, Sendable {
        case auto = 0x00, high = 0x01, low = 0x02
        var id: Self { self }
        var title: String {
            switch self {
            case .auto: "Auto"
            case .high: "High"
            case .low: "Low"
            }
        }
    }

    enum SpeakToChatTimeout: UInt8, CaseIterable, Identifiable, Sendable {
        case short = 0x00, standard = 0x01, long = 0x02, never = 0x03
        var id: Self { self }
        var title: String {
            switch self {
            case .short: "15 s"
            case .standard: "30 s"
            case .long: "1 min"
            case .never: "Never"
            }
        }
    }

    enum CustomButton: UInt8, CaseIterable, Identifiable, Sendable {
        case ambientControl = 0x00, googleAssistant = 0x31, alexa = 0x32
        var id: Self { self }
        var title: String {
            switch self {
            case .ambientControl: "Ambient Sound Control"
            case .googleAssistant: "Google Assistant"
            case .alexa: "Amazon Alexa"
            }
        }
    }

    enum OptimizerState: Equatable, Sendable {
        case idle, measuringWear, measuringPressure, analyzing, finished
        var isRunning: Bool { self != .idle && self != .finished }
        var title: String {
            switch self {
            case .idle: "Ready"
            case .measuringWear: "Measuring fit…"
            case .measuringPressure: "Measuring pressure…"
            case .analyzing: "Analyzing…"
            case .finished: "Optimized"
            }
        }
    }

    struct SpeakToChatConfig: Equatable, Sendable {
        var sensitivity: SpeakToChatSensitivity
        var focusOnVoice: Bool
        var timeout: SpeakToChatTimeout
    }

    @Published private(set) var modelName: String?
    @Published private(set) var codec: String?
    @Published private(set) var dseeActive: Bool?
    @Published private(set) var dseeExtreme: Bool?
    @Published private(set) var prefersStableConnection: Bool?
    @Published private(set) var touchPanel: Bool?
    @Published private(set) var multipoint: Bool?
    @Published private(set) var pauseWhenRemoved: Bool?
    @Published private(set) var autoPowerOff: AutoPowerOff?
    @Published private(set) var speakToChat: Bool?
    @Published private(set) var speakToChatConfig: SpeakToChatConfig?
    @Published private(set) var customButton: CustomButton?
    @Published private(set) var voiceGuidance: Bool?
    @Published private(set) var isPlaying: Bool?
    @Published private(set) var track: String?
    @Published private(set) var artist: String?
    @Published private(set) var optimizer: OptimizerState = .idle
    @Published private(set) var pressureAtm: Double?

    /// Sends a payload; the Bool selects the 0x0E (table 2) message type.
    var send: (_ payload: [UInt8], _ tableTwo: Bool) -> Void = { _, _ in }

    func requestAll() {
        for request: [UInt8] in [
            [0x04, 0x01], [0x14, 0x00], [0x18, 0x00], [0xE6, 0x01], [0xE6, 0x02],
            [0xD6, 0xD1], [0xD6, 0xD2], [0xF6, 0x03], [0xF6, 0x04], [0xF6, 0x05],
            [0xFA, 0x05], [0xF6, 0x06], [0x82, 0x01], [0x86, 0x01],
        ] { send(request, false) }
        send([0x46, 0x01, 0x01], true)
        requestPlayback()
    }

    func requestPlayback() {
        send([0xA2, 0x01], false)
        send([0xA6, 0x01, 0x00], false)
        send([0xA6, 0x01, 0x02], false)
    }

    func reset() {
        modelName = nil; codec = nil; dseeActive = nil; dseeExtreme = nil
        prefersStableConnection = nil; touchPanel = nil; multipoint = nil
        pauseWhenRemoved = nil; autoPowerOff = nil; speakToChat = nil
        speakToChatConfig = nil; customButton = nil; voiceGuidance = nil
        isPlaying = nil; track = nil; artist = nil
        optimizer = .idle; pressureAtm = nil
    }

    // MARK: Setters (optimistic; the headphones confirm with a notify)

    func setDSEEExtreme(_ on: Bool) { dseeExtreme = on; send([0xE8, 0x02, 0x00, on ? 1 : 0], false) }
    func setPrefersStableConnection(_ on: Bool) {
        prefersStableConnection = on
        send([0xE8, 0x01, 0x00, on ? 1 : 0], false)
    }
    func setTouchPanel(_ on: Bool) { touchPanel = on; send([0xD8, 0xD1, 0x01, on ? 1 : 0], false) }
    func setMultipoint(_ on: Bool) { multipoint = on; send([0xD8, 0xD2, 0x01, on ? 1 : 0], false) }
    func setPauseWhenRemoved(_ on: Bool) { pauseWhenRemoved = on; send([0xF8, 0x03, 0x00, on ? 1 : 0], false) }
    func setAutoPowerOff(_ value: AutoPowerOff) { autoPowerOff = value; send([0xF8, 0x04, 0x01, value.rawValue, 0x00], false) }
    func setSpeakToChat(_ on: Bool) { speakToChat = on; send([0xF8, 0x05, 0x01, on ? 1 : 0], false) }
    func setSpeakToChatConfig(_ config: SpeakToChatConfig) {
        speakToChatConfig = config
        send([0xFC, 0x05, 0x00, config.sensitivity.rawValue, config.focusOnVoice ? 1 : 0, config.timeout.rawValue], false)
    }
    /// The headphones silently refuse an assistant that was never set up on a phone, so read back what they took.
    func setCustomButton(_ value: CustomButton) {
        customButton = value
        send([0xF8, 0x06, 0x01, value.rawValue], false)
        send([0xF6, 0x06], false)
    }
    func setVoiceGuidance(_ on: Bool) { voiceGuidance = on; send([0x48, 0x01, 0x01, on ? 1 : 0], true) }
    func startOptimizer() { optimizer = .measuringWear; send([0x84, 0x01, 0x00, 0x01], false) }
    func cancelOptimizer() { send([0x84, 0x01, 0x00, 0x00], false) }
    func powerOff() { send([0x22, 0x00, 0x01], false) }


    enum PlaybackCommand: UInt8 { case pause = 0x01, next = 0x02, previous = 0x03, play = 0x07 }
    func playback(_ command: PlaybackCommand) {
        if command == .play || command == .pause { isPlaying = command == .play }
        send([0xA4, 0x01, 0x00, command.rawValue], false)
    }

    // MARK: Parsing

    /// Returns true when the payload belonged to one of these settings.
    @discardableResult
    func handle(_ p: [UInt8], tableTwo: Bool) -> Bool {
        guard p.count >= 2 else { return false }
        if tableTwo {
            if (p[0] == 0x47 || p[0] == 0x49), p.count >= 4, p[1] == 0x01, p[2] == 0x01 {
                voiceGuidance = p[3] == 0x01
                return true
            }
            return false
        }
        switch (p[0], p[1]) {
        case (0x05, 0x01) where p.count > 3:
            modelName = String(bytes: p.dropFirst(3).prefix(Int(p[2])), encoding: .utf8)
        case (0x15, 0x00) where p.count >= 4, (0x17, 0x00) where p.count >= 4:
            dseeActive = p[3] == 0x01
        case (0x19, 0x00) where p.count >= 3, (0x1B, 0x00) where p.count >= 3:
            codec = Self.codecName(p[2])
        case (0xE7, 0x01) where p.count >= 4, (0xE9, 0x01) where p.count >= 4:
            prefersStableConnection = p[3] == 0x01
        case (0xE7, 0x02) where p.count >= 4, (0xE9, 0x02) where p.count >= 4:
            dseeExtreme = p[3] == 0x01
        case (0xD7, 0xD1) where p.count >= 4, (0xD9, 0xD1) where p.count >= 4:
            touchPanel = p[3] == 0x01
        case (0xD7, 0xD2) where p.count >= 4, (0xD9, 0xD2) where p.count >= 4:
            multipoint = p[3] == 0x01
        case (0xF7, 0x03) where p.count >= 4, (0xF9, 0x03) where p.count >= 4:
            pauseWhenRemoved = p[3] == 0x01
        case (0xF7, 0x04) where p.count >= 4, (0xF9, 0x04) where p.count >= 4:
            autoPowerOff = AutoPowerOff(rawValue: p[3])
        case (0xF7, 0x05) where p.count >= 4:
            speakToChat = p[3] == 0x01
        case (0xF9, 0x05) where p.count >= 4:
            // 01 = mode on/off; 02 = preview state, which is not a setting.
            if p[2] == 0x01 { speakToChat = p[3] == 0x01 }
        case (0xFB, 0x05) where p.count >= 6, (0xFD, 0x05) where p.count >= 6:
            speakToChatConfig = SpeakToChatConfig(
                sensitivity: SpeakToChatSensitivity(rawValue: p[3]) ?? .auto,
                focusOnVoice: p[4] == 0x01,
                timeout: SpeakToChatTimeout(rawValue: p[5]) ?? .standard
            )
        case (0xF7, 0x06) where p.count >= 4, (0xF9, 0x06) where p.count >= 4:
            customButton = CustomButton(rawValue: p[3])
        case (0xA3, 0x01) where p.count >= 4, (0xA5, 0x01) where p.count >= 4:
            if p[3] == 0x01 || p[3] == 0x02 { isPlaying = p[3] == 0x01 }
        case (0xA7, 0x01) where p.count >= 4, (0xA9, 0x01) where p.count >= 3:
            handlePlaybackParam(p)
        case (0x83, 0x01) where p.count >= 4, (0x85, 0x01) where p.count >= 4:
            optimizer = Self.optimizerState(p[3])
            if optimizer == .finished || optimizer == .idle { send([0x86, 0x01], false) }
        case (0x87, 0x01) where p.count >= 6, (0x89, 0x01) where p.count >= 6:
            pressureAtm = Double(p[5]) / 10
        default:
            return false
        }
        return true
    }

    private func handlePlaybackParam(_ p: [UInt8]) {
        let dataType = p[2]
        // 0x20 is volume; the Mac owns volume (system keys, absolute volume), so Cans ignores it.
        if dataType == 0x20 { return }
        guard p[0] == 0xA7 else {
            // Track/artist notifies carry only the type; ask for the new value.
            send([0xA6, 0x01, dataType], false)
            return
        }
        // A7 01 {type} {status} {len} {utf8}
        let text: String? = p.count > 5 && p[3] == 0x02
            ? String(bytes: p.dropFirst(5).prefix(Int(p[4])), encoding: .utf8)
            : nil
        let value = (text?.isEmpty ?? true) ? nil : text
        switch dataType {
        case 0x00: track = value
        case 0x02: artist = value
        default: break
        }
    }

    static func codecName(_ byte: UInt8) -> String? {
        switch byte {
        case 0x01: "SBC"
        case 0x02: "AAC"
        case 0x10: "LDAC"
        case 0x20: "aptX"
        case 0x21: "aptX HD"
        default: nil
        }
    }

    static func optimizerState(_ byte: UInt8) -> OptimizerState {
        switch byte {
        case 0x01: .measuringWear
        case 0x02: .measuringPressure
        case 0x10: .analyzing
        case 0x11: .finished
        default: .idle
        }
    }
}
