# Architecture

## Overview

NTFSWriter is a macOS menubar app that remounts NTFS drives with full read/write access using `ntfs-3g` over macFUSE.

## Components

```
AppDelegate
├── DiskMonitor       — detects NTFS drives via DiskArbitration framework
├── NTFSMounter       — runs ntfs-3g with admin privileges via osascript
├── MenuBarController — NSStatusItem + NSMenu UI
├── DependencyChecker — verifies macFUSE + ntfs-3g are installed
└── Preferences       — auto-mount and launch-at-login settings
```

## Mount Flow

```
Drive plugged in
      ↓
DiskArbitration callback (DiskMonitor)
      ↓
Detected as NTFS → shown in menu
      ↓
User clicks "Enable Write Access"
      ↓
NTFSMounter writes a bash script to /tmp
runs it via `do shell script ... with administrator privileges`
      ↓
Script: diskutil unmount → mkdir → ntfs-3g remount as FUSE daemon
      ↓
Drive is writable
```

## Privilege Model

ntfs-3g must run as root to interact with raw disk devices and create mount points under `/Volumes/`. NTFSWriter uses `NSAppleScript` (`do shell script ... with administrator privileges`) which triggers the standard macOS password dialog. Auth is cached by the OS for ~5 minutes.

## Dependencies

| Dependency | Role |
|---|---|
| macFUSE | Kernel extension that allows userspace filesystem drivers |
| ntfs-3g | FUSE-based NTFS driver; handles all reads and writes |

## Build

No Xcode required. `build_app.sh` uses `swiftc` directly with the Command Line Tools SDK, then assembles and ad-hoc signs the `.app` bundle. `package_dmg.sh` wraps it in a distributable DMG.
