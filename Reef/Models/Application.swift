//
//  Application.swift
//  Reef
//
//  Created by Xander Gouws on 16-09-2025.
//

import Foundation
import Cocoa


class Application {
    var title: String
    var element: AXUIElement?

    // When set, this instance represents a single browser profile: window
    // lists are filtered to that profile and new windows open in it.
    var browserProfileName: String?

    var runningApplication: NSRunningApplication?
    var pid: pid_t?
    var bundleIdentifier: String?
    var bundleUrl: URL?
    
    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication

        self.pid = runningApplication.processIdentifier

        self.element = AXUIElementCreateApplication(self.pid!)

        self.title = runningApplication.localizedName ?? "Unknown Application"
        self.bundleIdentifier = runningApplication.bundleIdentifier
        self.bundleUrl = runningApplication.bundleURL
    }
    
    // Initialize from URL (for loading from persistence)
    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        self.bundleUrl = url
        self.bundleIdentifier = Bundle(url: url)?.bundleIdentifier
        self.title = url.deletingPathExtension().lastPathComponent
        
        // Try to find running instance
        if let bundle = Bundle(url: url),
           let bundleIdentifier = bundle.bundleIdentifier,
           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            self.runningApplication = runningApp
            self.pid = runningApp.processIdentifier
            self.element = AXUIElementCreateApplication(self.pid!)
            self.title = runningApp.localizedName ?? self.title
        } else {
            self.runningApplication = nil
            self.pid = nil
            self.element = nil
        }
    }

    convenience init?(bundleIdentifier: String) {
        if let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        {
            self.init(runningApp)
            return
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            self.init(url: url)
            return
        }

        return nil
    }
    
