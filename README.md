# NTFSWriter

A free, open-source macOS menubar app that gives full read/write access to NTFS drives — without Paragon or Tuxera.

Plug in your NTFS hard drive, click **Enable Write Access**, done. Your TV, Windows PC, and Mac all share the same drive seamlessly.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue) ![Swift 5.8](https://img.shields.io/badge/Swift-5.8-orange) ![License MIT](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Full NTFS write access** — powered by the battle-tested `ntfs-3g` driver (same one Linux uses)
- **Menubar-only** — no Dock icon, lives quietly in your menu bar
- **Auto-Mount on Connect** — optionally mount drives writable the moment they're plugged in
- **Launch at Login** — start automatically with macOS
- **Safe Eject** — flushes writes with `sync` before unmounting so data is never lost
- **Dependency check** — alerts you if macFUSE or ntfs-3g are missing, with install instructions
- **No subscription, no telemetry, no cost**

---

## Quick Start

**1. Install dependencies (one time):**
```bash
brew install --cask macfuse
brew tap gromgit/homebrew-fuse
brew install gromgit/homebrew-fuse/ntfs-3g-mac
```
Then: **System Settings → Privacy & Security → approve macFUSE extension → Restart**

**2. Install NTFSWriter:**

Download `NTFSWriter.dmg` from [Releases](../../releases), open it, drag the app to `/Applications`.

Or build from source:
```bash
git clone https://github.com/yasirva/ntfs-writer.git
cd ntfs-writer
bash build_app.sh
cp -r NTFSWriter.app /Applications/
```

**3. Run:**
```bash
open /Applications/NTFSWriter.app
```

The drive icon appears in your menu bar. Plug in an NTFS drive and click **Enable Write Access**.

---

## Building from Source

Requires: macOS 12+, Swift 5.8+, Command Line Tools (`xcode-select --install`)

```bash
bash build_app.sh          # compiles + creates NTFSWriter.app
bash package_dmg.sh        # builds app AND wraps it in a distributable DMG
```

The build scripts auto-detect your SDK — no Xcode install required, Command Line Tools are enough.

### What `build_app.sh` does
1. Finds the newest available macOS SDK under `/Library/Developer/CommandLineTools/SDKs/`
2. Compiles all Swift sources + the DiskArbitration C bridge with `swiftc`
3. Assembles `NTFSWriter.app/Contents/{MacOS,Resources}` with the binary and `Info.plist`
4. Ad-hoc code-signs the bundle with `codesign --sign -` (no Apple Developer account needed)

### What `package_dmg.sh` does
1. Runs `build_app.sh` first
2. Creates a staging folder with `NTFSWriter.app` + an `Applications` symlink
3. Creates a writable HFS+ disk image with `hdiutil create`
4. Mounts it and uses AppleScript to set the Finder window layout (icon positions, size)
5. Unmounts and converts to a compressed read-only UDZO image (`zlib-level=9`)
6. Output: `NTFSWriter.dmg` (~64 KB)

To distribute: share `NTFSWriter.dmg`. Recipients open it and drag the app to Applications — standard macOS install flow.

---

## How It Works

```
User plugs in NTFS drive
        │
        ▼
DiskArbitration (macOS kernel)
  fires "disk appeared" callback
        │
        ▼
DiskMonitor detects NTFS filesystem
  (kDADiskDescriptionVolumeKindKey == "ntfs")
        │
        ▼
MenuBarController shows drive in menu
        │
   User clicks "Enable Write Access"
        │
        ▼
NTFSMounter writes a bash script to /tmp
  runs it via `do shell script ... with administrator privileges`
  (standard macOS password dialog — auth cached ~5 min)
        │
        ▼
Script: diskutil unmount → mkdir → ntfs-3g remount
  ntfs-3g runs as root FUSE daemon, drive now writable
        │
        ▼
User reads/writes freely. "Safely Eject" → sync + unmount.
```

---

## Project Structure

```
ntfs-writer/
├── Sources/NTFSWriter/
│   ├── main.swift                  # NSApplication entry point
│   ├── AppDelegate.swift           # Orchestrates all components
│   ├── Bridges/
│   │   └── DiskArbitrationBridge.h # Exposes DA C API to Swift
│   ├── Core/
│   │   ├── DiskMonitor.swift       # DiskArbitration drive detection
│   │   ├── NTFSMounter.swift       # Privileged mount/unmount via osascript
│   │   ├── DependencyChecker.swift # Detects macFUSE + ntfs-3g installs
│   │   └── Preferences.swift       # Auto-mount + launch-at-login settings
│   ├── Models/
│   │   └── NTFSDrive.swift         # Drive data model
│   └── UI/
│       └── MenuBarController.swift # NSStatusItem + NSMenu
├── Info.plist                      # LSUIElement=true (menubar-only)
├── Package.swift                   # Swift Package Manager manifest
├── build_app.sh                    # Compile + assemble .app bundle
└── package_dmg.sh                  # Build + create distributable DMG
```

---

## Tech Stack

| Component | Why |
|---|---|
| **Swift 5.8 + AppKit** | Native macOS performance; no Electron overhead |
| **DiskArbitration framework** | The official macOS API for disk attach/detach events |
| **ntfs-3g** | Mature FUSE-based NTFS driver; same code Linux has used since 2006 |
| **macFUSE** | FUSE layer for macOS that ntfs-3g runs on top of |
| **NSAppleScript** | Privilege escalation via standard macOS password dialog (no LaunchDaemon needed) |
| **SMAppService** | macOS 13+ Login Items API (falls back to LaunchAgent plist on macOS 12) |

---

## Requirements

- macOS 12 Monterey or later
- Apple Silicon or Intel Mac
- [macFUSE](https://osxfuse.github.io) + [ntfs-3g](https://github.com/osxfuse/osxfuse) (via Homebrew)
