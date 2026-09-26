import AppKit
import SwiftUI

/// Ambient recalls. (Noise cancelling has its own NC key, so no scene duplicates it.)
private enum Scene: String, CaseIterable, Identifiable {
    case office, aware

    var id: Self { self }
    var title: String { rawValue }
    var level: Int { self == .office ? 8 : 20 }
    var focusOnVoice: Bool { self == .office }
    var help: String { self == .office ? "Ambient 8 with Focus on Voice" : "Ambient 20, full awareness" }
}

private enum PanelScreen { case dashboard, inserts }

private enum InsertSection: String, CaseIterable, Identifiable {
    case headphones, speakToChat, noiseCancelling, sound, controls, app, diagnostics
    var id: Self { self }
    var title: String {
        switch self {
        case .headphones: "Headphones"
        case .speakToChat: "Speak-to-Chat"
        case .noiseCancelling: "NC Optimizer"
        case .sound: "Sound"
        case .controls: "Controls"
        case .app: "App"
        case .diagnostics: "Diagnostics"
        }
    }
    var summary: String {
        switch self {
        case .headphones: "What's connected, straight from the headphones."
        case .speakToChat: "Talk to someone without taking your headphones off."
        case .noiseCancelling: "Fit noise cancelling to you and the air around you."
        case .sound: "Upscaling and how Bluetooth trades quality for stability."
        case .controls: "Buttons, touch, sensors and power."
        case .app: "How Cans behaves on this Mac."
        case .diagnostics: "The control link, for troubleshooting."
        }
    }
    var symbol: String {
        switch self {
        case .headphones: "headphones"
        case .speakToChat: "bubble.left.and.bubble.right"
        case .noiseCancelling: "waveform.path.ecg"
        case .sound: "hifispeaker"
        case .controls: "hand.tap"
        case .app: "menubar.rectangle"
        case .diagnostics: "stethoscope"
        }
    }
}

enum MenuBarMetrics {
    static let width: CGFloat = 660
    static let insertsHeight: CGFloat = 420
    static let displaySize = CGSize(width: width, height: 470)
    static let inset: CGFloat = 20
}

struct MenuBarView: View {
    var onSizeChange: ((CGSize) -> Void)? = nil
    @EnvironmentObject private var headphones: SonyHeadphonesController
    @EnvironmentObject private var device: SonyDeviceSettings
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var updates = Updates.shared
    @StateObject private var nowPlaying = NowPlaying()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: PanelScreen = .dashboard
    @State private var contentHeight: CGFloat = 330
    @State private var section: InsertSection = CommandLine.arguments
        .first { $0.hasPrefix("--section=") }
        .flatMap { InsertSection(rawValue: String($0.dropFirst("--section=".count))) } ?? .headphones
    @State private var savingProfile = false
    @State private var profileName = ""
    @State private var confirmingMultipoint = false
    @State private var powerOffArmed = false
    @State private var celebratingFullCharge = false

