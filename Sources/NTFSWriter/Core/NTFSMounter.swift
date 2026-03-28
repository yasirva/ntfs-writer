import Foundation
import AppKit

// NTFSMounter handles the privileged mount/unmount cycle.
//
// Strategy:
//  1. Write a bash script to /tmp (avoids AppleScript string-escaping issues)
//  2. Execute it via `do shell script "..." with administrator privileges`
//     which shows the standard macOS password dialog
//  3. macOS caches the auth grant for ~5 minutes (like sudo)
//
// Safety: the script uses `|| true` so a failed unmount (drive already
// unmounted) never prevents the subsequent ntfs-3g mount from running.

enum MountError: Error, LocalizedError {
    case ntfs3gNotFound
    case scriptWriteFailed
    case userCancelled
    case mountFailed(String)
    case unmountFailed(String)

    var errorDescription: String? {
        switch self {
        case .ntfs3gNotFound:
            return "ntfs-3g not found. Run: brew tap gromgit/homebrew-fuse && brew install gromgit/homebrew-fuse/ntfs-3g-mac"
        case .scriptWriteFailed:
            return "Could not write temporary mount script."
        case .userCancelled:
            return "Authentication was cancelled."
        case .mountFailed(let msg):
            return "Mount failed: \(msg)"
        case .unmountFailed(let msg):
            return "Unmount failed: \(msg)"
        }
    }
}

final class NTFSMounter {

    func mount(drive: NTFSDrive, completion: @escaping (Result<Void, MountError>) -> Void) {
        guard let ntfs3g = DependencyChecker.ntfs3gPath else {
            completion(.failure(.ntfs3gNotFound))
            return
        }

        let mountPoint = drive.mountPoint.isEmpty
            ? "/Volumes/\(drive.volumeName)"
            : drive.mountPoint

        // Build script — single quotes around paths guard against spaces in volume names
        let script = """
        #!/bin/bash
        set -e
        diskutil unmount '\(drive.devicePath)' 2>/dev/null || true
        mkdir -p '\(mountPoint)'
        nohup '\(ntfs3g)' '\(drive.devicePath)' '\(mountPoint)' \\
            -o local,allow_other,noappledouble,nolocalcaches \\
            >/tmp/ntfs-writer-mount.log 2>&1 &
        # Wait up to 10s for the mount to appear
        for i in $(seq 1 20); do
            if /sbin/mount | grep -qF '\(mountPoint)'; then
                exit 0
            fi
            sleep 0.5
        done
        echo "Timeout waiting for mount" >&2
        exit 1
        """

        runPrivilegedScript(script) { result in
            switch result {
            case .success:      completion(.success(()))
            case .failure(let e): completion(.failure(.mountFailed(e.localizedDescription)))
            }
        }
    }

    func unmount(drive: NTFSDrive, completion: @escaping (Result<Void, MountError>) -> Void) {
        let script = """
        #!/bin/bash
        sync
        diskutil unmount '\(drive.mountPoint)' 2>/dev/null \\
            || umount '\(drive.mountPoint)' 2>/dev/null \\
            || diskutil unmount force '\(drive.mountPoint)'
        """

        runPrivilegedScript(script) { result in
            switch result {
            case .success:        completion(.success(()))
            case .failure(let e): completion(.failure(.unmountFailed(e.localizedDescription)))
            }
        }
    }

    // MARK: - Private

    private func runPrivilegedScript(_ script: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Write to /tmp with a unique name; short prefix avoids path-length issues in osascript
        let scriptPath = "/tmp/ntfsw_\(Int.random(in: 100_000...999_999)).sh"

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
        } catch {
            completion(.failure(MountError.scriptWriteFailed))
            return
        }

        // AppleScript string — the script path only contains /tmp/ntfsw_NNNNNN.sh, safe to embed
        let appleScript = "do shell script \"\(scriptPath)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var errDict: NSDictionary?
            NSAppleScript(source: appleScript)?.executeAndReturnError(&errDict)
            try? FileManager.default.removeItem(atPath: scriptPath)

            DispatchQueue.main.async {
                if let errDict = errDict {
                    // Error number -128 = user pressed Cancel in the auth dialog
                    let code = errDict["NSAppleScriptErrorNumber"] as? Int ?? 0
                    if code == -128 {
                        completion(.failure(MountError.userCancelled))
                    } else {
                        let msg = errDict["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                        completion(.failure(MountError.mountFailed(msg)))
                    }
                } else {
                    completion(.success(()))
                }
            }
        }
    }
}
