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
    private(set) var panel: CyclePanel!
    private let state = ExposeState()
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var currentApplication: Application?
    private var captureTask: Task<Void, Never>?

    override init() {
        super.init()
        createPanel()
    }

    private func createPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 600, height: 400)
        panel = CyclePanel(contentRect: contentRect)

        let contentView = ExposeView(state: state) { [weak self] index in
            guard let self else { return }
            self.state.selectedIndex = index
            self.activateSelectedWindow()
        }
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

        updatePanelSize()
        panel.center()
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

    private func updatePanelSize() {
        let columns = CGFloat(max(1, state.columns))
        let rows = CGFloat(max(1, state.rows))

        let gridWidth = columns * ExposeMetrics.cardWidth
            + (columns - 1) * ExposeMetrics.gridSpacing
            + ExposeMetrics.gridPadding * 2
        let gridHeight = rows * ExposeMetrics.cardHeight
            + (rows - 1) * ExposeMetrics.gridSpacing
            + ExposeMetrics.gridPadding * 2
        let desiredContentHeight = ExposeMetrics.headerHeight + 1 + gridHeight

        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = visibleFrame.width * 0.85
        let maxHeight = visibleFrame.height * 0.85

        let contentWidth = min(gridWidth, maxWidth)
        let contentHeight = min(desiredContentHeight, maxHeight)

        let targetContentRect = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        let targetFrameSize = panel.frameRect(forContentRect: targetContentRect).size
        panel.setFrame(NSRect(origin: panel.frame.origin, size: targetFrameSize), display: true, animate: false)
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
    }

    private func installFlagsMonitor() {
        guard flagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }

            let controlPressed = event.modifierFlags.contains(.control)

            // Control was released
            if !controlPressed {
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
