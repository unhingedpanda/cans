import Combine
import Foundation

@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let headphones: SonyHeadphonesController
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore, headphones: SonyHeadphonesController) {
        self.settings = settings
        self.headphones = headphones
        settings.$reconnectAutomatically
            .removeDuplicates()
            .sink { [weak headphones] enabled in
                headphones?.setReconnectAutomatically(enabled)
            }
            .store(in: &cancellables)
    }

    /// True when unit-test bundles are injected into this process. An app merely launched by UI
    /// tests is not a test host: it must connect for real, so only injection markers count.
    static var isTestHost: Bool {
        let env = ProcessInfo.processInfo.environment
        return ["XCInjectBundleInto", "XCTestBundleInjectPath", "XCTestBundlePath"].contains { env[$0] != nil }
    }

    static func live() -> AppEnvironment {
        if isTestHost {
            // Unit-test host: never take the real RFCOMM channel from a running copy.
            return AppEnvironment(
                settings: SettingsStore(defaults: UserDefaults(suiteName: "app.cans.mac.tests") ?? .standard),
                headphones: SonyHeadphonesController(startAutomatically: false)
            )
        }
        if CommandLine.arguments.contains("-ui-testing") {
            let suiteName = "app.cans.mac.ui-testing"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            return AppEnvironment(
                settings: SettingsStore(defaults: defaults),
                headphones: SonyHeadphonesController(startAutomatically: false, simulatedReady: true)
            )
        }
        return AppEnvironment(
            settings: SettingsStore(defaults: .standard, managesLaunchService: true),
            headphones: SonyHeadphonesController()
        )
    }
}
