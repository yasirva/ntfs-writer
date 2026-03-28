import Foundation
import DiskArbitration

// DiskMonitor watches for NTFS drives appearing and disappearing.
// It fires plain-data callbacks — all state management lives in AppDelegate.
//
// C callback pattern: DiskArbitration requires C function pointers (non-capturing).
// We pass `self` as an Unmanaged void* context and recover it inside the callback.
// Using passUnretained is safe because DiskMonitor lives for the full app lifetime.

final class DiskMonitor {

    var onDriveAppeared: ((String, String, String, String) -> Void)?  // (bsdName, volumeName, mountPoint, devicePath)
    var onDriveDisappeared: ((String) -> Void)?                        // bsdName

    private var session: DASession?

    func start() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            NSLog("[DiskMonitor] Failed to create DASession")
            return
        }
        self.session = session

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(
            session,
            nil,  // match all disks; NTFS filter is applied in the callback
            diskAppearedCCallback,
            ctx
        )
        DARegisterDiskDisappearedCallback(
            session,
            nil,
            diskDisappearedCCallback,
            ctx
        )

        // Schedule on the main run loop so callbacks fire on the main thread
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func stop() {
        guard let session = session else { return }
        DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.session = nil
    }

    // Called on main thread (run loop scheduled above)
    fileprivate func handleDiskAppeared(_ disk: DADisk) {
        guard let cfDesc = DADiskCopyDescription(disk) else { return }
        let desc = cfDesc as NSDictionary

        // Filter: NTFS volumes only
        guard let fsType = desc[kDADiskDescriptionVolumeKindKey] as? String,
              fsType.lowercased() == "ntfs" else { return }

        guard let namePtr = DADiskGetBSDName(disk) else { return }
        let bsdName   = String(cString: namePtr)
        let volName   = desc[kDADiskDescriptionVolumeNameKey] as? String ?? bsdName
        let mountURL  = desc[kDADiskDescriptionVolumePathKey] as? URL
        let mountPt   = mountURL?.path ?? "/Volumes/\(volName)"
        let devPath   = "/dev/\(bsdName)"

        NSLog("[DiskMonitor] NTFS drive appeared: %@ at %@", bsdName, mountPt)
        onDriveAppeared?(bsdName, volName, mountPt, devPath)
    }

    fileprivate func handleDiskDisappeared(_ disk: DADisk) {
        guard let namePtr = DADiskGetBSDName(disk) else { return }
        let bsdName = String(cString: namePtr)
        NSLog("[DiskMonitor] Drive disappeared: %@", bsdName)
        onDriveDisappeared?(bsdName)
    }
}

// MARK: - C-compatible free functions (cannot capture any Swift variables)

private func diskAppearedCCallback(disk: DADisk, context: UnsafeMutableRawPointer?) {
    guard let context = context else { return }
    Unmanaged<DiskMonitor>.fromOpaque(context).takeUnretainedValue().handleDiskAppeared(disk)
}

private func diskDisappearedCCallback(disk: DADisk, context: UnsafeMutableRawPointer?) {
    guard let context = context else { return }
    Unmanaged<DiskMonitor>.fromOpaque(context).takeUnretainedValue().handleDiskDisappeared(disk)
}
