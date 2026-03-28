import Foundation
import ServiceManagement

// Preferences — thin wrapper around UserDefaults.
// All reads/writes are synchronous and safe to call from the main thread.

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case autoMount    = "autoMountOnConnect"
        case launchAtLogin = "launchAtLogin"
    }

    // Automatically mount NTFS drives writable when plugged in (no user click needed)
    var autoMount: Bool {
        get { defaults.bool(forKey: Key.autoMount.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoMount.rawValue) }
    }

    // Register / unregister as a Login Item using ServiceManagement
    var launchAtLogin: Bool {
        get {
            if #available(macOS 13, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Pre-macOS 13: read the stored preference; actual state managed separately
                return defaults.bool(forKey: Key.launchAtLogin.rawValue)
            }
        }
        set {
            defaults.set(newValue, forKey: Key.launchAtLogin.rawValue)
            applyLaunchAtLogin(newValue)
        }
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[Preferences] Launch-at-login toggle failed: %@", error.localizedDescription)
            }
        } else {
            // macOS 12 fallback: write a LaunchAgent plist
            applyLaunchAgentPlist(enable)
        }
    }

    // macOS 12 fallback: install/remove a LaunchAgent plist
    private func applyLaunchAgentPlist(_ enable: Bool) {
        guard let bundlePath = Bundle.main.executablePath else { return }
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistPath = launchAgentsDir.appendingPathComponent("com.ntfswriter.app.plist")

        if enable {
            try? FileManager.default.createDirectory(at: launchAgentsDir,
                                                     withIntermediateDirectories: true)
            let plist: NSDictionary = [
                "Label": "com.ntfswriter.app",
                "ProgramArguments": [bundlePath],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            plist.write(to: plistPath, atomically: true)
        } else {
            try? FileManager.default.removeItem(at: plistPath)
        }
    }
}
