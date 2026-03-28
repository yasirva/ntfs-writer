import AppKit

// Entry point — NSApplication + AppDelegate setup.
// Using main.swift (not @main) keeps it explicit and
// compatible with SPM's executableTarget.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
