//
//  PreferencesCapsLockView.swift
//  Reef
//
//  Caps Lock remapping: while held, Caps Lock acts as a chosen modifier
//  combination (no Karabiner-Elements required).
//

import SwiftUI

struct PreferencesCapsLockView: View {
    @AppStorage("capsLockRemapEnabled") private var remapEnabled = false
    @AppStorage("capsLockControl") private var capsControl = true
    @AppStorage("capsLockOption") private var capsOption = true
    @AppStorage("capsLockShift") private var capsShift = false
    @AppStorage("capsLockCommand") private var capsCommand = false

    @StateObject private var manager: CapsLockRemapManager = {
        if let manager = AppDelegate.capsLockManager {
            return manager
        }
        return CapsLockRemapManager()
    }()

    // Timer to poll for permission changes
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var needsPermission: Bool {
        remapEnabled && !manager.hasInputMonitoring
    }

    var body: some View {
        Form {
            // Input Monitoring Permission Warning
            if needsPermission {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .imageScale(.large)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Input Monitoring Permission Required")
                            .fontWeight(.medium)
                        Text("Needed to watch the Caps Lock key — System Settings → Privacy & Security → Input Monitoring. macOS may only apply the grant after a relaunch.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        Button("Open Settings") {
                            openInputMonitoringSettings()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Relaunch Reef") {
                            relaunchReef()
                        }
                    }
                }
            }

            Section {
                Toggle("Remap Caps Lock", isOn: $remapEnabled)
            } footer: {
                Text("While on, Caps Lock no longer toggles capitals (and its light stays off). Held together with other keys, it acts as the modifiers selected below.")
            }

            Section {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        Text(verbatim: "Modifier keys")
                            .fontWeight(.medium)
                            .frame(minWidth: 150, alignment: .leading)
                        Text("⌃").fontWeight(.medium)
                        Text("⌥").fontWeight(.medium)
                        Text("⇧").fontWeight(.medium)
                        Text("⌘").fontWeight(.medium)
                    }

                    Divider()

                    GridRow {
                        Text(verbatim: "Caps Lock acts as")
                            .frame(minWidth: 150, alignment: .leading)
                        Toggle("", isOn: $capsControl).toggleStyle(.checkbox)
                        Toggle("", isOn: $capsOption).toggleStyle(.checkbox)
                        Toggle("", isOn: $capsShift).toggleStyle(.checkbox)
                        Toggle("", isOn: $capsCommand).toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 8)
                .disabled(!remapEnabled)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⌃ Control  •  ⌥ Option  •  ⇧ Shift  •  ⌘ Command")
                    Text("All four selected makes Caps Lock a \"hyper key\" — pair it with a Reef shortcut for one-handed switching.")
                    Text("If Karabiner-Elements is running, its own Caps Lock mapping may override this one.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: needsPermission ? 480 : 390)
        .onChange(of: remapEnabled) { applyChanges() }
        .onChange(of: capsControl) { applyChanges() }
        .onChange(of: capsOption) { applyChanges() }
        .onChange(of: capsShift) { applyChanges() }
        .onChange(of: capsCommand) { applyChanges() }
        .onReceive(timer) { _ in
            manager.refreshAccess()
        }
    }

    private func applyChanges() {
        manager.apply()
    }

    private func openInputMonitoringSettings() {
        // Open System Settings to the Privacy & Security > Input Monitoring pane
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // The Input Monitoring verdict can be cached per process launch, so a
    // fresh grant may only take effect in a new instance.
    private func relaunchReef() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

#Preview {
    PreferencesCapsLockView()
}
