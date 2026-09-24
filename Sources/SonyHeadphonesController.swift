import Combine
import Foundation
import OSLog
@preconcurrency import IOBluetooth

@MainActor
final class SonyHeadphonesController: NSObject, ObservableObject {
    enum LinkState: Equatable {
        case searching, disconnected, opening, handshaking, ready, controlBusy
        case failed(String)
    }

    @Published private(set) var deviceName = "Headphones"
    @Published private(set) var address = ""
    @Published private(set) var isDeviceConnected = false
    @Published private(set) var linkState: LinkState = .searching
    @Published private(set) var noiseControlMode: NoiseControlMode?
    @Published private(set) var ambientLevel = 10
    @Published private(set) var focusOnVoice = false
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isApplyingChange = false
    @Published private(set) var equalizerPreset: EqualizerPreset?
    @Published private(set) var customEqualizer = EqualizerSettings.flat
    @Published private(set) var firmwareVersion: String?
    @Published private(set) var controlChannelID: Int?
    @Published private(set) var retrySecondsRemaining: Int?
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastErrorMessage: String?
    /// The link is open but the headphones stopped answering (seen once on an XM4 whose firmware
    /// hung mid NC-optimizer, then rebooted). Cleared by the next frame they send.
    @Published private(set) var isUnresponsive = false
    private var missedReplies = 0

    var isReady: Bool { linkState == .ready }
    var protocolDescription: String {
        "MDR \(isV1 ? "v1" : "v2")" + (controlChannelID.map { " · RFCOMM \($0)" } ?? "")
    }
    var statusText: String {
        switch linkState {
        case .searching: "Looking for your headphones…"
        case .disconnected: "Headphones disconnected"
        case .opening: "Opening Sony control link…"
        case .handshaking: "Syncing controls…"
        case .ready: isUnresponsive ? "Headphones not responding" : "Connected"
        case .controlBusy: "Control link busy"
        case .failed(let message): message
        }
    }

    var diagnosticReport: String {
        [
            "Cans diagnostics",
            "Device: \(deviceName)",
            "Address: \(address.isEmpty ? "Not found" : address)",
            "Bluetooth audio: \(isDeviceConnected ? "Connected" : "Disconnected")",
            "Sony control: \(statusText)",
            "Protocol: MDR \(isV1 ? "v1" : "v2") / RFCOMM\(controlChannelID.map { " channel \($0)" } ?? "")",
            "Firmware: \(firmwareVersion ?? "Unknown")",
            "Battery: \(batteryLevel.map { "\($0)%" } ?? "Unknown")",
            "Noise control: \(noiseControlMode?.title ?? "Unknown")",
            "Equalizer: \(equalizerPreset?.title ?? "Unknown")",
            "Last sync: \(lastSyncDate?.formatted(date: .numeric, time: .standard) ?? "Never")",
            "Last error: \(lastErrorMessage ?? "None")",
        ].joined(separator: "\n")
    }

    private enum Stage { case idle, protocolInfo, supportFunctions, noiseControl, ready }
    private static let sonyUUIDBytes: [UInt8] = [
        0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8,
        0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2,
    ]
    // WH-1000XM4 and older only expose the MDR v1 service.
    private static let sonyV1UUIDBytes: [UInt8] = [
        0x96, 0xCC, 0x20, 0x3E, 0x50, 0x68, 0x46, 0xAD,
        0xB3, 0x2D, 0xE3, 0x16, 0xF5, 0xE0, 0x69, 0xBA,
    ]
    private static let asmByFunction: [(function: UInt8, type: UInt8)] = [
        (0x6D, 0x19), (0x6B, 0x17), (0x68, 0x15), (0x67, 0x22), (0x66, 0x21),
    ]
    private static let logger = Logger(subsystem: "app.cans.mac", category: "SonyBluetooth")

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var refreshTimer: Timer?
    private var retryWorkItem: DispatchWorkItem?
    private var ambientWorkItem: DispatchWorkItem?
    private var commandTimeoutWorkItem: DispatchWorkItem?
    private var equalizerWorkItem: DispatchWorkItem?
    private var linkTimeoutWorkItem: DispatchWorkItem?
    private var openAttempt = 0
    /// False for a controller created with startAutomatically: false (previews, test hosts);
    /// such a controller must never open the link on its own.
    private var isStarted = false
    private var ackTimeoutWorkItem: DispatchWorkItem?
    /// One request in flight at a time: the next command goes out only after the previous one's
    /// reply (or a short timeout for commands the headphones don't answer). With pipelining, a late
    /// reply to an older request can overwrite fresher state. Actions run in queue order too.
    private enum Outgoing {
        case frame(payload: [UInt8], type: UInt8)
        case action(() -> Void)
    }
    private var outbox: [Outgoing] = []
    private var awaitingReply = false
    let deviceSettings = SonyDeviceSettings()
    private var stream = SonyFrameStream()
    private var stage: Stage = .idle
    private var sequence: UInt8 = 0
    private var asmType: UInt8?
    private var naExtra: [UInt8] = [0, 0]
    private var reconnectAutomatically = true
    private var isSimulated = false
    private var retryAttempt = 0
    private var nextRetryDate: Date?
    private var syncPollCount = 0
    private var isV1 = false
    private var batteryRequest: [UInt8] { isV1 ? [0x10, 0x00] : [0x22, 0x00] }
    private var equalizerType: UInt8 { isV1 ? 0x01 : 0x00 }
    private var equalizerRequest: [UInt8] { [0x56, equalizerType] }

