//
//  BrowserProfile.swift
//  Reef
//

import Foundation

// Chromium-based browsers append the active profile name to their window
// titles ("Tab Title - Google Chrome - Work") whenever more than one profile
// exists. Reef uses that to tell profiles apart and treat each one as its
// own application.
enum BrowserProfile {
    private static let bindingSeparator = "::profile::"

    // Bundle ID -> the name the browser uses for itself in window titles.
    private static let titleMarkers: [String: String] = [
        "com.google.Chrome": "Google Chrome",
        "com.google.Chrome.beta": "Google Chrome Beta",
        "com.google.Chrome.dev": "Google Chrome Dev",
        "com.google.Chrome.canary": "Google Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.brave.Browser": "Brave",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    // Bundle ID -> user data directory under ~/Library/Application Support.
    private static let userDataDirectories: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    static func profileName(fromWindowTitle title: String, bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier,
              let marker = titleMarkers[bundleIdentifier] else {
            return nil
        }

        guard let range = title.range(of: " - \(marker) - ", options: .backwards) else {
            return nil
        }

        let name = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // MARK: - Binding encoding

    // Profile-specific bindings are stored as "bundleID::profile::Name".
    // Plain bundle identifiers keep working unchanged.
    static func encodeBinding(bundleIdentifier: String, profileName: String?) -> String {
        guard let profileName else { return bundleIdentifier }
        return bundleIdentifier + bindingSeparator + profileName
    }

    static func decodeBinding(_ binding: String) -> (bundleIdentifier: String, profileName: String?) {
        guard let range = binding.range(of: bindingSeparator) else {
            return (binding, nil)
        }

        let bundleIdentifier = String(binding[..<range.lowerBound])
        let profileName = String(binding[range.upperBound...])
        return (bundleIdentifier, profileName.isEmpty ? nil : profileName)
    }

    // MARK: - Launching

    // Resolves a profile's display name ("Work") to its on-disk directory
    // ("Profile 1") by reading the browser's Local State file, so a new
    // window can be opened with --profile-directory.
    static func profileDirectory(named profileName: String, bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier,
              let dataDirectory = userDataDirectories[bundleIdentifier],
              let applicationSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first else {
            return nil
        }

        let localStateURL = applicationSupport
            .appendingPathComponent(dataDirectory, isDirectory: true)
            .appendingPathComponent("Local State")

        guard let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileSection = json["profile"] as? [String: Any],
              let infoCache = profileSection["info_cache"] as? [String: Any] else {
            return nil
        }

        for (directory, info) in infoCache {
            if let info = info as? [String: Any],
               let name = info["name"] as? String,
               name == profileName {
                return directory
            }
        }

        return nil
    }
}
