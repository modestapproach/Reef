//
//  ExposePanelController.swift
//  Reef
//
//  Mission Control-style exposé scoped to one bound app or browser profile.
//

import AppKit
import SwiftUI

@MainActor
final class ExposePanelController: NSObject {
    private(set) var panel: ExposeOverlayPanel!
    private let state = ExposeState()
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var currentApplication: Application?
    private var captureTask: Task<Void, Never>?
    private var shownAt: Date?

    // A quick tap of the chord releases its modifiers as the overlay is still
    // appearing; ignore releases inside this window so a tap means "browse"
    // while a deliberate hold-and-release still commits the selection.
    private let tapGracePeriod: TimeInterval = 0.3

    override init() {
        super.init()
        createPanel()
    }

    private func createPanel() {
        panel = ExposeOverlayPanel()
        panel.delegate = self

        let contentView = ExposeView(
            state: state,
            onSelect: { [weak self] index in
                guard let self else { return }
                self.state.selectedIndex = index
                self.activateSelectedWindow()
            },
            onCancel: { [weak self] in
                self?.hideExpose()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        guard let containerView = panel.contentView else { return }
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    func show(for application: Application) {
        currentApplication = application
        state.setApplication(application)

        print("Expose: \(application.displayTitle) — \(state.windows.count) windows, screenAccess=\(state.hasScreenAccess)")

        // Nothing to hunt through — behave like instant switching with no windows.
        guard !state.windows.isEmpty else {
            hideExpose()
            Task { @MainActor in
                let success = await application.performNoWindowAction()
                if !success {
                    NSSound.beep()
                }
            }
            return
        }

        let screen = screenForOverlay()
        shownAt = Date()
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installFlagsMonitor()
        installKeyDownMonitor()

        startThumbnailCapture()
    }

    func cycleSelection() {
        state.cycleNext()
    }

    func isShowingExpose(for application: Application) -> Bool {
        guard let currentApplication else { return false }

        guard currentApplication.browserProfileName == application.browserProfileName else {
            return false
        }

        if let currentBundleID = currentApplication.bundleIdentifier,
           let targetBundleID = application.bundleIdentifier {
            return currentBundleID == targetBundleID
        }

        if let currentURL = currentApplication.bundleUrl,
           let targetURL = application.bundleUrl {
            return currentURL == targetURL
        }

        return currentApplication.title == application.title
    }

    // Overlay goes on the screen the user is looking at: the one with the
    // focused window, falling back to the screen under the mouse.
    private func screenForOverlay() -> NSScreen {
        if let focusedFrame = Window.getFrontWindow()?.cgWindowID.flatMap(windowFrame(for:)),
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(focusedFrame) }) {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func windowFrame(for windowID: CGWindowID) -> NSRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let boundsDict = info.first?[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }

        // CGWindow bounds are top-left origin; flip into AppKit's coordinate space.
        let bounds = NSRect(
            x: boundsDict["X"] ?? 0,
            y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0,
            height: boundsDict["Height"] ?? 0
        )
        let primaryHeight = NSScreen.screens[0].frame.height
        return NSRect(
            x: bounds.origin.x,
            y: primaryHeight - bounds.origin.y - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    private func startThumbnailCapture() {
        captureTask?.cancel()

        let windowIDs = state.windows.compactMap(\.cgWindowID)
        let state = self.state

        captureTask = Task {
            await WindowThumbnailProvider.capture(windowIDs: windowIDs) { windowID, image in
                state.thumbnails[windowID] = image
            }
        }
    }

    func activateSelectedWindow() {
        let window = state.currentWindow
        hideExpose()
        window?.focus()
    }

    private func hideExpose() {
        captureTask?.cancel()
        captureTask = nil
        removeFlagsMonitor()
        removeKeyDownMonitor()
        panel.orderOut(nil)
        state.reset()
        currentApplication = nil
        shownAt = nil
    }

    private func installFlagsMonitor() {
        guard flagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }

            // Activate once every modifier of the exposé chord is released —
            // the chord is configurable and may not include Control.
            let chord = AppDelegate.modifierManager?.exposeModifiers ?? [.control]
            let pressed = event.modifierFlags.intersection([.control, .option, .shift, .command])

            if !chord.isEmpty, pressed.intersection(chord).isEmpty {
                if let shownAt = self.shownAt, Date().timeIntervalSince(shownAt) < self.tapGracePeriod {
                    return event
                }

                Task { @MainActor in
                    self.activateSelectedWindow()
                }
            }

            return event
        }
    }

    private func removeFlagsMonitor() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }

            switch event.keyCode {
            case 53: // Escape
                Task { @MainActor in
                    self.hideExpose()
                }
                return nil
            case 36, 76: // Return / Enter
                Task { @MainActor in
                    self.activateSelectedWindow()
                }
                return nil
            case 123: // Left arrow
                Task { @MainActor in
                    self.state.moveSelection(byColumns: -1, byRows: 0)
                }
                return nil
            case 124: // Right arrow
                Task { @MainActor in
                    self.state.moveSelection(byColumns: 1, byRows: 0)
                }
                return nil
            case 125: // Down arrow
                Task { @MainActor in
                    self.state.moveSelection(byColumns: 0, byRows: 1)
                }
                return nil
            case 126: // Up arrow
                Task { @MainActor in
                    self.state.moveSelection(byColumns: 0, byRows: -1)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyDownMonitor() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }

    deinit {
        // Capture the monitors in local variables before deinit (while still on main actor)
        let monitor = flagsMonitor
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        let keyMonitor = keyDownMonitor
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

extension ExposePanelController: NSWindowDelegate {
    // Clicking another app (or anything that steals key) dismisses the overlay
    // and tears down its monitors.
    func windowDidResignKey(_ notification: Notification) {
        hideExpose()
    }
}
