import Foundation

struct DependencyChecker {

    // Known ntfs-3g install locations (Intel + Apple Silicon Homebrew)
    static let ntfs3gCandidates = [
        "/usr/local/bin/ntfs-3g",
        "/opt/homebrew/bin/ntfs-3g",
        "/usr/local/sbin/ntfs-3g",
        "/opt/homebrew/sbin/ntfs-3g"
    ]

    static var ntfs3gPath: String? {
        ntfs3gCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isMacFUSEInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Filesystems/macfuse.fs")
    }

    static var isNTFS3GInstalled: Bool {
        ntfs3gPath != nil
    }

    static var allInstalled: Bool {
        isMacFUSEInstalled && isNTFS3GInstalled
    }

    static var missingList: [String] {
        var missing: [String] = []
        if !isMacFUSEInstalled { missing.append("macFUSE") }
        if !isNTFS3GInstalled  { missing.append("ntfs-3g") }
        return missing
    }

    static var installGuide: String {
        """
        Install required dependencies:

        1. brew install --cask macfuse
        2. brew install ntfs-3g

        After installing macFUSE, go to:
        System Settings → Privacy & Security
        and approve the system extension, then restart.
        """
    }
}
