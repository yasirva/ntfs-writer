import AppKit

// MenuBarController owns the NSStatusItem and rebuilds the NSMenu
// whenever the drives list changes. It communicates user actions
// back to AppDelegate via closures (avoids tight coupling).

final class MenuBarController {

    var onMountDrive: ((String) -> Void)?
    var onEjectDrive: ((String) -> Void)?
    var onShowSetup: (() -> Void)?

    private let statusItem: NSStatusItem
    private var drives: [NTFSDrive] = []
    private let prefs = Preferences.shared

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let icon = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "NTFS Writer") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.title = "N"
            }
            button.toolTip = "NTFS Writer"
        }
    }

    // Must be called on the main thread.
    func updateDrives(_ newDrives: [NTFSDrive]) {
        drives = newDrives.sorted { $0.volumeName.localizedCompare($1.volumeName) == .orderedAscending }
        rebuildMenu()
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if drives.isEmpty {
            let empty = NSMenuItem(title: "No NTFS drives detected", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for drive in drives {
                addItems(for: drive, to: menu)
                menu.addItem(.separator())
            }
        }

        if !DependencyChecker.allInstalled {
            let warn = NSMenuItem(
                title: "⚠️ Setup required — click to fix",
                action: #selector(setupTapped),
                keyEquivalent: ""
            )
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        // ── Preferences ───────────────────────────────────────
        let autoItem = NSMenuItem(
            title: "Auto-Mount on Connect",
            action: #selector(toggleAutoMount),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.state = prefs.autoMount ? .on : .off
        menu.addItem(autoItem)

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = prefs.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NTFSWriter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func addItems(for drive: NTFSDrive, to menu: NSMenu) {
        let header = NSMenuItem(title: "💾  \(drive.volumeName)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if drive.isProcessing {
            let processing = NSMenuItem(title: "   ⏳ Please wait…", action: nil, keyEquivalent: "")
            processing.isEnabled = false
            menu.addItem(processing)
            return
        }

        if drive.isMounted {
            let status = NSMenuItem(title: "   ✅ Write access enabled", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)

            let eject = NSMenuItem(title: "   Safely Eject", action: #selector(ejectTapped(_:)), keyEquivalent: "")
            eject.target = self
            eject.representedObject = drive.id
            menu.addItem(eject)
        } else {
            let status = NSMenuItem(title: "   ○ Read-only (macOS default)", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)

            let mount = NSMenuItem(title: "   Enable Write Access", action: #selector(mountTapped(_:)), keyEquivalent: "")
            mount.target = self
            mount.representedObject = drive.id
            menu.addItem(mount)
        }
    }

    // MARK: - Drive actions

    @objc private func mountTapped(_ sender: NSMenuItem) {
        guard let driveId = sender.representedObject as? String else { return }
        onMountDrive?(driveId)
    }

    @objc private func ejectTapped(_ sender: NSMenuItem) {
        guard let driveId = sender.representedObject as? String else { return }
        onEjectDrive?(driveId)
    }

    // MARK: - Preference toggles

    @objc private func toggleAutoMount() {
        prefs.autoMount.toggle()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        prefs.launchAtLogin.toggle()
        rebuildMenu()
    }

    // MARK: - Dependency info

    @objc private func setupTapped() {
        onShowSetup?()
    }
}
