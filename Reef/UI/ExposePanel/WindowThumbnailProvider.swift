//
//  WindowThumbnailProvider.swift
//  Reef
//
//  Captures window thumbnails for the exposé grid via ScreenCaptureKit.
//

import AppKit
import ScreenCaptureKit

enum WindowThumbnailProvider {
    // Screen Recording permission is required for real thumbnails. The first
    // call triggers the system prompt; until granted (and the app relaunched)
    // captures fail and the exposé grid falls back to icon cards.
    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenCaptureAccess() {
        CGRequestScreenCaptureAccess()
    }

    // Captures each window and delivers images one at a time so the grid can
    // fill in progressively.
    static func capture(
        windowIDs: [CGWindowID],
        maxPixelWidth: CGFloat = 640,
        onImage: @MainActor @escaping (CGWindowID, CGImage) -> Void
    ) async {
        guard hasScreenCaptureAccess else {
            requestScreenCaptureAccess()
            return
        }

        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return
        }

        for windowID in windowIDs {
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                continue
            }

            let configuration = SCStreamConfiguration()
            let scale = min(1, maxPixelWidth / max(scWindow.frame.width, 1))
            configuration.width = max(1, Int(scWindow.frame.width * scale))
            configuration.height = max(1, Int(scWindow.frame.height * scale))
            configuration.showsCursor = false

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)

            guard let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) else {
                continue
            }

            await onImage(windowID, image)
        }
    }
}
