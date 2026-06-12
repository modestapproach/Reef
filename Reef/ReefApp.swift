//
//  ReefApp.swift
//  Reef
//
//  Created by Xander Gouws on 12-09-2025.
//

import SwiftUI
import KeyboardShortcuts
import ServiceManagement

@main
struct ReefApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var profileManager: ProfileManager
    @StateObject private var sparkleConnector = SparkleConnector()
    @AppStorage("launchOnLogin") private var launchOnLogin = true
    
    init() {
        let profileManager = ProfileManager()
        _profileManager = StateObject(wrappedValue: profileManager)
        AppDelegate.profileManager = profileManager
        
        // Sync launch at login state with system
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            _launchOnLogin = AppStorage(wrappedValue: status == .enabled, "launchOnLogin")
        }
    }

    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(profileManager)
                .environmentObject(sparkleConnector)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(profileManager)
                .environmentObject(sparkleConnector)
        } label: {
            Image("menu_placeholder")
                .renderingMode(.template)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var instance: AppDelegate!
    static var profileManager: ProfileManager!
    static private(set) var modifierManager: ModifierManager!
    static private(set) var capsLockManager: CapsLockRemapManager!
    
    private var cycleController: CyclePanelController!
    private var exposeController: ExposePanelController!
    private var shortcutManager: ShortcutController!
    private var windowManager: PreferencesController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.instance = self
        AppDelegate.modifierManager = ModifierManager()
        AppDelegate.capsLockManager = CapsLockRemapManager()
        AppDelegate.capsLockManager.apply()

        cycleController = CyclePanelController()
        exposeController = ExposePanelController()
        shortcutManager = ShortcutController(cycleController, exposeController, AppDelegate.profileManager)
        windowManager = PreferencesController()

        NSApp.setActivationPolicy(.accessory)

        // Prompt for Accessibility on launch when untrusted. This also makes
        // macOS register the current bundle in the Accessibility list, so the
        // user only has to flip the toggle — important for ad-hoc local builds,
        // where each rebuild changes the signature and orphans the old entry.
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.profileManager.saveNow()
        AppDelegate.capsLockManager.tearDownForQuit()
    }
}