    init(startAutomatically: Bool = true, simulatedReady: Bool = false) {
        super.init()
        deviceSettings.send = { [weak self] payload, tableTwo in
            self?.send(payload, type: tableTwo ? 0x0E : 0x0C)
        }
        #if DEBUG
        if simulatedReady {
            isSimulated = true
            address = "80:99:E7:FB:0A:59"
            isDeviceConnected = true
            linkState = .ready
            noiseControlMode = .ambient
            ambientLevel = 12
            batteryLevel = 78
            equalizerPreset = .bassBoost
            firmwareVersion = "2.5.1"
            controlChannelID = 9
            lastSyncDate = Date()
            stage = .ready
            asmType = 0x19
            return
        }
        #endif
        guard startAutomatically else {
            linkState = .disconnected
            return
        }
        isStarted = true
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func setReconnectAutomatically(_ enabled: Bool) {
        reconnectAutomatically = enabled
        guard !isSimulated, isStarted else { return }
        if enabled {
            refresh()
        } else {
            retryWorkItem?.cancel()
            retryWorkItem = nil
            nextRetryDate = nil
            retrySecondsRemaining = nil
        }
    }

    func refresh() {
        cancelScheduledRetry(resetAttempts: true)
        refresh(shouldOpenLink: true)
        requestCurrentSettings()
    }

    /// Releases Sony's control channel so the next owner (another launch, the phone) can take it at once.
    func disconnect() {
        reconnectAutomatically = false
        closeSonyLink()
    }

    func refreshEqualizer() {
        guard stage == .ready else { return }
        send(equalizerRequest)
    }

    private func poll() {
        updateRetryCountdown()
        refresh(shouldOpenLink: reconnectAutomatically)
        guard stage == .ready else { return }
        syncPollCount += 1
        if syncPollCount >= 5 {
            syncPollCount = 0
            requestCurrentSettings()
        }
    }

    /// Forgets everything the headphones reported and asks for all of it again, so what the UI
    /// shows afterwards is provably what the headphones hold (used by Sync now and the hardware E2E suite).
    func reloadFromDevice(completion: (() -> Void)? = nil) {
        guard stage == .ready, let asmType else { completion?(); return }
        enqueue { [weak self] in
            self?.noiseControlMode = nil
            self?.equalizerPreset = nil
            self?.batteryLevel = nil
            self?.deviceSettings.reset()
        }
        send([0x66, asmType])
        send(batteryRequest)
        send(equalizerRequest)
        if isV1 { deviceSettings.requestAll() }
        if let completion { enqueue(completion) }
    }

    private func requestCurrentSettings() {
        guard stage == .ready, let asmType else { return }
        send([0x66, asmType])
        send(batteryRequest)
        send(equalizerRequest)
        if firmwareVersion == nil { send([0x04, 0x02]) }
    }

    private func refresh(shouldOpenLink: Bool) {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard let match = paired.first(where: {
            let name = $0.name ?? ""
            return name.localizedCaseInsensitiveContains("1000XM5") || name.localizedCaseInsensitiveContains("1000XM4")
        }) else {
            closeSonyLink()
            device = nil
            address = ""
            isDeviceConnected = false
            linkState = .failed("Pair your Sony WH-1000XM4 or XM5 in System Settings")
            return
        }
        device = match
        deviceName = match.name ?? "Sony headphones"
        #if DEBUG
        // Capture aid: --demo-name=… keeps a personal device name out of recordings.
        if let name = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-name=") }) {
            deviceName = String(name.dropFirst("--demo-name=".count))
        }
        #endif
        address = match.addressString ?? ""
        isDeviceConnected = match.isConnected()
        guard isDeviceConnected else {
            closeSonyLink()
            linkState = .disconnected
            return
        }
        if shouldOpenLink, channel == nil, stage == .idle {
            guard nextRetryDate.map({ $0 <= Date() }) ?? true else { return }
            nextRetryDate = nil
            retrySecondsRemaining = nil
            openSonyLink()
        }
    }

