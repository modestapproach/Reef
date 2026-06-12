//
//  ShortcutController.swift
//  Reef
//
//  Created by Xander Gouws on 12-09-2025.
//

import KeyboardShortcuts
import Cocoa

let numberKeys: [KeyboardShortcuts.Key] = [
    .zero, .one, .two, .three, .four,
    .five, .six, .seven, .eight, .nine
]

extension KeyboardShortcuts.Name {
    static let bindShortcuts: [KeyboardShortcuts.Name] = (0...9).map { number in
        Self("bind\(number)")
    }
    
    static let activateShortcuts: [KeyboardShortcuts.Name] = (0...9).map { number in
        Self("activate\(number)")
    }
    
    static let profileShortcuts: [KeyboardShortcuts.Name] = (0...9).map { number in
        Self("profile\(number)")
    }

    static let exposeShortcuts: [KeyboardShortcuts.Name] = (0...9).map { number in
        Self("expose\(number)")
    }
}

@MainActor
final class ShortcutController {
    private let cycleController: CyclePanelController
    private let exposeController: ExposePanelController
    private let profileManager: ProfileManager

    init(_ cycleController: CyclePanelController, _ exposeController: ExposePanelController, _ profileManager: ProfileManager) {
        self.cycleController = cycleController
        self.exposeController = exposeController
        self.profileManager = profileManager

        setupShortcuts()
    }

    private func setupShortcuts() {
        for number in 0...9 {
            KeyboardShortcuts.onKeyUp(for: .bindShortcuts[number]) {
                self.handleBind(number: number)
            }

            KeyboardShortcuts.onKeyDown(for: .activateShortcuts[number]) {
                self.handleActivate(number: number)
            }

            KeyboardShortcuts.onKeyDown(for: .profileShortcuts[number]) {
                self.handleProfile(number: number)
            }

            KeyboardShortcuts.onKeyDown(for: .exposeShortcuts[number]) {
                self.handleExpose(number: number)
            }
        }
    }
    
    private func handleBind(number: Int) {
        guard let application = Application.getFrontApplication() else {
            NSSound.beep()
            return
        }

        guard let bundleIdentifier = application.bundleIdentifier else {
            NSSound.beep()
            return
        }

        var binding = bundleIdentifier
        if UserDefaults.standard.bool(forKey: "separateBrowserProfiles"),
           let windowTitle = application.getFocusedWindow()?.rawTitle,
           let profileName = BrowserProfile.profileName(fromWindowTitle: windowTitle, bundleIdentifier: bundleIdentifier) {
            binding = BrowserProfile.encodeBinding(bundleIdentifier: bundleIdentifier, profileName: profileName)
        }

        profileManager.bind(bundleIdentifier: binding, to: number)

        print("Bound \(binding) to \(number)")
    }

    // "Switch app - Fast": always instant, no panel.
    private func handleActivate(number: Int) {
        guard let binding = profileManager.application(for: number) else {
            NSSound.beep()
            return
        }

        // The list panel may be open (exposé chord in list mode); repeat
        // presses cycle it rather than switching behind it.
        if cycleController.panel.isVisible {
            if cycleController.isShowingSwitcher(for: binding) {
                cycleController.cycleNext()
            } else {
                cycleController.showSwitcher(for: binding)
            }

            return
        }

        instantActivate(binding)
    }

    // Instant mode: no panel. The first press focuses the app; repeat presses
    // jump straight to its next window.
    private func instantActivate(_ application: Application) {
        let windows = application.getWindows()

        guard !windows.isEmpty else {
            Task { @MainActor in
                let success = await application.performNoWindowAction()
                if !success {
                    NSSound.beep()
                }
            }
            return
        }

        guard application.isFrontmost() else {
            windows.first?.focus()
            return
        }

        // Cycle in a stable order (window IDs are creation-ordered) so repeated
        // presses visit every window instead of bouncing between the top two.
        let orderedWindows = windows.sorted { ($0.cgWindowID ?? 0) < ($1.cgWindowID ?? 0) }
        let focusedID = application.getFocusedWindow()?.cgWindowID

        if let focusedID,
           let currentIndex = orderedWindows.firstIndex(where: { $0.cgWindowID == focusedID }) {
            orderedWindows[(currentIndex + 1) % orderedWindows.count].focus()
        } else {
            orderedWindows.first?.focus()
        }
    }
    
    // "Switch app - Exposé": a grid of the binding's windows for visual
    // hunting. Repeat presses cycle the selection; releasing the chord (or
    // clicking) activates. With "Use List instead of Exposé UI" on, the
    // classic switcher panel shows instead of the grid.
    private func handleExpose(number: Int) {
        guard let binding = profileManager.application(for: number) else {
            NSSound.beep()
            return
        }

        if UserDefaults.standard.bool(forKey: "useListInsteadOfExpose") {
            if cycleController.panel.isVisible {
                if cycleController.isShowingSwitcher(for: binding) {
                    cycleController.cycleNext()
                } else {
                    cycleController.showSwitcher(for: binding)
                }

                return
            }

            // Already on this app: start at second window
            let startIndex = binding.isFrontmost() ? 1 : 0
            cycleController.showSwitcher(for: binding, startIndex: startIndex)
            return
        }

        if exposeController.panel.isVisible, exposeController.isShowingExpose(for: binding) {
            exposeController.cycleSelection()
            return
        }

        exposeController.show(for: binding)
    }

    func handleProfile(number: Int) {
        guard let profileID = profileManager.profileID(forNumber: number) else {
            NSSound.beep()
            return
        }
        
        profileManager.switchProfile(id: profileID)
    }
}
