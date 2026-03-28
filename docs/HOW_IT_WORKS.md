# How NTFSWriter Works — A Beginner's Guide

This document explains every decision made while building NTFSWriter, from first principles.
No prior programming knowledge assumed.

---

## Table of Contents

1. [The Problem We're Solving](#1-the-problem-were-solving)
2. [Why macOS Can't Write to NTFS](#2-why-macos-cant-write-to-ntfs)
3. [Our Solution: FUSE + ntfs-3g](#3-our-solution-fuse--ntfs-3g)
4. [How a macOS App Is Structured](#4-how-a-macos-app-is-structured)
5. [The App Architecture — Big Picture](#5-the-app-architecture--big-picture)
6. [File-by-File Walkthrough](#6-file-by-file-walkthrough)
7. [Key Concepts Explained Simply](#7-key-concepts-explained-simply)
8. [The Build Process](#8-the-build-process)
9. [The DMG — What It Is and How We Made It](#9-the-dmg--what-it-is-and-how-we-made-it)
10. [Glossary](#10-glossary)

---

## 1. The Problem We're Solving

You have a hard drive formatted as **NTFS** (a Windows format). You plug it into your Mac. macOS can *read* the files but refuses to *write* to it.

Why? Apple never fully implemented NTFS write support in macOS. They support reading it (so you can access Windows drives) but writing is disabled because they don't want to be responsible if something goes wrong with a competitor's file system.

**The consequence for you:**
- Your VIDAA TV understands NTFS but not exFAT
- FAT32 can't handle files larger than 4 GB
- So NTFS is the only option — but your Mac can't write to it
- Paragon NTFS solves this, but costs ~$20/year

**Our goal:** Build a free app that does exactly what Paragon does.

---

## 2. Why macOS Can't Write to NTFS

Think of a file system like a language. NTFS is a language that Windows invented. macOS learned to *read* this language (like reading a foreign book with a dictionary) but never learned to *write* it (like being able to write grammatically correct sentences in that language).

macOS uses its own file systems: **HFS+** (older) and **APFS** (modern). These are the languages macOS knows natively.

When you plug in an NTFS drive, macOS:
1. Recognises the format
2. Mounts it as **read-only** — you can browse files, copy files off, but not copy files onto it
3. Any attempt to write returns an error: `Read-only file system`

**The technical reason:** NTFS has complex features (journaling, permissions, sparse files, alternate data streams) that Apple chose not to fully implement. They implemented just enough to read files.

---

## 3. Our Solution: FUSE + ntfs-3g

### What is FUSE?

**FUSE** stands for **Filesystem in Userspace**.

Normally, file systems are implemented deep inside the operating system kernel (the core, privileged part of the OS). Only Apple can add new file systems to macOS that way.

FUSE is a clever workaround: it lets *regular programs* (not Apple) implement file systems. When you read/write a file, FUSE intercepts the call and forwards it to your program.

**Analogy:** Imagine the OS is a post office. Normally only the post office can deliver letters. FUSE is like a contractor arrangement where the post office forwards certain deliveries to a private courier. You still call the post office, but a third party does the actual work.

**macFUSE** is the macOS version of FUSE. It's a small kernel extension that provides this "contractor" mechanism.

### What is ntfs-3g?

**ntfs-3g** is a program that knows how to read and write NTFS, built on top of FUSE. It's been used on Linux for 15+ years and is extremely well-tested.

When ntfs-3g runs:
1. It registers itself with macFUSE as the handler for a specific mount point (e.g. `/Volumes/MyDrive`)
2. When your Mac tries to read or write any file at that path, macFUSE forwards the request to ntfs-3g
3. ntfs-3g does the actual NTFS reading/writing and returns the result
4. From your Mac's perspective, it all looks like a normal drive

**The full chain:**
```
Your App (Finder, Terminal, etc.)
        ↓  "write file to /Volumes/MyDrive/photo.jpg"
macOS kernel
        ↓  (sees this is a FUSE mount)
macFUSE (kernel extension)
        ↓  forwards to...
ntfs-3g (running as a background process)
        ↓
Actual NTFS read/write on the drive
```

### Why ntfs-3g needs root (admin) access

ntfs-3g needs to run as the administrator (`root`) user because:
1. It needs to create the mount point in `/Volumes/` (a protected system directory)
2. It needs to interact with the raw disk device (`/dev/disk2s1`) at a low level
3. macFUSE kernel operations require elevated privileges

This is why NTFSWriter asks for your password when you click "Enable Write Access."

---

## 4. How a macOS App Is Structured

Before diving into the code, let's understand what a macOS app actually is.

### The .app Bundle

A macOS app (like `NTFSWriter.app`) is not a single file. It's a **folder** that macOS treats as a single item. If you right-click any `.app` and choose "Show Package Contents", you'll see:

```
NTFSWriter.app/
└── Contents/
    ├── Info.plist        ← App metadata (name, version, settings)
    ├── MacOS/
    │   └── NTFSWriter    ← The actual compiled binary (the program)
    └── Resources/        ← Icons, images, etc.
```

`Info.plist` is a configuration file in XML format that tells macOS about the app:
- What the app is called
- What version it is
- Whether to show it in the Dock
- What permissions it needs

### LSUIElement — The Menubar-Only Setting

One key setting in `Info.plist` is:
```xml
<key>LSUIElement</key>
<true/>
```

`LSUIElement` = "Launch Services UI Element". Setting this to `true` tells macOS:
> "This app has no windows, no Dock icon. It lives in the menu bar only."

This is how apps like Dropbox, 1Password, and now NTFSWriter work — they're always running silently in the background, accessible only via the menu bar.

### Swift — The Language We Used

We wrote NTFSWriter in **Swift**, Apple's modern programming language for macOS and iOS apps. Swift is the language Apple created in 2014 to replace Objective-C.

Key things to know about Swift for this project:
- It compiles to native machine code (fast)
- It uses **AppKit** — Apple's framework for building Mac UI (menus, windows, buttons)
- It can call C code directly (needed for DiskArbitration)

### Swift Package Manager (SPM)

Instead of using Xcode (Apple's IDE), we used **Swift Package Manager** — a command-line build tool. The file `Package.swift` is the build manifest: it tells the compiler where the source files are and which system frameworks to link against.

```swift
// Package.swift — simplified explanation:
.executableTarget(
    name: "NTFSWriter",           // output binary name
    path: "Sources/NTFSWriter",   // where to find .swift files
    linkerSettings: [
        .linkedFramework("DiskArbitration"),  // link DA framework
        .linkedFramework("AppKit"),           // link UI framework
    ]
)
```

---

## 5. The App Architecture — Big Picture

Here's how all the pieces fit together:

```
┌─────────────────────────────────────────────────────────┐
│                     NTFSWriter.app                       │
│                                                          │
│  main.swift ──────► AppDelegate                          │
│  (entry point)      (orchestrator)                       │
│                          │                               │
│           ┌──────────────┼──────────────┐                │
│           │              │              │                 │
│           ▼              ▼              ▼                 │
│     DiskMonitor    NTFSMounter    MenuBarController       │
│     (detects       (mounts /       (the icon +           │
│      drives)        unmounts)       menu you see)        │
│           │                              │                │
│           │          DependencyChecker   │                │
│           │          (checks macFUSE     │                │
│           │           + ntfs-3g)         │                │
│           │                         Preferences          │
│           │                         (auto-mount,         │
│           │                          launch at login)    │
└───────────┼─────────────────────────────────────────────┘
            │
            ▼ (system level — outside our app)
     DiskArbitration            ntfs-3g
     (macOS kernel API)         (FUSE daemon, runs as root)
```

**Flow when you plug in a drive:**
1. macOS kernel detects new disk
2. `DiskMonitor` receives a callback from DiskArbitration: "disk appeared!"
3. `DiskMonitor` checks: is this NTFS? Yes → tells `AppDelegate`
4. `AppDelegate` adds the drive to its list, tells `MenuBarController` to update
5. You see the drive in the menu bar
6. You click "Enable Write Access"
7. `AppDelegate` tells `NTFSMounter` to mount it
8. `NTFSMounter` runs a privileged script that calls ntfs-3g
9. Drive is now writable → menu updates to show "✅ Write access enabled"

---

## 6. File-by-File Walkthrough

### `main.swift` — The Entry Point

```swift
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

Every macOS app starts here. `NSApplication.shared` is the application object — macOS gives you one per app. We create an `AppDelegate` and tell the app to use it. `app.run()` starts the event loop — it sits and waits for events (disk plug-in, mouse clicks, etc.) forever until the app quits.

**What is `NSApplication`?** It's the object that *is* your app from macOS's perspective. It handles events (keyboard, mouse, disk events), manages the menu bar, and coordinates everything.

**What is a delegate?** A delegate is an object you give to another object to handle events on its behalf. By setting `AppDelegate` as the application's delegate, we're saying: "when the app starts, when it quits, etc. — tell AppDelegate."

---

### `AppDelegate.swift` — The Orchestrator

This is the brain of the app. It:
- Creates all the other components on startup
- Wires them together
- Manages the single source of truth: the list of detected drives

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // Called by macOS once the app has fully started

    let menu = MenuBarController()   // create the menu bar icon
    let monitor = DiskMonitor()      // start watching for drives
    monitor.start()
}
```

**Why is AppDelegate the "single source of truth"?**

The drives list (`private var drives: [String: NTFSDrive]`) lives only in AppDelegate. `DiskMonitor` doesn't store drives — it just fires events. `MenuBarController` doesn't store drives — it just displays what AppDelegate gives it. This prevents the bug where two places have different ideas of what drives are connected.

**The auto-mount logic:**
```swift
// After a drive appears...
if Preferences.shared.autoMount {
    mountDrive(bsdName)  // mount immediately without user clicking
}
```

---

### `NTFSDrive.swift` — The Data Model

```swift
struct NTFSDrive {
    let id: String           // "disk2s1" — the kernel's name for this partition
    let volumeName: String   // "MY_DRIVE" — the human-readable name
    var mountPoint: String   // "/Volumes/MY_DRIVE" — where it appears in Finder
    let devicePath: String   // "/dev/disk2s1" — the raw device path
    var isMounted: Bool      // true = writable via ntfs-3g
    var isProcessing: Bool   // true = currently mounting/unmounting
}
```

**Why `struct` and not `class`?**

In Swift, `struct` is a **value type** (copying creates an independent copy) and `class` is a **reference type** (copying gives you another pointer to the same object).

We use `struct` here because drives are just data — there's no shared identity to worry about. When AppDelegate updates a drive's `isMounted` flag, it gets a copy, modifies it, and puts it back. This is safer and avoids bugs where two parts of the code accidentally share and mutate the same object.

**What is `bsdName` / `disk2s1`?**

macOS names disk partitions with the scheme `diskXsY`:
- `X` = disk number (0 = internal SSD, 1 = first external, 2 = second external...)
- `s` = "slice" (partition)
- `Y` = partition number

So `disk2s1` = disk number 2, partition 1. This is how the kernel identifies partitions. `/dev/disk2s1` is the "device file" — a special file that represents the physical partition.

---

### `DiskMonitor.swift` — Watching for Drives

This is the most technically complex file. It uses **DiskArbitration**, a C framework.

**What is DiskArbitration?**

DiskArbitration is macOS's system for managing disk events. It's what macOS uses internally to know when you plug in a USB drive, SD card, etc. We tap into the same system.

**The C callback problem:**

DiskArbitration was written in C (an older language), not Swift. C uses **callbacks** — you give it a function pointer and it calls your function when something happens. The problem: C function pointers can't be Swift closures (which can capture variables from their environment).

We solve this with a pattern called **context pointer**:

```swift
// 1. Convert `self` to a raw pointer (a memory address)
let ctx = Unmanaged.passUnretained(self).toOpaque()

// 2. Register with DiskArbitration, passing our pointer as "context"
DARegisterDiskAppearedCallback(session, nil, diskAppearedCCallback, ctx)

// 3. Free function (no captured variables — C-compatible)
private func diskAppearedCCallback(disk: DADisk, context: UnsafeMutableRawPointer?) {
    // 4. Convert the raw pointer back to our Swift object
    let monitor = Unmanaged<DiskMonitor>.fromOpaque(context!).takeUnretainedValue()
    monitor.handleDiskAppeared(disk)  // now we can call Swift methods
}
```

**Analogy:** Imagine you need to give a stranger (C code) a way to reach you. You can't give them your name (Swift object) because they don't understand names. Instead you give them your phone number (a raw pointer — just a number). When they want to reach you, they call that number, and you pick up.

**What does `Unmanaged` mean?**

Swift has **Automatic Reference Counting (ARC)** — it automatically tracks how many things are using an object and frees the memory when nothing is using it anymore. `Unmanaged` lets us step outside ARC to pass a raw pointer to C code. We use `passUnretained` (don't increase the reference count) because we know `DiskMonitor` will live for the entire app lifetime — so we don't need ARC to keep it alive.

**Filtering for NTFS:**

```swift
guard let fsType = desc[kDADiskDescriptionVolumeKindKey] as? String,
      fsType.lowercased() == "ntfs" else { return }
```

When a disk appears, we ask DiskArbitration for its description (a dictionary of properties). One property is `kDADiskDescriptionVolumeKindKey` — the file system type. We only care about `"ntfs"`, so we ignore everything else (APFS system volumes, FAT32 drives, etc.).

---

### `NTFSMounter.swift` — The Privileged Mount Operation

This file handles the actual mounting. The core challenge: **ntfs-3g must run as root**.

**Why write a script to /tmp?**

We could build the shell command as a string and pass it directly to AppleScript:
```swift
let appleScript = "do shell script \"diskutil unmount ... && ntfs-3g ...\" with administrator privileges"
```

But this causes **escaping hell** — volume names might contain spaces, apostrophes, special characters. Every `"` in the command needs to be `\"` in the Swift string, and the AppleScript string adds another layer of escaping. It becomes unreadable and error-prone.

Instead, we write the script to a file:
```swift
// Write to /tmp/ntfsw_123456.sh
try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
// Then run it:
// do shell script "/tmp/ntfsw_123456.sh" with administrator privileges
```

The script path is just `/tmp/ntfsw_NNNNNN.sh` — no special characters. Clean.

**What does `atomically: true` mean?**

It means: write to a temporary file first, then rename it to the final path. This prevents a situation where the file is half-written (e.g., if the system crashes mid-write). Either the full file exists, or the old file exists — never a corrupt in-between state.

**What is `0o700`?**

File permissions in Unix/macOS are represented as octal numbers. `0o700` means:
- `7` (owner: read + write + execute)
- `0` (group: no permissions)
- `0` (everyone else: no permissions)

We need `+x` (execute) so the script can be run directly. Only the owner needs it.

**The mount script explained:**

```bash
#!/bin/bash
set -e                          # stop if any command fails

diskutil unmount '/dev/disk2s1' 2>/dev/null || true
# macOS auto-mounted the drive read-only. We unmount it first.
# "2>/dev/null" = ignore error output
# "|| true" = if unmount fails (already unmounted), don't stop

mkdir -p '/Volumes/MY_DRIVE'
# Create the mount point directory if it doesn't exist
# "-p" = don't fail if it already exists

nohup '/opt/homebrew/bin/ntfs-3g' '/dev/disk2s1' '/Volumes/MY_DRIVE' \
    -o local,allow_other,noappledouble,nolocalcaches \
    >/tmp/ntfs-writer-mount.log 2>&1 &
# Run ntfs-3g in the background
# "nohup" = don't kill it when this script exits
# "&" = run in background (don't wait for it)
# The options:
#   local = tell macOS it's a local volume
#   allow_other = let other users access it
#   noappledouble = don't create annoying ._ files
#   nolocalcaches = don't cache data (avoid stale reads)

# Wait up to 10 seconds for the mount to appear
for i in $(seq 1 20); do
    if /sbin/mount | grep -qF '/Volumes/MY_DRIVE'; then
        exit 0   # success!
    fi
    sleep 0.5
done
exit 1  # timeout
```

**Why `nohup` + `&`?**

ntfs-3g needs to keep running as a background process — it *is* the file system. If it exits, the drive disappears. But our script needs to exit (so AppleScript can return). `nohup ... &` starts ntfs-3g in the background and detaches it from the script. When the script exits, ntfs-3g keeps running.

**`do shell script ... with administrator privileges`:**

This is AppleScript syntax. AppleScript is macOS's built-in scripting language. This specific command shows the standard macOS password dialog and runs the command as root. macOS caches the authentication for ~5 minutes (same as `sudo`), so you won't be asked repeatedly.

---

### `DependencyChecker.swift` — Are macFUSE and ntfs-3g Installed?

Simple file existence checks:

```swift
// macFUSE installs here when you run the .pkg installer
static var isMacFUSEInstalled: Bool {
    FileManager.default.fileExists(atPath: "/Library/Filesystems/macfuse.fs")
}

// ntfs-3g installs to different places depending on architecture:
// Intel Mac Homebrew: /usr/local/bin/
// Apple Silicon Homebrew: /opt/homebrew/bin/
static let ntfs3gCandidates = [
    "/usr/local/bin/ntfs-3g",
    "/opt/homebrew/bin/ntfs-3g",
]
```

**Why two paths for ntfs-3g?**

Apple switched from Intel processors to Apple Silicon (M1/M2/M3/M4) in 2020. Homebrew changed its install location:
- Intel Macs: `/usr/local/`
- Apple Silicon Macs: `/opt/homebrew/`

We check both to support all Macs.

---

### `MenuBarController.swift` — The UI

This creates and manages the menu bar icon and dropdown menu.

**NSStatusItem:**

`NSStatusItem` is Apple's class for menu bar items. We get one from the system bar:
```swift
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
```

**SF Symbols:**

The drive icon uses an **SF Symbol** — Apple's built-in icon library with 5000+ icons:
```swift
NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "NTFS Writer")
```

`isTemplate = true` tells AppKit to re-draw the icon in the right colour for dark/light menu bars automatically.

**NSMenu + NSMenuItem:**

The dropdown is an `NSMenu` containing `NSMenuItem` objects. The interesting part is how menu items communicate back to our code:

```swift
let mountItem = NSMenuItem(
    title: "Enable Write Access",
    action: #selector(mountTapped(_:)),  // call this method when clicked
    keyEquivalent: ""
)
mountItem.target = self              // on THIS object
mountItem.representedObject = drive.id  // attach the drive ID so we know which drive
```

**`#selector`** is Swift's way of safely referring to a method name. When the user clicks the menu item, AppKit calls `mountTapped(_:)` on `target` (which is `self` — the `MenuBarController`). The method then reads `representedObject` to know which drive was clicked.

---

### `Preferences.swift` — Settings

Two preferences:
1. **Auto-mount** — simple `UserDefaults` bool
2. **Launch at login** — uses `SMAppService` (macOS 13+) or a `LaunchAgent` plist

**UserDefaults:**

`UserDefaults` is macOS's built-in key-value store for app settings. It persists across app restarts. Think of it as a small dictionary saved to disk automatically.

**SMAppService (Launch at Login):**

On macOS 13+, there's a clean API:
```swift
try SMAppService.mainApp.register()   // add to Login Items
try SMAppService.mainApp.unregister() // remove from Login Items
```

This shows the app in **System Settings → General → Login Items** where users can manage it.

**LaunchAgent fallback (macOS 12):**

On macOS 12, we write a `.plist` file to `~/Library/LaunchAgents/`. The system reads this folder on login and launches any apps listed there. It's the older mechanism for auto-start.

---

## 7. Key Concepts Explained Simply

### What is a Framework?

A framework is a pre-built collection of code you can use in your app. Instead of writing everything from scratch, you use frameworks Apple (and others) provide.

- **AppKit** — everything for building Mac UI (menus, windows, buttons, dialogs)
- **Foundation** — basic stuff: files, strings, dates, networking
- **DiskArbitration** — disk plug/unplug events

When we write `import AppKit` at the top of a file, we're saying "give me access to Apple's UI code."

### What is a Run Loop?

`app.run()` starts the **run loop** — a loop that runs forever, waiting for events. Think of it as:

```
while appIsRunning:
    wait for something to happen (disk plugged in, menu clicked, etc.)
    handle it
    repeat
```

Without the run loop, the program would just start and immediately exit.

### What is the Main Thread?

Modern computers can do multiple things at once (**multithreading**). An app can have multiple "threads" of execution running simultaneously.

The **main thread** is the special thread that handles UI. All AppKit operations (updating menus, showing alerts) MUST happen on the main thread. If you try to update the UI from a background thread, the app will crash or behave unpredictably.

This is why we always dispatch UI updates:
```swift
DispatchQueue.main.async {
    self.menuBarController?.updateDrives(...)  // run on main thread
}
```

`DispatchQueue.main.async` = "schedule this to run on the main thread, as soon as possible."

### What is `guard let`?

```swift
guard let fsType = desc[kDADiskDescriptionVolumeKindKey] as? String else { return }
```

This is Swift's early-exit pattern. It means:
> "Try to get this value. If it doesn't exist or is the wrong type, exit this function now."

It's cleaner than nested `if` statements and makes the "happy path" code flat and readable.

### What is `[weak self]`?

```swift
mounter.mount(drive: drive) { [weak self] result in
    self?.menuBarController?.updateDrives(...)
}
```

This prevents **retain cycles** — a bug where two objects hold references to each other, preventing either from being freed from memory.

`[weak self]` means: "hold a weak reference to `self` — don't prevent it from being deallocated." If `self` (AppDelegate) gets freed before the closure runs, `self` becomes `nil` and the `self?.` calls safely do nothing.

---

## 8. The Build Process

We don't use Xcode. Instead, `build_app.sh` manually does what Xcode would do.

### Step by step:

**1. Find the SDK:**
```bash
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk | sort -V | tail -1)
```
The **SDK** (Software Development Kit) is a collection of header files and libraries that define the macOS APIs. We need the newest one available.

**2. Compile with `swiftc`:**
```bash
swiftc \
    -sdk "${SDK}" \
    -target arm64-apple-macos12 \    # Apple Silicon, macOS 12+
    -framework DiskArbitration \      # link the DA framework
    -I Sources/NTFSWriter/Bridges \   # include our C bridge header
    Sources/NTFSWriter/*.swift \
    -o /tmp/NTFSWriter_bin
```

`swiftc` is the Swift compiler. It takes all our `.swift` files and the C bridge header, and produces a single binary executable.

**3. Create the .app bundle structure:**
```bash
mkdir -p NTFSWriter.app/Contents/MacOS
cp /tmp/NTFSWriter_bin NTFSWriter.app/Contents/MacOS/NTFSWriter
cp Info.plist NTFSWriter.app/Contents/Info.plist
```

**4. Code sign:**
```bash
codesign --force --deep --sign - NTFSWriter.app
```

macOS 11+ requires all apps to be **code signed** — this is a cryptographic signature proving the app hasn't been tampered with. `--sign -` does an **ad-hoc signature** (using a local key, not your Apple Developer identity). This satisfies macOS's requirement without needing a paid Apple Developer account ($99/year).

---

## 9. The DMG — What It Is and How We Made It

### What is a DMG?

A **DMG** (Disk iMaGe) is a virtual disk — a file that macOS can mount as if it were a real drive. When you double-click a `.dmg`, a new drive icon appears on your desktop. Inside it you see the app (and usually an Applications shortcut for drag-to-install).

DMGs are the standard macOS distribution format. They're compressed, so a 5 MB app might be in a 2 MB DMG.

### How we create it — step by step:

**1. Staging folder:**
```bash
mkdir /tmp/NTFSWriter_dmg_staging
cp -r NTFSWriter.app /tmp/NTFSWriter_dmg_staging/
ln -s /Applications /tmp/NTFSWriter_dmg_staging/Applications
```

The `ln -s /Applications` creates a **symlink** — a shortcut that points to the real `/Applications` folder. This is what gives users the drag-to-install experience.

**2. Create a writable disk image:**
```bash
hdiutil create \
    -volname "NTFSWriter" \        # name shown when mounted
    -srcfolder /tmp/staging \       # copy everything from here
    -format UDRW \                  # UDRW = read/write format
    -size 20m \                     # 20 MB (the app is tiny)
    /tmp/NTFSWriter_tmp.dmg
```

`hdiutil` is Apple's disk image tool (built into macOS). We create a *writable* image first because we need to customise the Finder window.

**3. Mount and customise the Finder window:**
```bash
hdiutil attach -readwrite /tmp/NTFSWriter_tmp.dmg
```

This mounts the image. Now we use AppleScript to tell Finder how to display it:
```applescript
tell application "Finder"
    tell disk "NTFSWriter"
        set bounds of container window to {400, 200, 900, 480}  -- window size/position
        set icon size of icon view options to 96                -- big icons
        set position of item "NTFSWriter.app" to {150, 130}    -- app icon position
        set position of item "Applications" to {350, 130}      -- Applications alias position
    end tell
end tell
```

This is what makes DMGs look professional — the app icon on the left, the Applications arrow on the right, just like commercial apps.

**4. Unmount and convert to compressed read-only:**
```bash
hdiutil detach /Volumes/NTFSWriter

hdiutil convert /tmp/NTFSWriter_tmp.dmg \
    -format UDZO \          # UDZO = compressed read-only
    -imagekey zlib-level=9 \ # maximum compression
    -o NTFSWriter.dmg
```

The final DMG is read-only and compressed. `zlib-level=9` squeezes it as small as possible. Our final DMG is only **64 KB** — tiny!

---

## 10. Glossary

| Term | What it means |
|---|---|
| **NTFS** | New Technology File System — Windows' main disk format |
| **FUSE** | Filesystem in Userspace — lets programs implement file systems |
| **macFUSE** | The macOS FUSE implementation (kernel extension) |
| **ntfs-3g** | Open-source NTFS driver built on FUSE |
| **Kernel** | The core of the OS — the privileged layer that controls hardware |
| **Root / Admin** | The superuser account with full system access |
| **Mount** | Making a disk's contents accessible at a path (e.g. `/Volumes/MyDrive`) |
| **BSD name** | macOS kernel's identifier for a disk partition (e.g. `disk2s1`) |
| **Device file** | A special file representing hardware (e.g. `/dev/disk2s1`) |
| **DiskArbitration** | macOS C framework for disk attach/detach events |
| **AppKit** | Apple's framework for building Mac UI |
| **NSStatusItem** | An icon in the macOS menu bar |
| **Delegate** | An object that handles events on behalf of another object |
| **Run loop** | The infinite event-waiting loop at the heart of every Mac app |
| **Main thread** | The special thread that must handle all UI operations |
| **Retain cycle** | A memory bug where two objects prevent each other from being freed |
| **ARC** | Automatic Reference Counting — Swift's memory management system |
| **SPM** | Swift Package Manager — the command-line build tool we used |
| **SDK** | Software Development Kit — headers and libraries for building against macOS APIs |
| **Code signing** | Cryptographic proof an app hasn't been modified |
| **Ad-hoc signature** | Signing with a local key (no Apple account needed) |
| **DMG** | Disk Image — a compressed virtual disk file used to distribute Mac apps |
| **Symlink** | A file that is a shortcut pointing to another file/folder |
| **UserDefaults** | macOS key-value store for app preferences |
| **LaunchAgent** | A plist file that tells macOS to auto-start a program on login |
| **SMAppService** | Modern macOS 13+ API for Login Items |
| **`guard let`** | Swift's early-exit pattern for safely unwrapping optional values |
| **`[weak self]`** | Prevents retain cycles in closures |
| **`struct` vs `class`** | Structs are value types (copied), classes are reference types (shared) |
| **Callback / C callback** | A function you give to another system to call when something happens |
| **Unmanaged** | Swift mechanism to pass objects to C code as raw pointers |
| **`DispatchQueue.main.async`** | Schedule code to run on the main (UI) thread |