//    // Ensure application is running and refresh internal state
//    func ensureRunning() -> Bool {
//        guard let bundleUrl = self.bundleUrl else {
//            return false
//        }
//        
//        // Check if already running
//        if let runningApp = self.runningApplication,
//           runningApp.isTerminated == false {
//            return true
//        }
//        
//        // Try to find if it's running but we lost the reference
//        if let bundle = Bundle(url: bundleUrl),
//           let bundleIdentifier = bundle.bundleIdentifier,
//           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
//            self.runningApplication = runningApp
//            self.pid = runningApp.processIdentifier
//            self.element = AXUIElementCreateApplication(self.pid!)
//            return true
//        }
//        
//        return false
//    }
    
    var displayTitle: String {
        guard let browserProfileName else { return title }
        return "\(title) – \(browserProfileName)"
    }

    func focus() {
        if browserProfileName != nil {
            // Focus the profile's frontmost window (or open one) rather than
            // activating the whole browser.
            Task { @MainActor in
                _ = await self.performNoWindowAction()
            }
            return
        }

        self.activate()
    }

    func isFrontmost() -> Bool {
        guard let frontApp = Application.getFrontApplication() else { return false }

        if let frontBundleID = frontApp.bundleIdentifier, let bundleIdentifier {
            guard frontBundleID == bundleIdentifier else { return false }
        } else {
            guard frontApp.title == title else { return false }
        }

        guard let browserProfileName else { return true }

        guard let focusedTitle = frontApp.getFocusedWindow()?.rawTitle else { return false }
        return BrowserProfile.profileName(fromWindowTitle: focusedTitle, bundleIdentifier: bundleIdentifier) == browserProfileName
    }

    var isRunning: Bool {
        refreshRunningApplication() != nil
    }

    func activate(options: NSApplication.ActivationOptions = []) {
        if let runningApplication = refreshRunningApplication() {
            // App is running, just activate it
            runningApplication.activate(options: options)
        } else {
            // App not running, launch it
            try? reopen()
        }
    }
    
    func getFocusedWindow() -> Window? {
        guard let element = element,
              let windowElement: AXUIElement = element.getAttributeValue(.focusedWindow) else {
            return nil
        }
        
        return Window(windowElement, self)
    }
    
    func getFirstWindow() -> Window? {
        guard let element = element,
              let windowElements: [AXUIElement] = element.getAttributeValue(.windows) else {
            return nil
        }
        
        if let firstWindowElement = windowElements.first {
            return Window(firstWindowElement, self)
        }
        
        return nil
    }
    
    func reopen(
        configuration: NSWorkspace.OpenConfiguration = Application.defaultOpenConfiguration(),
        completion: @escaping (Result<NSRunningApplication, Error>) -> Void
    ) throws {
        guard let bundleUrl = self.bundleUrl else {
            throw ApplicationError.noBundleURL
        }
        
        NSWorkspace.shared.openApplication(
            at: bundleUrl,
            configuration: configuration,
            completionHandler: { runningApplication, error in
                if let runningApplication {
                    self.setRunningApplication(runningApplication)
                    completion(.success(runningApplication))
                    return
                }
                
                completion(.failure(error ?? ApplicationError.openFailed))
            }
        )
    }
    
    func reopen(
        configuration: NSWorkspace.OpenConfiguration = Application.defaultOpenConfiguration()
    ) async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try reopen(configuration: configuration) { result in
                    continuation.resume(with: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func reopen() throws {
        try reopen(configuration: Self.defaultOpenConfiguration()) { _ in }
    }
    
    func performNoWindowAction() async -> Bool {
        if let existingWindow = getWindows().first {
            existingWindow.focus()
            return true
        }

        // For a profile binding, open a new window in that specific profile.
        if let browserProfileName,
           let profileDirectory = BrowserProfile.profileDirectory(named: browserProfileName, bundleIdentifier: bundleIdentifier),
           await openBrowserProfileWindow(profileDirectory: profileDirectory) {
            return true
        }

        // Running with no windows: activate, and — when the opt-in toggle is
        // on — send the app ⌘N, the universal "new window" key equivalent, so
        // the binding lands on a usable window, not a bare focused app.
        // (Relaunching via NSWorkspace does not deliver a reopen event to a
        // running app.)
        if isRunning {
            activate()

            if UserDefaults.standard.bool(forKey: "openNewWindowIfNoneExist") {
                try? await Task.sleep(nanoseconds: 300_000_000)
                postNewWindowShortcut()
            }
            return true
        }

        do {
            _ = try await reopen(configuration: Self.defaultOpenConfiguration(activates: true))
            return true
        } catch {
            return false
        }
    }

    // Posts ⌘N to the app's process. Posting events is covered by the
    // Accessibility permission Reef already requires.
    private func postNewWindowShortcut() {
        guard let pid else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyN: CGKeyCode = 45

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyN, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyN, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.postToPid(pid)
        keyUp?.postToPid(pid)
    }

    // Chromium browsers forward the command line of a second instance to the
    // running one, so launching with --profile-directory opens a new window in
    // that profile whether or not the browser is already running.
    private func openBrowserProfileWindow(profileDirectory: String) async -> Bool {
        guard let bundleUrl else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--profile-directory=\(profileDirectory)"]

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: bundleUrl, configuration: configuration) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }
    
    static func getFrontApplication() -> Application? {
        guard let runningApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        return Application(runningApplication)
    }
    
    static func activateOrLaunch(
        bundleIdentifier: String,
        bundleURL: URL,
        options: NSApplication.ActivationOptions = []
    ) {
        if let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        {
            runningApplication.activate(options: options)
            return
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in }
    }

    func getAXWindows() -> [AXUIElement] {
        guard let element = element else {
            return []
        }
        
        // NOTE: Only returns windows in current Desktop (but multiple monitors does work)
        guard let windows: [AXUIElement] = element.getAttributeValue(.windows) else {
            return []
        }
        
        return windows
    }
    
    func getWindows() -> [Window] {
        let axWindows = self.getAXWindows()
        var windows = axWindows.map { axWindow in
            Window(axWindow, self)
        }
        
        // Finder can expose a trailing generic "Finder" window that is not useful for switching.
        if bundleIdentifier == "com.apple.finder",
           let lastWindow = windows.last,
           lastWindow.title == "Finder" {
            windows.removeLast()
        }

        if let browserProfileName {
            windows = windows.filter { window in
                guard let windowTitle = window.rawTitle else { return false }
                return BrowserProfile.profileName(fromWindowTitle: windowTitle, bundleIdentifier: bundleIdentifier) == browserProfileName
            }
        }

        return windows
    }
    
    func listAvailableAttributes() -> [String] {
        guard let element = element else {
            return []
        }
        
        var attributesRef: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &attributesRef)
        
        guard result == .success, let attributes = attributesRef as? [String] else {
            return []
        }
        
        return attributes
    }
    
    @discardableResult
    private func refreshRunningApplication() -> NSRunningApplication? {
        if let runningApplication,
           runningApplication.isTerminated == false {
            return runningApplication
        }
        
        guard let bundleIdentifier else {
            setRunningApplication(nil)
            return nil
        }
        
        guard let detectedRunningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        else {
            setRunningApplication(nil)
            return nil
        }
        
        setRunningApplication(detectedRunningApp)
        return detectedRunningApp
    }
    
    private func setRunningApplication(_ runningApplication: NSRunningApplication?) {
        self.runningApplication = runningApplication
        
        if let runningApplication {
            self.pid = runningApplication.processIdentifier
            self.element = AXUIElementCreateApplication(runningApplication.processIdentifier)
            self.title = runningApplication.localizedName ?? self.title
            return
        }
        
        self.pid = nil
        self.element = nil
    }
    
    private static func defaultOpenConfiguration(activates: Bool = true) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        return configuration
    }
    
}


enum ApplicationError: Error {
    case noBundleURL
    case openFailed
}
