//
//  ExposeOverlayPanel.swift
//  Reef
//
//  Borderless full-screen overlay that hosts the exposé tiles.
//

import AppKit

final class ExposeOverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior.insert(.fullScreenAuxiliary)
        self.collectionBehavior.insert(.canJoinAllSpaces)
        self.isMovable = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = true
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}
