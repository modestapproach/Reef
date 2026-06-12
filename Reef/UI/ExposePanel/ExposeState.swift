//
//  ExposeState.swift
//  Reef
//
//  State for the per-app exposé grid.
//

import AppKit
import Foundation

@MainActor
final class ExposeState: ObservableObject {
    @Published var applicationTitle: String = ""
    @Published var windows: [Window] = []
    @Published var thumbnails: [CGWindowID: CGImage] = [:]
    @Published var selectedIndex: Int = 0
    @Published var columns: Int = 1

    private(set) var appIcon: NSImage?

    func setApplication(_ application: Application) {
        applicationTitle = application.displayTitle
        appIcon = application.runningApplication?.icon
            ?? application.bundleUrl.map { NSWorkspace.shared.icon(forFile: $0.path) }

        // Stable creation-order, matching instant switching.
        windows = application.getWindows()
            .sorted { ($0.cgWindowID ?? 0) < ($1.cgWindowID ?? 0) }
        columns = Self.columnCount(for: windows.count)
        thumbnails = [:]
        selectedIndex = 0
    }

    var rows: Int {
        guard !windows.isEmpty else { return 0 }
        return (windows.count + columns - 1) / columns
    }

    var currentWindow: Window? {
        guard !windows.isEmpty, selectedIndex < windows.count else { return nil }
        return windows[selectedIndex]
    }

    func cycleNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    func moveSelection(byColumns deltaColumns: Int, byRows deltaRows: Int) {
        guard !windows.isEmpty else { return }

        let target = selectedIndex + deltaColumns + (deltaRows * columns)
        guard (0..<windows.count).contains(target) else { return }
        selectedIndex = target
    }

    func reset() {
        applicationTitle = ""
        windows = []
        thumbnails = [:]
        selectedIndex = 0
        columns = 1
        appIcon = nil
    }

    static func columnCount(for windowCount: Int) -> Int {
        switch windowCount {
        case ...1: return 1
        case 2...4: return 2
        case 5...9: return 3
        default: return 4
        }
    }
}
