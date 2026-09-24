import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private struct StatusPresentation {
        let title: String
        let accessibilityLabel: String
    }

    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var pendingStatusPresentation: StatusPresentation?
    private var litSegments = 0

    /// The Cans menu bar mark: two cups under a three-segment meter band. Lit segments show the
    /// mode in one colour (off 0, ambient 2, noise cancelling 3), as the menu bar is template-only.
    private static func glyph(lit: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1.75, y: 9, width: 3.5, height: 6), xRadius: 1.6, yRadius: 1.6).fill()
            NSBezierPath(roundedRect: NSRect(x: 12.75, y: 9, width: 3.5, height: 6), xRadius: 1.6, yRadius: 1.6).fill()
            for segment in 0..<3 {
                let start = 180 + CGFloat(segment) * 60 + 11
                let band = NSBezierPath()
                band.appendArc(withCenter: NSPoint(x: 9, y: 10), radius: 6, startAngle: start, endAngle: start + 38)
                band.lineWidth = 1.7
                band.lineCapStyle = .round
                NSColor.black.withAlphaComponent(segment < lit ? 1 : 0.35).setStroke()
                band.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentSize = MenuBarMetrics.displaySize
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(onSizeChange: { [weak self] size in
                guard let self, self.popover.contentSize != size else { return }
                self.popover.contentSize = size
            })
                .environmentObject(environment.settings)
                .environmentObject(environment.headphones)
                .environmentObject(environment.headphones.deviceSettings)
        )

        guard let button = statusItem.button else { return }
        button.image = Self.glyph(lit: 0)
        button.setAccessibilityLabel(String(localized: "status.accessibilityLabel"))
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        Publishers.CombineLatest3(
            environment.headphones.$linkState,
            environment.headphones.$noiseControlMode,
            environment.headphones.$batteryLevel
        )
        .sink { [weak self] _, _, _ in self?.updateStatusItem() }
        .store(in: &cancellables)
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let headphones = environment.headphones
        let title: String
        if headphones.isReady {
            if let battery = headphones.batteryLevel {
                title = " \(battery)%"
            } else if let mode = headphones.noiseControlMode {
                title = " \(mode.compactTitle)"
            } else {
                title = ""
            }
        } else {
            title = ""
        }
        let lit: Int
        switch headphones.isReady ? headphones.noiseControlMode : nil {
        case .anc: lit = 3
        case .ambient: lit = 2
        default: lit = 0
        }
        if lit != litSegments {
            litSegments = lit
            button.image = Self.glyph(lit: lit)
        }
        let details = [
            headphones.statusText,
            headphones.noiseControlMode?.title,
            headphones.batteryLevel.map { "Battery \($0) percent" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        let presentation = StatusPresentation(
            title: title,
            accessibilityLabel: "Cans, \(details)"
        )

        // Keep the status item's width fixed while its popover is anchored to it.
        // Accessibility remains current even while the visual title is queued.
        button.setAccessibilityLabel(presentation.accessibilityLabel)
        guard !popover.isShown else {
            pendingStatusPresentation = presentation
            return
        }
        apply(presentation)
    }

    private func apply(_ presentation: StatusPresentation) {
        statusItem.button?.title = presentation.title
        statusItem.button?.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let pendingStatusPresentation else { return }
        self.pendingStatusPresentation = nil
        apply(pendingStatusPresentation)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button, button.window != nil else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}
