import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment.live()

    private var menuBarController: MenuBarController?
    private var globalHotKeyController: GlobalHotKeyController?
    private var cancellables = Set<AnyCancellable>()
    /// SIGTERM (kill, some logout paths) bypasses AppKit's quit; route it through terminate so the
    /// Sony control channel is released instead of staying reserved for the next launch.
    private var terminationSource: DispatchSourceSignal?
    #if DEBUG
    private var uiTestWindow: NSWindow?
    #endif

    func applicationWillFinishLaunching(_ notification: Notification) {
        if !isRunningTests,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }
        #if MENU_BAR_APP
        NSApp.setActivationPolicy(.accessory)
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.headphones.disconnect()
    }

    private var isRunningTests: Bool {
        AppEnvironment.isTestHost ||
            CommandLine.arguments.contains("--ui-test-host")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSource = source
        if !isRunningTests, !CommandLine.arguments.contains("-ui-testing") {
            Updates.shared.start()
        }

        #if MENU_BAR_APP || HYBRID_APP
        menuBarController = MenuBarController(environment: environment)
        globalHotKeyController = GlobalHotKeyController { [weak self] in
            self?.environment.headphones.toggleNoiseControl()
        }
        environment.settings.$globalShortcutEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in self?.globalHotKeyController?.setEnabled(enabled) }
            .store(in: &cancellables)
        #endif

        #if DEBUG
        // Screenshot/review aid: --appearance=dark|light overrides the system appearance.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--appearance=") }) {
            NSApp.appearance = NSAppearance(named: arg.hasSuffix("dark") ? .darkAqua : .aqua)
        }
        #endif

        #if DEBUG && (MENU_BAR_APP || HYBRID_APP)
        if CommandLine.arguments.contains("--ui-test-host") {
            showUITestHost()
        }
        #endif
    }

    #if DEBUG && (MENU_BAR_APP || HYBRID_APP)
    private func showUITestHost() {
        let content = MenuBarView()
            .environmentObject(environment.settings)
            .environmentObject(environment.headphones)
            .environmentObject(environment.headphones.deviceSettings)
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "app.name")
        window.setContentSize(MenuBarMetrics.displaySize)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        uiTestWindow = window
    }
    #endif
}
