//
//  PreferencesGeneralView.swift
//  Reef
//
//  Created by Xander Gouws on 26-01-2026.
//

import SwiftUI
import ServiceManagement
import ApplicationServices

struct PreferencesGeneralView: View {
    @AppStorage("launchOnLogin") private var launchOnLogin = true
//    @AppStorage("hideMenubarIcon") private var hideMenubarIcon = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("defaultNumberOrder") private var defaultNumberOrder = "rightHanded"
    @AppStorage("instantWindowSwitching") private var instantWindowSwitching = false
    @AppStorage("separateBrowserProfiles") private var separateBrowserProfiles = false
    @AppStorage("openNewWindowIfNoneExist") private var openNewWindowIfNoneExist = false
    
    @State private var hasAccessibilityPermission = AXIsProcessTrusted()
    
    // Timer to poll for accessibility permission changes
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Form {
            // Accessibility Permission Warning
            if !hasAccessibilityPermission {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .imageScale(.large)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Permission Required")
                            .fontWeight(.medium)
                        Text("System Settings → Privacy & Security → Accessibility")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Open Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Section {
                Toggle("Launch Reef at login", isOn: $launchOnLogin)
                    .onChange(of: launchOnLogin) { _, newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
                
//                Toggle("Hide menubar icon", isOn: $hideMenubarIcon)
                
                
                Picker("Default number order:", selection: $defaultNumberOrder) {
                    Text("Right handed (0, 9, ..., 1)").tag("rightHanded")
                    Text("Left handed (1, ..., 9, 0)").tag("leftHanded")
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Number order sets the order in which numbers are displayed in the menubar")
            }

            Section {
                Toggle("Switch windows instantly", isOn: $instantWindowSwitching)

                Toggle("Treat browser profiles as separate apps", isOn: $separateBrowserProfiles)

                Toggle("Open a new window if none exist", isOn: $openNewWindowIfNoneExist)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instant switching focuses the bound app right away, and each repeat press jumps straight to its next window — no switcher panel.")
                    Text("With separate browser profiles, binding Chrome, Edge, Brave, or Vivaldi captures the active profile, and its number only switches between that profile's windows.")
                    Text("Opening a new window simulates clicking the app's Dock icon when you switch to it and it has no windows open (falling back to ⌘N).")
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: hasAccessibilityPermission ? 320 : 385)
        .onReceive(timer) { _ in
            // Poll for permission changes
            hasAccessibilityPermission = AXIsProcessTrusted()
        }
    }
    
    private func openAccessibilitySettings() {
        // Open System Settings to the Privacy & Security > Accessibility pane
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
                // Revert the toggle if it failed
                DispatchQueue.main.async {
                    launchOnLogin = !enabled
                }
            }
        } else {
            // Legacy API for macOS 12 and earlier
            SMLoginItemSetEnabled(Bundle.main.bundleIdentifier! as CFString, enabled)
        }
    }
}

#Preview {
    PreferencesGeneralView()
}
