import AppKit

// SetupWindowController — shown on first launch when macFUSE or ntfs-3g are missing.
// It guides the user through three phases:
//   1. Install deps (opens Terminal with pre-filled brew commands)
//   2. Approve the macFUSE system extension in System Settings
//   3. Restart macOS

final class SetupWindowController: NSWindowController {

    private var titleLabel: NSTextField!
    private var bodyLabel: NSTextField!
    private var step1Row: NSTextField!
    private var step2Row: NSTextField!
    private var statusLabel: NSTextField!
    private var primaryButton: NSButton!
    private var secondaryButton: NSButton!
    private var progressBar: NSProgressIndicator!

    // Called after setup completes so AppDelegate can refresh
    var onSetupComplete: (() -> Void)?

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 330),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NTFSWriter — Setup"
        window.center()
        self.init(window: window)
        buildUI()
        refreshState()
    }

    required init?(coder: NSCoder) { fatalError() }
    override init(window: NSWindow?) { super.init(window: window) }

    // MARK: - UI Construction

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        titleLabel = makeLabel("Setup Required", size: 17, bold: true)
        titleLabel.frame = NSRect(x: 24, y: 280, width: 432, height: 26)
        cv.addSubview(titleLabel)

        bodyLabel = makeLabel(
            "NTFSWriter needs two components to mount NTFS drives with write access.",
            size: 13
        )
        bodyLabel.frame = NSRect(x: 24, y: 248, width: 432, height: 20)
        cv.addSubview(bodyLabel)

        // Step rows
        step1Row = makeLabel("", size: 13)
        step1Row.frame = NSRect(x: 40, y: 208, width: 400, height: 20)
        cv.addSubview(step1Row)

        step2Row = makeLabel("", size: 13)
        step2Row.frame = NSRect(x: 40, y: 182, width: 400, height: 20)
        cv.addSubview(step2Row)

        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.frame = NSRect(x: 24, y: 160, width: 432, height: 1)
        cv.addSubview(divider)

        // Progress bar (hidden until install starts)
        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = true
        progressBar.frame = NSRect(x: 24, y: 135, width: 432, height: 12)
        progressBar.isHidden = true
        cv.addSubview(progressBar)

        // Status text
        statusLabel = makeLabel("", size: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 24, y: 112, width: 432, height: 18)
        cv.addSubview(statusLabel)

        // Note
        let note = makeLabel(
            "Homebrew is required. If you don't have it, the Terminal script will install it.",
            size: 11
        )
        note.textColor = .tertiaryLabelColor
        note.frame = NSRect(x: 24, y: 72, width: 432, height: 32)
        (note.cell as? NSTextFieldCell)?.wraps = true
        cv.addSubview(note)

        // Secondary button (left)
        secondaryButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        secondaryButton.bezelStyle = .rounded
        secondaryButton.frame = NSRect(x: 24, y: 24, width: 80, height: 32)
        cv.addSubview(secondaryButton)

        // Primary button (right)
        primaryButton = NSButton(title: "", target: self, action: #selector(primaryTapped))
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.frame = NSRect(x: 340, y: 24, width: 140, height: 32)
        cv.addSubview(primaryButton)
    }

    // MARK: - State machine

    private enum Phase {
        case needsInstall   // deps missing, not yet started
        case installing     // Terminal opened, waiting
        case needsApproval  // installed but extension not approved
        case ready          // everything good
    }

    private var phase: Phase = .needsInstall

    private func refreshState() {
        let fuseOK = DependencyChecker.isMacFUSEInstalled
        let ntfsOK = DependencyChecker.isNTFS3GInstalled
        let fuseLoaded = isMacFUSELoaded()

        step1Row.stringValue = fuseOK
            ? "✅  macFUSE  —  installed"
            : "○  macFUSE  —  not found"

        step2Row.stringValue = ntfsOK
            ? "✅  ntfs-3g  —  installed"
            : "○  ntfs-3g  —  not found"

        if fuseOK && ntfsOK && fuseLoaded {
            phase = .ready
            showReady()
        } else if fuseOK && ntfsOK && !fuseLoaded {
            phase = .needsApproval
            showApprovalNeeded()
        } else if phase == .installing {
            showInstalling()
        } else {
            phase = .needsInstall
            showNeedsInstall()
        }
    }

    private func showNeedsInstall() {
        statusLabel.stringValue = "Click below to install both components automatically."
        primaryButton.title = "Install in Terminal…"
        primaryButton.isEnabled = true
        secondaryButton.isHidden = false
        progressBar.isHidden = true
        progressBar.stopAnimation(nil)
    }

    private func showInstalling() {
        statusLabel.stringValue = "Waiting for install to finish… click Check when done."
        primaryButton.title = "Check Again"
        primaryButton.isEnabled = true
        secondaryButton.isHidden = true
        progressBar.isHidden = false
        progressBar.startAnimation(nil)
    }

    private func showApprovalNeeded() {
        progressBar.isHidden = true
        progressBar.stopAnimation(nil)
        statusLabel.stringValue = "Approve macFUSE in System Settings, then restart your Mac."
        statusLabel.textColor = .systemOrange
        primaryButton.title = "Open System Settings"
        primaryButton.isEnabled = true
        secondaryButton.isHidden = false
        secondaryButton.title = "I'll do it later"
        secondaryButton.action = #selector(dismissSetup)
    }

    private func showReady() {
        progressBar.isHidden = true
        progressBar.stopAnimation(nil)
        statusLabel.stringValue = "All set! NTFSWriter is ready to use."
        statusLabel.textColor = .systemGreen
        primaryButton.title = "Done"
        primaryButton.isEnabled = true
        secondaryButton.isHidden = true
    }

    // MARK: - Actions

    @objc private func primaryTapped() {
        switch phase {
        case .needsInstall:
            openTerminalInstall()
            phase = .installing
            showInstalling()

        case .installing:
            // "Check Again"
            refreshState()

        case .needsApproval:
            openSystemSettings()

        case .ready:
            dismissSetup()
            onSetupComplete?()
        }
    }

    private func openTerminalInstall() {
        let brew = findBrew() ?? "brew"   // if brew not found, will fail visibly in Terminal

        // Single shell command: install homebrew if missing, then macFUSE and ntfs-3g
        let cmd = [
            "echo '=== NTFSWriter Setup ==='",
            // Install Homebrew if absent
            "command -v brew &>/dev/null || /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
            // Ensure brew is on PATH (Apple Silicon)
            "eval \"$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)\"",
            "eval \"$(/usr/local/bin/brew shellenv 2>/dev/null || true)\"",
            // Install packages
            "\(brew) install --cask macfuse",
            "\(brew) tap gromgit/homebrew-fuse",
            "\(brew) install gromgit/homebrew-fuse/ntfs-3g-mac",
            "echo ''",
            "echo '✓ Done — return to NTFSWriter and click Check Again'"
        ].joined(separator: " && ")

        // Escape for AppleScript double-quoted string
        let escaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        NSAppleScript(source: appleScript)?.executeAndReturnError(nil)
    }

    private func openSystemSettings() {
        // Deep-link directly to Privacy & Security in System Settings
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
        statusLabel.stringValue = "In System Settings: click Allow next to macFUSE, then restart."
    }

    @objc private func dismissSetup() {
        close()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func isMacFUSELoaded() -> Bool {
        // /dev/macfuse exists only when the kernel extension is approved and loaded
        FileManager.default.fileExists(atPath: "/dev/macfuse")
    }

    private func findBrew() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func makeLabel(_ text: String, size: CGFloat, bold: Bool = false) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = bold
            ? NSFont.boldSystemFont(ofSize: size)
            : NSFont.systemFont(ofSize: size)
        tf.isEditable = false
        tf.isBordered = false
        tf.backgroundColor = .clear
        return tf
    }
}
