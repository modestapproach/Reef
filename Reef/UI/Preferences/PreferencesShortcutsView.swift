//
//  PreferencesShortcutsView.swift
//  Reef
//
//  Created by Xander Gouws on 26-01-2026.
//

import SwiftUI

struct PreferencesShortcutsView: View {
    @StateObject private var modifierManager: ModifierManager = {
        if let manager = AppDelegate.modifierManager {
            return manager
        }
        return ModifierManager()
    }()
    @State private var showingResetConfirmation = false
    @State private var showingExposeInfo = false

    private var disabledCapabilityNote: String? {
        var disabledCapabilities: [String] = []
        if !modifierManager.exposeEnabled {
            disabledCapabilities.append("exposé switching")
        }
        if !modifierManager.activateEnabled {
            disabledCapabilities.append("fast switching")
        }
        if !modifierManager.bindEnabled {
            disabledCapabilities.append("binding")
        }
        if !modifierManager.profileEnabled {
            disabledCapabilities.append("profile switching")
        }

        guard !disabledCapabilities.isEmpty else {
            return nil
        }

        let capabilityList: String
        switch disabledCapabilities.count {
        case 1:
            capabilityList = disabledCapabilities[0]
        case 2:
            capabilityList = "\(disabledCapabilities[0]) and \(disabledCapabilities[1])"
        default:
            let prefix = disabledCapabilities.dropLast().joined(separator: ", ")
            capabilityList = "\(prefix), and \(disabledCapabilities.last!)"
        }

        let verb = disabledCapabilities.count == 1 ? "is" : "are"
        return "Note: Keyboard \(capabilityList) \(verb) disabled"
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Use the selection boxes below to customize modifier keys for switching and binding apps, and profile switching.\n\nTo disable an action, deselect all modifier checkboxes in that row.")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Button("Reset to defaults") {
                        showingResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
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
                        HStack(spacing: 4) {
                            Text(verbatim: "Switch app - Exposé")

                            Button {
                                showingExposeInfo.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showingExposeInfo, arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("While the exposé grid is open")
                                        .font(.headline)

                                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                                        GridRow { Text("↩").fontWeight(.medium); Text("focus the selected window") }
                                        GridRow { Text("N").fontWeight(.medium); Text("open a new window (in the bound browser profile, if any)") }
                                        GridRow { Text("W").fontWeight(.medium); Text("close the selected window") }
                                        GridRow { Text("Q").fontWeight(.medium); Text("quit the app") }
                                        GridRow { Text("esc").fontWeight(.medium); Text("cancel") }
                                    }

                                    Text("Tap the chord to browse with the arrow keys; hold it and release to switch immediately.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .frame(width: 320)
                            }
                        }
                        .frame(minWidth: 150, alignment: .leading)
                        Toggle("", isOn: $modifierManager.exposeControl).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.exposeOption).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.exposeShift).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.exposeCommand).toggleStyle(.checkbox)
                    }

                    GridRow {
                        Text(verbatim: "Switch app - Fast")
                            .frame(minWidth: 150, alignment: .leading)
                        Toggle("", isOn: $modifierManager.activateControl).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.activateOption).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.activateShift).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.activateCommand).toggleStyle(.checkbox)
                    }

                    GridRow {
                        Text(verbatim: "Switch profile")
                            .frame(minWidth: 150, alignment: .leading)
                        Toggle("", isOn: $modifierManager.profileControl).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.profileOption).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.profileShift).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.profileCommand).toggleStyle(.checkbox)
                    }

                    GridRow {
                        Text(verbatim: "Bind app")
                            .frame(minWidth: 150, alignment: .leading)
                        Toggle("", isOn: $modifierManager.bindControl).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.bindOption).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.bindShift).toggleStyle(.checkbox)
                        Toggle("", isOn: $modifierManager.bindCommand).toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 8)

                if let disabledCapabilityNote {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Text(disabledCapabilityNote)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            } footer: {
                Text("⌃ Control  •  ⌥ Option  •  ⇧ Shift  •  ⌘ Command")
            }
        }
        .formStyle(.grouped)
        .frame(height: !modifierManager.activateEnabled || !modifierManager.bindEnabled || !modifierManager.profileEnabled || !modifierManager.exposeEnabled ? 430 : 395)
        .alert("Reset shortcut modifiers?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                modifierManager.resetToDefaults()
            }
        } message: {
            Text(verbatim: """
            Modifiers will be reset to

            Exposé:\t\t⌥ + ⌘
            Fast:\t\t⌃ + ⌥
            Profile:\t\t⌃ + ⌥ + ⇧
            Bind:\t\t⌃ + ⌥ + ⇧ + ⌘
            """)
            .font(.system(.body, design: .monospaced))
        }
    }
}

#Preview {
    PreferencesShortcutsView()
}
