import Foundation

struct NTFSDrive: Identifiable, Hashable {
    let id: String           // BSD name e.g. "disk2s1"
    let volumeName: String   // e.g. "MY_DRIVE"
    var mountPoint: String   // e.g. "/Volumes/MY_DRIVE"
    let devicePath: String   // e.g. "/dev/disk2s1"
    var isMounted: Bool      // true = writable via ntfs-3g
    var isProcessing: Bool   // true = mount/unmount in progress

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: NTFSDrive, rhs: NTFSDrive) -> Bool {
        lhs.id == rhs.id
    }
}