    private var panelHeight: CGFloat {
        // Inserts matches the dashboard so the popover never jumps size between screens.
        screen == .inserts ? max(contentHeight, MenuBarMetrics.insertsHeight) : contentHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            Console.panel.ignoresSafeArea()
            if screen == .dashboard {
                dashboard
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    .transition(slide(.leading))
            } else {
                inserts.transition(slide(.trailing))
            }
        }
        .frame(width: MenuBarMetrics.width, height: panelHeight, alignment: .top)
        .clipped()
        .onChange(of: panelHeight, initial: true) { _, height in
            onSizeChange?(CGSize(width: MenuBarMetrics.width, height: height))
        }
        .tint(Console.amber)
        .alert("Save EQ as", isPresented: $savingProfile) {
            TextField("Name", text: $profileName)
            Button("Save") {
                settings.customEqualizerDraft = headphones.customEqualizer
                settings.saveEqualizerProfile(named: profileName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved on this Mac. Choosing it later sends the curve to your headphones.")
        }
        .alert("Turn multipoint \(device.multipoint == true ? "off" : "on")?", isPresented: $confirmingMultipoint) {
            Button("Change") { device.setMultipoint(!(device.multipoint ?? false)) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your headphones may restart and briefly disconnect. With multipoint on, LDAC is unavailable.")
        }
        // .contain keeps this container's identifier from overriding every child's identifier.
        .accessibilityElement(children: .contain)
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { _ in nowPlaying.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in nowPlaying.stop() }
        .onAppear {
            if CommandLine.arguments.contains("--ui-test-host") { nowPlaying.start() }
            #if DEBUG
            // Capture aids: --demo-mode=ambient|anc|off switches the headphones once linked;
            // --show-inserts shows the dashboard first (so its height is measured), then Inserts.
            if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-mode=") }) {
                let mode: NoiseControlMode = arg.hasSuffix("ambient") ? .ambient : arg.hasSuffix("off") ? .off : .anc
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    headphones.applyPreset(mode: mode, ambientLevel: 14, focusOnVoice: false)
                }
            }
            #endif
        }
        .onChange(of: headphones.isReady) { _, ready in
            #if DEBUG
            // Capture aid: once linked (dashboard measured), open Inserts.
            if ready, CommandLine.arguments.contains("--show-inserts") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { navigate(to: .inserts) }
            }
            if ready, CommandLine.arguments.contains("--demo-tour") { runDemoTour() }
            #endif
        }
        .accessibilityIdentifier(screen == .dashboard ? "headphones.dashboard" : "settings.inline")
    }

    // MARK: Dashboard

    private var dashboard: some View {
        VStack(spacing: 0) {
            stripHeader
                .padding(.bottom, 10)
            if headphones.isReady {
                // Top deck: the channel on the left, its switches on the right.
                HStack(alignment: .center, spacing: 0) {
                    HStack(alignment: .center, spacing: 14) {
                        ChannelPortrait(modelName: device.modelName ?? headphones.deviceName,
                                        mode: headphones.noiseControlMode, ambientLevel: headphones.ambientLevel)
                        meterBridge
                    }
                    .frame(width: 300, alignment: .leading)
                    Rectangle().fill(Console.groove).frame(width: 1).padding(.horizontal, 18)
                    VStack(alignment: .leading, spacing: 14) {
                        inputSelector
                        sceneRecall
                        if device.isPlaying != nil || nowPlaying.track != nil { transport }
                    }
                    .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                seam
                faderBank
            } else {
                noSignal
            }
        }
        .padding(.horizontal, MenuBarMetrics.inset)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var seam: some View {
        Rectangle().fill(Console.groove).frame(height: 1)
            .overlay(alignment: .bottom) { Rectangle().fill(Console.seam).frame(height: 1).offset(y: 1) }
            .padding(.vertical, 10)
    }

    private var stripHeader: some View {
        HStack(spacing: 8) {
            ScribbleTape(text: headphones.deviceName, size: 13)
                .help(Self.isSmallHours ? "Still up? Your ears could use a rest." : headphones.deviceName)
                .accessibilityIdentifier("menu.title")
            linkLamp
            Spacer(minLength: 4)
            Button { navigate(to: .inserts) } label: {
                HStack(spacing: 6) {
                    if updates.availableVersion != nil { UpdatePip() }
                    Legend("Inserts", size: 10.5, color: Console.legend)
                }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Console.raised, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Console.seam, lineWidth: 0.75))
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityIdentifier("inserts.open")
            .help(updates.availableVersion.map { "Cans \($0) is ready to install (⌘,)" } ?? "Headphone and app settings (⌘,)")
            .accessibilityLabel("Inserts")
            .accessibilityValue(updates.availableVersion.map { "Update available: Cans \($0)" } ?? "")
        }
    }

    private static var isSmallHours: Bool { (2...4).contains(Calendar.current.component(.hour, from: Date())) }

    private var linkLamp: some View {
        let live = headphones.isReady && !headphones.isUnresponsive
        return HStack(spacing: 5) {
            Circle()
                .fill(live ? Console.signal : Console.unlit)
                .frame(width: 6, height: 6)
                .shadow(color: live ? Console.signal.opacity(0.7) : .clear, radius: 4)
            Legend(live ? "Live" : linkLegend, size: 10.5, color: live ? Console.legend : Console.dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headphones.statusText)
    }

    private var linkLegend: String {
        if headphones.isReady { return "No reply" }
        return switch headphones.linkState {
        case .opening, .handshaking: "Linking"
        case .controlBusy: "Busy"
        case .failed: "Fault"
        default: "Off"
        }
    }

    private var meterBridge: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(device.modelName ?? "Sony headphones")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Console.legend)
            Text(headphones.firmwareVersion.map { "Firmware \($0)" } ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(Console.dim)
            if let battery = headphones.batteryLevel {
                HStack(spacing: 7) {
                    Legend(headphones.isCharging ? "Chg" : "Batt", size: 10.5)
                    LEDLadder(fraction: Double(battery) / 100, tint: battery <= 20 ? Console.alarm : Console.amber,
                              chasing: celebratingFullCharge)
                        .onChange(of: battery) { old, new in
                            if new == 100, old < 100, headphones.isCharging {
                                celebratingFullCharge = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { celebratingFullCharge = false }
                            }
                        }
                    Text("\(battery)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(battery <= 20 ? Console.alarmInk : Console.legend)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery \(battery) percent\(headphones.isCharging ? ", charging" : "")")
            }
            HStack(spacing: 6) {
                if let codec = device.codec { badge(codec, lit: false, help: "Bluetooth codec in use") }
                if let dsee = device.dseeActive { badge("DSEE", lit: dsee, help: dsee ? "DSEE Extreme is upscaling" : "DSEE Extreme idle") }
                if headphones.isApplyingChange {
                    LEDLadder(fraction: 0, segments: 4, segmentSize: CGSize(width: 4, height: 7), chasing: true)
                        .accessibilityLabel("Applying setting")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(_ text: String, lit: Bool, help: String) -> some View {
        Legend(text, size: 10.5, color: lit ? Console.amberInk : Console.dim)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(lit ? Console.amber.opacity(0.6) : Console.seam, lineWidth: 0.75))
            .help(help)
            .accessibilityLabel(help)
    }

    private var inputSelector: some View {
        VStack(alignment: .leading, spacing: 7) {
            Legend("Noise control", size: 10.5)
            HStack(spacing: 6) {
                modeButton(.off, "Off", key: "1")
                modeButton(.anc, "NC", key: "2")
                modeButton(.ambient, "Amb", key: "3")
            }
        }
    }

    private func modeButton(_ mode: NoiseControlMode, _ title: String, key: KeyEquivalent) -> some View {
        LampButton(title: title, lit: headphones.noiseControlMode == mode, height: 34, fontSize: 12.5) {
            headphones.setNoiseControl(mode)
        }
        .keyboardShortcut(key, modifiers: [])
        .help("\(mode.title) (\(String(key.character)))")
        .accessibilityLabel(mode.title)
        .accessibilityIdentifier("noiseControl.\(mode.rawValue)")
    }

    private var faderBank: some View {
        let eq = headphones.customEqualizer
        let ambientOn = headphones.noiseControlMode == .ambient
        return VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                Fader(label: "Ambient sound level", accessibilityName: "Ambient level",
                      value: max(1, headphones.ambientLevel), range: 1...20, ticks: [1, 5, 10, 15, 20],
                      enabled: ambientOn, tapeLabel: "Amb") { headphones.setAmbientLevel($0) }
                Rectangle().fill(Console.groove).frame(width: 1, height: 132).padding(.horizontal, 6)
                Fader(label: "Clear Bass", accessibilityName: "Clear Bass", value: eq.clearBass, range: -10...10,
                      ticks: [-10, -5, 0, 5, 10], enabled: eqEnabled, resetValue: 0, format: signed,
                      tapeLabel: "CB", dimValue: eqOff) {
                    var next = eq
                    next.clearBass = $0
                    headphones.setCustomEqualizer(next)
                }
                ForEach(0..<5, id: \.self) { band in
                    Fader(label: EqualizerSettings.bandLabels[band], accessibilityName: "\(EqualizerSettings.bandLabels[band]) band",
                          value: eq[band: band], range: -10...10, ticks: [-10, -5, 0, 5, 10],
                          enabled: eqEnabled, resetValue: 0, format: signed,
                          tapeLabel: ["400", "1K", "2.5K", "6.3K", "16K"][band], dimValue: eqOff) {
                        var next = eq
                        next[band: band] = $0
                        headphones.setCustomEqualizer(next)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            // One continuous scribble strip runs under the bank; each fader writes its own label on it.
            .background(alignment: .bottom) {
                Console.tape.frame(height: 18).clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Console.tapeEdge, lineWidth: 0.75))
            }

            HStack(spacing: 6) {
                LampButton(title: "Voice", lit: ambientOn && headphones.focusOnVoice, enabled: ambientOn, height: 24, fontSize: 10.5) {
                    headphones.setFocusOnVoice(!headphones.focusOnVoice)
                }
                // Exactly one fader column wide, so it sits centred under AMB.
                .frame(width: (MenuBarMetrics.width - 2 * MenuBarMetrics.inset - 13) / 7)
                .help("Focus on Voice")
                .accessibilityLabel("Focus on Voice")
                .accessibilityValue(headphones.focusOnVoice ? "On" : "Off")
                Spacer()
                Legend("EQ", size: 10.5)
                equalizerMenu
            }
        }
    }

    private var eqEnabled: Bool { headphones.equalizerPreset != nil }
    private var eqOff: Bool { headphones.equalizerPreset == .off }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    private var equalizerMenu: some View {
        Menu {
            ForEach(EqualizerPreset.selectableCases(customSlots: headphones.isV1)) { preset in
                // A Toggle gets the native menu checkmark; a Label's icon isn't drawn in macOS menus.
                Toggle(preset.title, isOn: Binding(
                    get: { headphones.equalizerPreset == preset },
                    set: { _ in headphones.setEqualizerPreset(preset) }))
            }
            if !settings.equalizerProfiles.isEmpty {
                Divider()
                ForEach(settings.equalizerProfiles) { profile in
                    Button(profile.name) {
                        settings.customEqualizerDraft = profile.settings
                        headphones.setCustomEqualizer(profile.settings)
                    }
                }
                Menu("Delete Saved") {
                    ForEach(settings.equalizerProfiles) { profile in
                        Button(profile.name, role: .destructive) { settings.deleteEqualizerProfile(id: profile.id) }
                    }
                }
            }
            Divider()
            Button("Save Current Curve…") {
                profileName = ""
                savingProfile = true
            }
        } label: {
            Text((headphones.equalizerPreset?.title ?? "—").uppercased())
                .font(Console.legendFont(10.5, weight: .bold))
                .foregroundStyle(eqOff ? Console.dim : Console.amberInk)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.trailing, -5)  // the borderless indicator carries built-in trailing space; land on the edge
        .disabled(!eqEnabled)
        .help("Equalizer preset. Moving a band fader switches to Manual.")
        .accessibilityLabel("Equalizer preset")
        .accessibilityValue(headphones.equalizerPreset?.title ?? "Unavailable")
        .accessibilityIdentifier("equalizer.preset")
    }

    private var sceneRecall: some View {
        VStack(alignment: .leading, spacing: 7) {
            Legend("Scene", size: 10.5)
            HStack(spacing: 6) {
            ForEach(Scene.allCases) { scene in
                LampButton(title: scene.title, lit: isSceneActive(scene), height: 26, fontSize: 10.5) {
                    headphones.applyPreset(mode: .ambient, ambientLevel: scene.level, focusOnVoice: scene.focusOnVoice)
                }
                .help(scene.help)
            }
            }
        }
    }

    private func isSceneActive(_ scene: Scene) -> Bool {
        guard headphones.noiseControlMode == .ambient else { return false }
        return headphones.ambientLevel == scene.level && headphones.focusOnVoice == scene.focusOnVoice
    }

    /// One recessed transport module: source, track and controls on a shared centre line.
    /// Track info comes from macOS Now Playing (any app); the headphones only know the play state.
    private var transport: some View {
        let track = nowPlaying.track
        let playing = track?.isPlaying ?? (device.isPlaying == true)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Legend(track?.appName ?? "Now playing", size: 10)
                Text(track?.title ?? "Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(track == nil ? Console.dim : Console.legend)
                    .lineLimit(1)
                Text(track?.artist ?? " ")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Console.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            HStack(spacing: 6) {
                transportKey("backward.fill", "Previous track") {
                    track != nil ? nowPlaying.perform("previous") : device.playback(.previous)
                }
                Button {
                    track != nil ? nowPlaying.perform("playpause") : device.playback(playing ? .pause : .play)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(playing ? Console.tapeInk : Console.legend)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(playing ? Console.amber : Console.raised)
                            .shadow(color: playing ? Console.glow : .black.opacity(0.35), radius: playing ? 6 : 1.5, y: playing ? 0 : 1))
                        .overlay(Circle().strokeBorder(Console.seam, lineWidth: 0.75))
                }
                .buttonStyle(PressStyle())
                .keyboardShortcut(.space, modifiers: [])
                .help(playing ? "Pause" : "Play")
                .accessibilityLabel(playing ? "Pause" : "Play")
                transportKey("forward.fill", "Next track") {
                    track != nil ? nowPlaying.perform("next") : device.playback(.next)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 58)
        .background(Console.groove.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Console.seam, lineWidth: 0.75))
    }

    private func transportKey(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Console.legend)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private var isLinking: Bool { headphones.linkState == .opening || headphones.linkState == .handshaking }

    private var noSignal: some View {
        VStack(spacing: 14) {
            if headphones.address.isEmpty == false {
                ChannelPortrait(modelName: headphones.deviceName, mode: .off, ambientLevel: 0)
                    .opacity(0.55)
            }
            LEDLadder(fraction: 0, segments: 14, chasing: isLinking)
                .padding(.top, 24)
            Text(noSignalTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Console.legend)
            Text(noSignalGuidance)
                .font(.system(size: 11.5))
                .foregroundStyle(Console.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !isLinking {
                LampButton(title: "Connect", lit: true, height: 34, fontSize: 12) {
                    headphones.isDeviceConnected ? headphones.refresh() : headphones.connect()
                }
                .accessibilityIdentifier("headphones.connect")
            }
            HStack {
                Button("Bluetooth Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                if let seconds = headphones.retrySecondsRemaining {
                    Text("Retrying in \(seconds)s").monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Console.dim)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .accessibilityIdentifier("headphones.connection")
    }

    private var noSignalTitle: String {
        switch headphones.linkState {
        case .opening, .handshaking: "Linking to your headphones"
        case .controlBusy: "Audio connected, controls busy"
        case .failed: "Couldn't reach the headphones"
        default: "No signal"
        }
    }

    private var noSignalGuidance: String {
        switch headphones.linkState {
        case .opening, .handshaking: "Keep them on and nearby."
        case .controlBusy: "Another app holds Sony's control channel. Close Sound Connect on your phone; Cans retries on its own."
        case .failed(let message): message
        default: "Turn on your WH-1000XM4 or XM5. First time? Pair them in Bluetooth Settings."
        }
    }

    // MARK: Inserts (settings): a rail of sections, one section on screen at a time.

    private var availableSections: [InsertSection] {
        var sections: [InsertSection] = []
        if headphones.isReady {
            sections.append(.headphones)
            if device.speakToChat != nil { sections.append(.speakToChat) }
            if device.modelName != nil { sections.append(.noiseCancelling) }
            if device.dseeExtreme != nil || device.prefersStableConnection != nil { sections.append(.sound) }
            if device.touchPanel != nil || device.customButton != nil || device.pauseWhenRemoved != nil
                || device.autoPowerOff != nil || device.multipoint != nil || device.voiceGuidance != nil {
                sections.append(.controls)
            }
        }
        sections += [.app, .diagnostics]
        return sections
    }

    private var currentSection: InsertSection {
        availableSections.contains(section) ? section : (availableSections.first ?? .app)
    }

    private var inserts: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { navigate(to: .dashboard) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        Legend("Channel", size: 10.5, color: Console.legend)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Console.raised, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Console.seam, lineWidth: 0.75))
                }
                .buttonStyle(PressStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Back to channel")
                ScribbleTape(text: "Inserts", size: 13)
                Spacer()
                Text("Cans \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Console.dim)
            }
            .padding(.horizontal, MenuBarMetrics.inset)
            .padding(.vertical, 12)
            GrooveSeam()

            HStack(alignment: .top, spacing: 0) {
                sectionRail
                Rectangle().fill(Console.groove).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(currentSection.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Console.legend)
                        Text(currentSection.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Console.dim)
                            .padding(.top, 3)
                            .padding(.bottom, 12)
                        sectionContent(currentSection)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, MenuBarMetrics.inset)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(currentSection)
            }
        }
        .frame(height: max(contentHeight, MenuBarMetrics.insertsHeight))
    }

    private var sectionRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(availableSections) { item in
                let selected = item == currentSection
                Button { section = item } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 16)
                            .foregroundStyle(selected ? Console.amberInk : Console.dim)
                        Text(item.title)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Console.legend : Console.dim)
                        Spacer(minLength: 0)
                        if item == .app, updates.availableVersion != nil { UpdatePip() }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(selected ? Console.raised : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("section.\(item.rawValue)")
            }
            Spacer(minLength: 12)
            Button("Quit Cans") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Console.dim)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityIdentifier("app.quit")
        }
        .padding(.vertical, 12)
        .padding(.leading, MenuBarMetrics.inset - 10)
        .padding(.trailing, 12)
        .frame(width: 176, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func sectionContent(_ section: InsertSection) -> some View {
        switch section {
        case .headphones: headphonesSection
        case .speakToChat: speakToChatSection
        case .noiseCancelling: optimizerSection
        case .sound: soundSection
        case .controls: controlsSection
        case .app: appSection
        case .diagnostics: diagnosticsSection
        }
    }

    private var headphonesSection: some View {
        HStack(alignment: .top, spacing: 20) {
            ChannelPortrait(modelName: device.modelName ?? headphones.deviceName,
                            mode: headphones.noiseControlMode, ambientLevel: headphones.ambientLevel)
            VStack(alignment: .leading, spacing: 0) {
                InfoRow(label: "Model", value: device.modelName ?? "Sony headphones")
                InfoRow(label: "Firmware", value: headphones.firmwareVersion ?? "Unknown")
                InfoRow(label: "Battery", value: headphones.batteryLevel.map { "\($0)%\(headphones.isCharging ? ", charging" : "")" } ?? "Unknown")
                InfoRow(label: "Codec", value: device.codec ?? "Negotiating")
                InfoRow(label: "Address", value: headphones.address.uppercased())
                if device.modelName != nil {
                    powerOffButton.padding(.top, 14)
                }
            }
        }
    }

    @ViewBuilder
    private var speakToChatSection: some View {
        if let stc = device.speakToChat {
            RackRow(title: "Speak-to-Chat", detail: "Pauses music and lets sound in while you talk") {
                LatchButton(accessibilityTitle: "Speak-to-Chat", isOn: stc) { device.setSpeakToChat(!stc) }
            }
            if stc, let config = device.speakToChatConfig {
                RackRow(title: "Sensitivity", detail: "How readily your voice triggers it") {
                    LampSelector(options: SonyDeviceSettings.SpeakToChatSensitivity.allCases.map { ($0, $0.title) },
                                 selection: config.sensitivity) {
                        var next = config; next.sensitivity = $0; device.setSpeakToChatConfig(next)
                    }
                }
                RackRow(title: "Ends after", detail: "Silence before music resumes") {
                    LampSelector(options: SonyDeviceSettings.SpeakToChatTimeout.allCases.map { ($0, $0.title) },
                                 selection: config.timeout) {
                        var next = config; next.timeout = $0; device.setSpeakToChatConfig(next)
                    }
                }
                RackRow(title: "Focus on Voice", detail: "Lets voices through more clearly") {
                    LatchButton(accessibilityTitle: "Speak-to-Chat focus on voice", isOn: config.focusOnVoice) {
                        var next = config; next.focusOnVoice.toggle(); device.setSpeakToChatConfig(next)
                    }
                }
            }
        }
    }

    private var optimizerSection: some View {
        VStack(spacing: 0) {
            RackRow(title: "NC Optimizer",
                    detail: device.optimizer.isRunning ? "\(device.optimizer.title) Keep them on and stay still." : "Tunes cancelling to your fit and air pressure") {
                LampButton(title: device.optimizer.isRunning ? "Cancel" : "Run",
                           lit: device.optimizer.isRunning, height: 26, fontSize: 10.5) {
                    device.optimizer.isRunning ? device.cancelOptimizer() : device.startOptimizer()
                }
                .frame(width: 72)
            }
            if let pressure = device.pressureAtm {
                RackRow(title: "Air pressure", detail: "Run the optimizer again after a flight") {
                    HStack(spacing: 8) {
                        // The headphones report 0.7–1.0 atm.
                        LEDLadder(fraction: (pressure - 0.6) / 0.4, segments: 8)
                        Text(String(format: "%.1f atm", pressure))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Console.legend)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: "Air pressure %.1f atmospheres", pressure))
                }
            }
        }
    }

    @ViewBuilder
    private var soundSection: some View {
        if let dsee = device.dseeExtreme {
            RackRow(title: "DSEE Extreme", detail: "Upscales compressed music; uses more battery") {
                LatchButton(accessibilityTitle: "DSEE Extreme", isOn: dsee) { device.setDSEEExtreme(!dsee) }
            }
        }
        if let stable = device.prefersStableConnection {
            RackRow(title: "Bluetooth priority", detail: stable ? "Fewer dropouts, lower bitrate" : "Best sound, needs a strong signal") {
                LampSelector(options: [(false, "Quality"), (true, "Stable")], selection: stable) {
                    device.setPrefersStableConnection($0)
                }
            }
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        if let touch = device.touchPanel {
            RackRow(title: "Touch controls", detail: "Swipe and tap on the right ear cup") {
                LatchButton(accessibilityTitle: "Touch controls", isOn: touch) { device.setTouchPanel(!touch) }
            }
        }
        if let button = device.customButton {
            RackRow(title: "Custom button", detail: "Set up assistants in Sound Connect") {
                LampSelector(options: SonyDeviceSettings.CustomButton.allCases.map { ($0, $0.shortTitle) },
                             selection: button) { device.setCustomButton($0) }
            }
        }
        if let pause = device.pauseWhenRemoved {
            RackRow(title: "Pause when taken off", detail: "Resumes when you put them back on") {
                LatchButton(accessibilityTitle: "Pause when taken off", isOn: pause) { device.setPauseWhenRemoved(!pause) }
            }
        }
        if let autoOff = device.autoPowerOff {
            RackRow(title: "Auto power off", detail: "Saves battery when not worn") {
                LampSelector(options: SonyDeviceSettings.AutoPowerOff.allCases.map { ($0, $0 == .whenRemoved ? "Taken off" : "Never") },
                             selection: autoOff) { device.setAutoPowerOff($0) }
            }
        }
        if let multipoint = device.multipoint {
            RackRow(title: "Connect to 2 devices", detail: "Multipoint; turns off LDAC") {
                LatchButton(accessibilityTitle: "Connect to 2 devices", isOn: multipoint) { confirmingMultipoint = true }
            }
        }
        if let voice = device.voiceGuidance {
            RackRow(title: "Voice guidance", detail: "Spoken status prompts in the headphones") {
                LatchButton(accessibilityTitle: "Voice guidance", isOn: voice) { device.setVoiceGuidance(!voice) }
            }
        }
    }

    @ViewBuilder
    private var appSection: some View {
        RackRow(title: "Reconnect automatically", detail: "Takes the controls back when they're free") {
            LatchButton(accessibilityTitle: "Reconnect automatically", isOn: settings.reconnectAutomatically) {
                settings.reconnectAutomatically.toggle()
            }
        }
        RackRow(title: "Open at login", detail: "Cans waits quietly in the menu bar") {
            LatchButton(accessibilityTitle: "Open at login", isOn: settings.launchAtLogin) {
                settings.setLaunchAtLogin(!settings.launchAtLogin)
            }
        }
        RackRow(title: "Shortcut ⌥⌘A", detail: "Switches between noise cancelling and ambient") {
            LatchButton(accessibilityTitle: "Global shortcut", isOn: settings.globalShortcutEnabled) {
                settings.globalShortcutEnabled.toggle()
            }
        }
        if let error = settings.launchAtLoginError {
            Text(error).font(.system(size: 11)).foregroundStyle(Console.legend).padding(.top, 8)
        }
        updateRow
        RackRow(title: "Automatic updates", detail: "Asks GitHub once a day for a newer Cans") {
            LatchButton(accessibilityTitle: "Automatic updates", isOn: updates.checksAutomatically) {
                updates.checksAutomatically.toggle()
            }
        }
        RackRow(title: "Support Cans", detail: "Free and open source") {
            LampButton(title: "Buy me a coffee", lit: false, height: 26, fontSize: 10.5) {
                if let url = URL(string: "https://buymeacoffee.com/yash.raj") { NSWorkspace.shared.open(url) }
            }
            .frame(width: 150)
        }
    }

    /// Waiting: the version and a lit Update button (Sparkle's sheet installs it).
    /// Otherwise: the running version, when it last looked, and Check now.
    private var updateRow: some View {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return Group {
            if let version = updates.availableVersion {
                RackRow(title: "Cans \(version) is ready", detail: "You have \(current). Cans reopens after installing") {
                    LampButton(title: "Update", lit: true, height: 26, fontSize: 10.5) { updates.checkNow() }
                        .frame(width: 110)
                        .accessibilityIdentifier("app.update")
                }
            } else {
                RackRow(title: "Cans \(current)", detail: lastCheckText) {
                    LampButton(title: "Check now", lit: false, enabled: updates.canCheck, height: 26, fontSize: 10.5) {
                        updates.checkNow()
                    }
                    .frame(width: 110)
                    .accessibilityIdentifier("app.checkForUpdates")
                }
            }
        }
    }

    private var lastCheckText: String {
        guard let date = updates.lastCheck else { return "Not checked for updates yet" }
        return "Up to date · checked " + date.formatted(.relative(presentation: .named))
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow(label: "Control link", value: headphones.statusText)
            InfoRow(label: "Protocol", value: headphones.protocolDescription)
            InfoRow(label: "Last sync", value: headphones.lastSyncDate?.formatted(date: .omitted, time: .standard) ?? "Never")
            if let error = headphones.lastErrorMessage {
                InfoRow(label: "Last issue", value: error, warning: true)
            }
            HStack(spacing: 8) {
                LampButton(title: "Sync now", lit: false, height: 26, fontSize: 10.5) { headphones.reloadFromDevice() }
                    .keyboardShortcut("r", modifiers: .command)
                LampButton(title: "Copy report", lit: false, height: 26, fontSize: 10.5) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(headphones.diagnosticReport, forType: .string)
                }
            }
            .frame(width: RackRow<EmptyView>.controlColumn)
            .padding(.top, 16)
        }
    }

    /// Guarded like a covered switch: the first click arms it, the second sends power off.
    private var powerOffButton: some View {
        LampButton(title: powerOffArmed ? "Click to confirm" : "Power off", lit: powerOffArmed, height: 26, fontSize: 10.5) {
            if powerOffArmed {
                device.powerOff()
                powerOffArmed = false
            } else {
                powerOffArmed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { powerOffArmed = false }
            }
        }
        .frame(width: 140)
        .help("Turn the headphones off")
    }

    #if DEBUG
    /// Capture aid: --demo-tour plays a scripted walk through the real controls on the real
    /// headphones (for the README GIF and launch video), then restores NC with EQ off.
    private func runDemoTour() {
        Task { @MainActor in
            func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
            // About 27 s, paced for people watching on a phone: quick where nothing changes,
            // slow where the eye has to follow (the ambient sweep, scenes, EQ, settings pages).
            headphones.applyPreset(mode: .anc, ambientLevel: 1, focusOnVoice: false)
            headphones.setEqualizerPreset(.off)
            await wait(2.5)
            headphones.applyPreset(mode: .ambient, ambientLevel: 4, focusOnVoice: false)
            await wait(1.5)
            for level in stride(from: 6, through: 20, by: 2) {
                headphones.setAmbientLevel(level)
                await wait(0.35)
            }
            await wait(2)
            headphones.applyPreset(mode: .ambient, ambientLevel: 8, focusOnVoice: true)  // Office scene
            await wait(2.8)
            headphones.setEqualizerPreset(.bassBoost)
            await wait(2.4)
            headphones.setEqualizerPreset(.bright)
            await wait(2.4)
            headphones.setNoiseControl(.anc)
            await wait(2)
            section = .speakToChat  // Headphones shows the Bluetooth address; keep it out of recordings
            navigate(to: .inserts)
            for next in [InsertSection.noiseCancelling, .controls] {
                await wait(2.4)
                section = next
            }
            await wait(2.4)
            navigate(to: .dashboard)
            headphones.setEqualizerPreset(.off)
            headphones.applyPreset(mode: .anc, ambientLevel: 1, focusOnVoice: false)
        }
    }
    #endif

    // MARK: Navigation

    private func slide(_ edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: edge).combined(with: .opacity), removal: .opacity)
    }

    private func navigate(to destination: PanelScreen) {
        guard screen != destination else { return }
        if reduceMotion {
            screen = destination
        } else {
            withAnimation(.smooth(duration: 0.24)) { screen = destination }
        }
    }
}

private extension SonyDeviceSettings.CustomButton {
    var shortTitle: String {
        switch self {
        case .ambientControl: "NC/Amb"
        case .googleAssistant: "Google"
        case .alexa: "Alexa"
        }
    }
}