    func connect() {
        cancelScheduledRetry(resetAttempts: true)
        guard let device else {
            refresh()
            return
        }
        linkState = .opening
        let result = device.openConnection()
        isDeviceConnected = device.isConnected()
        if result != kIOReturnSuccess, !isDeviceConnected {
            fail("Headphones did not respond. Make sure they are powered on.")
            return
        }
        stage = .idle
        refresh()
    }

    func setNoiseControl(_ mode: NoiseControlMode) {
        sendNoiseControl(mode)
    }

    func toggleNoiseControl() {
        guard isReady else { return }
        sendNoiseControl(noiseControlMode == .anc ? .ambient : .anc)
    }

    func setEqualizerPreset(_ preset: EqualizerPreset) {
        guard stage == .ready else { return }
        equalizerWorkItem?.cancel()
        beginApplyingChange()
        send([0x58, equalizerType, preset.rawValue, 0x00])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            Task { @MainActor in guard let self else { return }; self.send(self.equalizerRequest) }
        }
    }

    func setCustomEqualizer(_ settings: EqualizerSettings) {
        guard stage == .ready else { return }
        customEqualizer = settings
        equalizerPreset = .manual
        equalizerWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.beginApplyingChange()
                var payload = settings.sonySetPayload
                payload[1] = self.equalizerType
                // Verified on a WH-1000XM4: it ignores A0 in a set and only takes FF for a custom curve.
                if self.isV1 { payload[2] = 0xFF }
                self.send(payload)
            }
        }
        equalizerWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    func applyPreset(mode: NoiseControlMode, ambientLevel level: Int, focusOnVoice focus: Bool) {
        ambientWorkItem?.cancel()
        ambientLevel = max(1, min(20, level))
        focusOnVoice = focus
        sendNoiseControl(mode)
    }

    private func sendNoiseControl(_ mode: NoiseControlMode) {
        if isSimulated {
            noiseControlMode = mode
            return
        }
        guard stage == .ready, let asmType else { return }
        if isV1 {
            beginApplyingChange()
            send([0x68, 0x02, mode == .off ? 0x00 : 0x11, 0x02, mode == .anc ? 0x02 : 0x00, 0x01,
                  focusOnVoice ? 1 : 0, UInt8(max(1, min(20, ambientLevel)))])
            return
        }
        let noNoiseCancelling = asmType == 0x21 || asmType == 0x22
        let hasWindMode = asmType == 0x15
        let hasExtraAmbientFields = asmType == 0x19
        var payload: [UInt8] = [0x68, asmType, 0x01, mode == .off ? 0x00 : 0x01]
        if !noNoiseCancelling { payload.append(mode == .ambient ? 0x01 : 0x00) }
        if hasWindMode { payload.append(mode == .wind ? 0x03 : 0x02) }
        payload += [focusOnVoice ? 1 : 0, UInt8(max(1, min(20, ambientLevel)))]
        if hasExtraAmbientFields { payload += naExtra }
        beginApplyingChange()
        send(payload)
    }

    func setAmbientLevel(_ level: Int) {
        ambientLevel = max(1, min(20, level))
        ambientWorkItem?.cancel()
        guard noiseControlMode == .ambient else { return }
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.sendNoiseControl(.ambient) }
        }
        ambientWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    func setFocusOnVoice(_ enabled: Bool) {
        focusOnVoice = enabled
        if noiseControlMode == .ambient { sendNoiseControl(.ambient) }
    }

    private func beginApplyingChange() {
        isApplyingChange = true
        commandTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.isApplyingChange = false }
        }
        commandTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func openSonyLink() {
        guard let device else { return }
        stage = .protocolInfo
        linkState = .opening
        func record(_ bytes: [UInt8]) -> IOBluetoothSDPServiceRecord? {
            device.getServiceRecord(for: bytes.withUnsafeBytes {
                IOBluetoothSDPUUID(bytes: $0.baseAddress!, length: bytes.count)
            })
        }
        let v2Record = record(Self.sonyUUIDBytes)
        isV1 = v2Record == nil
        guard let record = v2Record ?? record(Self.sonyV1UUIDBytes) else {
            fail("Sony control service is unavailable")
            return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            fail("Could not resolve Sony control channel")
            return
        }
        var openedChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&openedChannel, withChannelID: channelID, delegate: self)
        channel = openedChannel
        guard result == kIOReturnSuccess else {
            handleOpenFailure(result)
            return
        }
        controlChannelID = Int(channelID)
        Self.logger.info("Opening RFCOMM channel \(channelID) [controller \(UInt(bitPattern: ObjectIdentifier(self).hashValue) & 0xFFFF, privacy: .public)]")
        // bluetoothd can refuse the open (e.g. another process owns the channel) without calling back.
        openAttempt &+= 1
        let attempt = openAttempt
        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.openAttempt == attempt, self.stage != .ready, self.stage != .idle else { return }
                self.handleOpenFailure(kIOReturnTimeout)
            }
        }
        linkTimeoutWorkItem?.cancel()
        linkTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 11, execute: timeout)
    }

    private func closeSonyLink() {
        cancelScheduledRetry(resetAttempts: true)
        deviceSettings.reset()
        channel?.close()
        channel = nil
        stage = .idle
        asmType = nil
        noiseControlMode = nil
        batteryLevel = nil
        isCharging = false
        isApplyingChange = false
        equalizerPreset = nil
        firmwareVersion = nil
        controlChannelID = nil
        equalizerWorkItem?.cancel()
        equalizerWorkItem = nil
    }

    private func beginHandshake() {
        missedReplies = 0
        isUnresponsive = false
        sequence = 0
        outbox.removeAll()
        awaitingReply = false
        stream = SonyFrameStream()
        stage = .protocolInfo
        linkState = .handshaking
        sendHandshake(attempt: 0)
    }

    /// Right after a reconnect the headphones often ignore the first init for a few seconds
    /// (verified on a WH-1000XM4), so keep knocking instead of waiting out the link timeout.
    private func sendHandshake(attempt: Int) {
        guard stage == .protocolInfo, channel != nil, attempt < 8 else { return }
        if attempt > 0 {
            sequence = 0
            outbox.removeAll()
            awaitingReply = false
        }
        send([0x00, 0x00])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            Task { @MainActor in self?.sendHandshake(attempt: attempt + 1) }
        }
    }

    private func send(_ payload: [UInt8], type: UInt8 = 0x0C) {
        guard channel != nil else { return }
        outbox.append(.frame(payload: payload, type: type))
        pumpOutbox()
    }

    /// Runs `action` once every request queued before it has been answered.
    private func enqueue(_ action: @escaping () -> Void) {
        outbox.append(.action(action))
        pumpOutbox()
    }

    private func pumpOutbox() {
        while !awaitingReply, !outbox.isEmpty {
            switch outbox.removeFirst() {
            case .action(let action):
                action()
            case .frame(let payload, let type):
                awaitingReply = true
                Self.logger.debug(">> \(String(format: "%02X", type), privacy: .public) \(payload.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
                write(payload, type: type, sequence: sequence)
                let timeout = DispatchWorkItem { [weak self] in
                    Task { @MainActor in self?.replyTimedOut() }
                }
                ackTimeoutWorkItem?.cancel()
                ackTimeoutWorkItem = timeout
                // Some replies take ~0.6s right after a write; unanswered commands just cost this wait.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timeout)
            }
        }
    }

    /// Every frame is ACKed, so three silent requests in a row means the headphones stopped listening.
    private func replyTimedOut() {
        guard awaitingReply else { return }
        missedReplies += 1
        if missedReplies >= 3, stage == .ready, !isUnresponsive { isUnresponsive = true }
        replyReceived()
    }

    private func replyReceived() {
        guard awaitingReply else { return }
        ackTimeoutWorkItem?.cancel()
        awaitingReply = false
        pumpOutbox()
    }

    private func write(_ payload: [UInt8], type: UInt8, sequence frameSequence: UInt8) {
        guard let channel else { return }
        let data = SonyFrameCodec.encode(type: type, sequence: frameSequence, payload: payload)
        let result = data.withUnsafeBytes { bytes -> IOReturn in
            guard let baseAddress = bytes.baseAddress else { return kIOReturnBadArgument }
            return channel.writeSync(UnsafeMutableRawPointer(mutating: baseAddress), length: UInt16(data.count))
        }
        if result != kIOReturnSuccess { fail("Could not send to headphones (\(result))") }
    }

    private func receive(_ data: Data) {
        for frame in stream.append(data) {
            missedReplies = 0
            if isUnresponsive { isUnresponsive = false }
            Self.logger.debug("<< \(String(format: "%02X", frame.type), privacy: .public) \(frame.payload.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
            if frame.type == 0x01 {
                // The ACK carries the sequence number the headphones expect next. Following it (not
                // toggling locally) keeps a lost ACK from making later commands look like retransmissions.
                sequence = frame.sequence
                continue
            }
            if frame.type == 0x0C || frame.type == 0x0E {
                write([], type: 0x01, sequence: 1 - frame.sequence)
            }
            guard !frame.payload.isEmpty else { continue }
            defer { replyReceived() }
            if frame.type == 0x0C {
                dispatch(frame.payload)
            } else if frame.type == 0x0E, isV1 {
                deviceSettings.handle(frame.payload, tableTwo: true)
            }
        }
    }

    private func dispatch(_ payload: [UInt8]) {
        switch (payload[0], stage) {
        case (0x01, .protocolInfo) where isV1:
            asmType = 0x02
            stage = .noiseControl
            send([0x66, 0x02])
        case (0x01, .protocolInfo):
            stage = .supportFunctions
            send([0x06, 0x00])
        case (0x07, .supportFunctions):
            let count = payload.count > 2 ? Int(payload[2]) : 0
            let functions = Set((0..<count).compactMap { index -> UInt8? in
                let position = 3 + index * 2
                return position < payload.count ? payload[position] : nil
            })
            guard let supported = Self.asmByFunction.first(where: { functions.contains($0.function) }) else {
                fail("These headphones did not report ANC support")
                return
            }
            asmType = supported.type
            stage = .noiseControl
            send([0x66, supported.type])
        case (0x67, _), (0x69, _):
            parseNoiseControl(payload)
        case (0x11, _) where isV1, (0x13, _) where isV1, (0x23, _) where !isV1, (0x25, _) where !isV1:
            parseBattery(payload)
        case (0x57, _), (0x59, _):
            parseEqualizer(payload)
        case (0x05, _) where payload.count > 1 && payload[1] == 0x02:
            parseFirmware(payload)
        default:
            if isV1 { deviceSettings.handle(payload, tableTwo: false) }
        }
    }

    private func parseNoiseControl(_ payload: [UInt8]) {
        guard let asmType, (6...9).contains(payload.count), payload[1] == asmType else { return }
        if isV1 {
            // v1 layout: 67 02 <on> <setting type> <nc: 02, ambient: 00> <asm type> <voice> <level>
            guard payload.count == 8 else { return }
            focusOnVoice = payload[6] == 0x01
            ambientLevel = min(20, Int(payload[7]))
            markNoiseControlSynced(payload[2] == 0x00 ? .off : payload[4] == 0x00 ? .ambient : .anc)
            return
        }
        let noNoiseCancelling = asmType == 0x21 || asmType == 0x22
        let hasWindMode = asmType == 0x15
        let hasExtraAmbientFields = asmType == 0x19
        let mode: NoiseControlMode
        if payload[3] == 0x00 {
            mode = .off
        } else if hasWindMode, payload.count > 5, payload[5] == 0x03 || payload[5] == 0x05 {
            mode = .wind
        } else if noNoiseCancelling {
            mode = .ambient
        } else {
            mode = payload[4] == 0x00 ? .anc : .ambient
        }
        let index = payload.count - (hasExtraAmbientFields ? 4 : 2)
        focusOnVoice = payload[index] == 0x01
        let level = Int(payload[index + 1])
        ambientLevel = (0...20).contains(level) ? level : 10
        if hasExtraAmbientFields { naExtra = [payload[index + 2], payload[index + 3]] }
        markNoiseControlSynced(mode)
    }

    private func markNoiseControlSynced(_ mode: NoiseControlMode) {
        linkTimeoutWorkItem?.cancel()
        linkTimeoutWorkItem = nil
        noiseControlMode = mode
        stage = .ready
        linkState = .ready
        isApplyingChange = false
        commandTimeoutWorkItem?.cancel()
        commandTimeoutWorkItem = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryAttempt = 0
        nextRetryDate = nil
        retrySecondsRemaining = nil
        lastErrorMessage = nil
        lastSyncDate = Date()
        Self.logger.info("Noise control synced; mode=\(mode.rawValue, privacy: .public)")
        if batteryLevel == nil { send(batteryRequest) }
        if equalizerPreset == nil { send(equalizerRequest) }
        if firmwareVersion == nil { send([0x04, 0x02]) }
        if isV1, deviceSettings.modelName == nil { deviceSettings.requestAll() }
    }

    private func parseBattery(_ payload: [UInt8]) {
        guard payload.count >= 4, payload[1] == 0x00 else { return }
        let level = Int(payload[2])
        guard (0...100).contains(level) else { return }
        batteryLevel = level
        isCharging = payload[3] == 0x01
        lastSyncDate = Date()
        Self.logger.info("Battery ready; level=\(level, privacy: .public)")
    }

    private func parseEqualizer(_ payload: [UInt8]) {
        guard payload.count >= 3, payload[1] == equalizerType else { return }
        equalizerPreset = EqualizerPreset(rawValue: payload[2])
        var normalized = payload
        normalized[1] = 0x00
        if let settings = EqualizerSettings(sonyPayload: normalized) {
            customEqualizer = settings
        }
        lastSyncDate = Date()
        isApplyingChange = false
        commandTimeoutWorkItem?.cancel()
        commandTimeoutWorkItem = nil
        if let equalizerPreset {
            Self.logger.info("Equalizer ready; preset=\(equalizerPreset.title, privacy: .public)")
        }
    }

    private func fail(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
        channel?.close()
        channel = nil
        stage = .idle
        linkState = .failed(message)
        lastErrorMessage = message
        isApplyingChange = false
        scheduleRetry()
    }

    private func handleOpenFailure(_ error: IOReturn) {
        let message = "Sony control channel is busy (\(error))"
        Self.logger.error("\(message, privacy: .public)")
        channel?.close()
        channel = nil
        stage = .idle
        linkState = .controlBusy
        lastErrorMessage = message
        scheduleRetry()
    }

    private func scheduleRetry() {
        retryWorkItem?.cancel()
        guard reconnectAutomatically, isDeviceConnected else {
            nextRetryDate = nil
            retrySecondsRemaining = nil
            return
        }
        let delay = ReconnectBackoff.delay(forAttempt: retryAttempt)
        retryAttempt += 1
        nextRetryDate = Date().addingTimeInterval(delay)
        retrySecondsRemaining = Int(delay.rounded(.up))
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.retryWorkItem = nil
                self.nextRetryDate = nil
                self.retrySecondsRemaining = nil
                self.refresh(shouldOpenLink: true)
            }
        }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelScheduledRetry(resetAttempts: Bool) {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        nextRetryDate = nil
        retrySecondsRemaining = nil
        if resetAttempts { retryAttempt = 0 }
    }

    private func updateRetryCountdown() {
        guard let nextRetryDate else {
            retrySecondsRemaining = nil
            return
        }
        retrySecondsRemaining = max(0, Int(nextRetryDate.timeIntervalSinceNow.rounded(.up)))
    }

    private func parseFirmware(_ payload: [UInt8]) {
        guard payload.count > 2, payload[1] == 0x02 else { return }
        let value = String(bytes: payload.dropFirst(2), encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
        guard let value, !value.isEmpty else { return }
        firmwareVersion = value
        lastSyncDate = Date()
        Self.logger.info("Firmware ready; version=\(value, privacy: .public)")
    }

    @objc nonisolated
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel, status error: IOReturn) {
        Task { @MainActor in
            guard error == kIOReturnSuccess else {
                handleOpenFailure(error)
                return
            }
            channel = rfcommChannel
            beginHandshake()
        }
    }

    @objc nonisolated
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel, data dataPointer: UnsafeMutableRawPointer, length dataLength: Int) {
        let copied = Data(bytes: dataPointer, count: dataLength)
        Task { @MainActor in receive(copied) }
    }

    @objc nonisolated
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        Task { @MainActor in
            guard channel === rfcommChannel else { return }
            channel = nil
            stage = .idle
            noiseControlMode = nil
            if isDeviceConnected {
                linkState = .controlBusy
                lastErrorMessage = "Sony control link closed while Bluetooth audio remained connected"
                scheduleRetry()
            } else {
                linkState = .disconnected
            }
        }
    }
}
