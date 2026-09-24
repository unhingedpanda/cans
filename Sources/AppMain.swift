import SwiftUI

@main
@MainActor
struct CansApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Everything lives in the menu bar popover; the scene exists only because App requires one.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
