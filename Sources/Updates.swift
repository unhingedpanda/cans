import Combine
import Foundation
import Sparkle

/// Sparkle, adapted to a menu bar app: scheduled finds light an amber pip on the panel (a "gentle
/// reminder") instead of throwing a window at someone who is working. Clicking Update hands over to
/// Sparkle's own install sheet.
@MainActor
final class Updates: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    /// The version waiting to be installed, e.g. "1.0.2".
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    @Published var checksAutomatically = false {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != checksAutomatically {
                controller.updater.automaticallyChecksForUpdates = checksAutomatically
            }
        }
    }

    private var controller: SPUStandardUpdaterController!
    private var cancellables = Set<AnyCancellable>()

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }.store(in: &cancellables)
        updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastCheck = $0 }.store(in: &cancellables)
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] in self?.checksAutomatically = $0 }.store(in: &cancellables)
        #if DEBUG
        // Screenshot aid: --fake-update=1.0.2 shows the waiting-update state.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--fake-update=") }) {
            availableVersion = String(arg.dropFirst("--fake-update=".count))
        }
        #endif
    }

    /// Never under tests: an update sheet mid-run would block the UI suite.
    func start() { controller.startUpdater() }

    /// Also how a waiting update gets installed: Sparkle shows it again, with its install button.
    func checkNow() { controller.checkForUpdates(nil) }

    // MARK: SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated { availableVersion = version }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { availableVersion = nil }
    }
}
