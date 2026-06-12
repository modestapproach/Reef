//
//  ExposeState.swift
//  Reef
//
//  State for the per-app exposé overlay.
//

import AppKit
import Foundation

@MainActor
final class ExposeState: ObservableObject {
    @Published var applicationTitle: String = ""
    @Published var windows: [Window] = []
    @Published var thumbnails: [CGWindowID: CGImage] = [:]
    @Published var selectedIndex: Int = 0
    @Published var hasScreenAccess: Bool = true

    private(set) var appIcon: NSImage?

    // At most this many tiles per row; rows are balanced from it.
    private static let maxTilesPerRow = 4

    func setApplication(_ application: Application) {
        applicationTitle = application.displayTitle
        appIcon = application.runningApplication?.icon
            ?? application.bundleUrl.map { NSWorkspace.shared.icon(forFile: $0.path) }

        // Stable creation-order, matching instant switching.
        windows = application.getWindows()
            .sorted { ($0.cgWindowID ?? 0) < ($1.cgWindowID ?? 0) }
        thumbnails = [:]
        selectedIndex = 0
        hasScreenAccess = WindowThumbnailProvider.hasScreenCaptureAccess
    }

    var rows: Int {
        guard !windows.isEmpty else { return 0 }
        return (windows.count + Self.maxTilesPerRow - 1) / Self.maxTilesPerRow
    }

    var columns: Int {
        guard !windows.isEmpty else { return 1 }
        return (windows.count + rows - 1) / rows
    }

    // Window indices chunked into balanced rows for tiling.
    var rowChunks: [[Int]] {
        let indices = Array(windows.indices)
        guard !indices.isEmpty else { return [] }
        return stride(from: 0, to: indices.count, by: columns).map {
            Array(indices[$0..<min($0 + columns, indices.count)])
        }
    }

    var currentWindow: Window? {
        guard !windows.isEmpty, selectedIndex < windows.count else { return nil }
        return windows[selectedIndex]
    }

    func cycleNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    func removeWindow(at index: Int) {
        guard windows.indices.contains(index) else { return }
        windows.remove(at: index)
        selectedIndex = min(selectedIndex, max(0, windows.count - 1))
    }

    // Re-reads the window list keeping existing thumbnails, and moves the
    // selection to the first window that wasn't there before (if any).
    func refreshWindows(_ application: Application, selectingNewFrom previousIDs: Set<CGWindowID>) {
        windows = application.getWindows()
            .sorted { ($0.cgWindowID ?? 0) < ($1.cgWindowID ?? 0) }

        let currentIDs = Set(windows.compactMap(\.cgWindowID))
        thumbnails = thumbnails.filter { currentIDs.contains($0.key) }

        if let newIndex = windows.firstIndex(where: { window in
            window.cgWindowID.map { !previousIDs.contains($0) } ?? false
        }) {
            selectedIndex = newIndex
        } else {
            selectedIndex = min(selectedIndex, max(0, windows.count - 1))
        }
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
        appIcon = nil
    }
}
