import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController?
    private var diskMonitor: DiskMonitor?
    private let mounter = NTFSMounter()
    private var setupWindow: SetupWindowController?

    // Single source of truth for drive state
    private var drives: [String: NTFSDrive] = [:]  // keyed by bsdName

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: LSUIElement in Info.plist is the primary mechanism
        NSApp.setActivationPolicy(.accessory)

        let menu = MenuBarController()
        menu.onMountDrive = { [weak self] id in self?.mountDrive(id) }
        menu.onEjectDrive = { [weak self] id in self?.ejectDrive(id) }
        menu.onShowSetup  = { [weak self] in self?.showSetupWizard() }
        menuBarController = menu

        let monitor = DiskMonitor()
        monitor.onDriveAppeared    = { [weak self] in self?.driveAppeared($0, $1, $2, $3) }
        monitor.onDriveDisappeared = { [weak self] in self?.driveDisappeared($0) }
        diskMonitor = monitor
        monitor.start()

        // Show setup wizard if dependencies are missing
        if !DependencyChecker.allInstalled {
            showSetupWizard()
        }

        menu.updateDrives([])
    }

    // MARK: - DiskMonitor callbacks (called on main thread)

    private func driveAppeared(_ bsdName: String, _ volumeName: String, _ mountPoint: String, _ devicePath: String) {
        guard drives[bsdName] == nil else { return }  // Already tracking this drive
        let drive = NTFSDrive(
            id: bsdName,
            volumeName: volumeName,
            mountPoint: mountPoint,
            devicePath: devicePath,
            isMounted: false,
            isProcessing: false
        )
        drives[bsdName] = drive
        menuBarController?.updateDrives(Array(drives.values))

        // Auto-mount if the preference is enabled
        if Preferences.shared.autoMount {
            mountDrive(bsdName)
        }
    }

    private func driveDisappeared(_ bsdName: String) {
        // Don't remove drives that are mid-cycle (unmounted for ntfs-3g remount).
        // After a successful ntfs-3g mount the drive stays in the list as isMounted=true.
        // Physical disconnect while processing is an edge case we accept losing.
        if let drive = drives[bsdName], drive.isProcessing { return }
        drives.removeValue(forKey: bsdName)
        menuBarController?.updateDrives(Array(drives.values))
    }

    // MARK: - User actions

    private func mountDrive(_ bsdName: String) {
        guard var drive = drives[bsdName], !drive.isProcessing else { return }
        drive.isProcessing = true
        drives[bsdName] = drive
        menuBarController?.updateDrives(Array(drives.values))

        mounter.mount(drive: drive) { [weak self] result in
            guard let self = self else { return }
            guard var d = self.drives[bsdName] else { return }
            d.isProcessing = false
            switch result {
            case .success:
                d.isMounted = true
            case .failure(let error):
                if case MountError.userCancelled = error { break }
                self.showError(error.localizedDescription, for: d.volumeName)
            }
            self.drives[bsdName] = d
            self.menuBarController?.updateDrives(Array(self.drives.values))
        }
    }

    private func ejectDrive(_ bsdName: String) {
        guard var drive = drives[bsdName], !drive.isProcessing else { return }
        drive.isProcessing = true
        drives[bsdName] = drive
        menuBarController?.updateDrives(Array(drives.values))

        mounter.unmount(drive: drive) { [weak self] result in
            guard let self = self else { return }
            guard var d = self.drives[bsdName] else { return }
            d.isProcessing = false
            switch result {
            case .success:
                d.isMounted = false
                // Drive will disappear naturally via DA after the user physically disconnects.
                // If they just ejected software-wise, keep it in the list as read-only.
            case .failure(let error):
                self.showError(error.localizedDescription, for: d.volumeName)
            }
            self.drives[bsdName] = d
            self.menuBarController?.updateDrives(Array(self.drives.values))
        }
    }

    // MARK: - Alerts

    private func showError(_ message: String, for driveName: String) {
        let alert = NSAlert()
        alert.messageText = "NTFS Writer — \(driveName)"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func showSetupWizard() {
        if setupWindow == nil {
            let wc = SetupWindowController()
            wc.onSetupComplete = { [weak self] in
                self?.setupWindow = nil
                self?.diskMonitor?.start()
            }
            setupWindow = wc
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.showWindow(nil)
    }
}
