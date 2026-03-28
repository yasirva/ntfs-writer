#!/usr/bin/env bash
# build_app.sh — Compile NTFSWriter and package it as a .app bundle
# Works with Command Line Tools only (no Xcode required)
set -euo pipefail

APP_NAME="NTFSWriter"
APP_DIR="${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

# Detect SDK — prefers Xcode SDK, falls back to CLT SDK
if XCODE_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null); then
    SDK="${XCODE_SDK}"
else
    # CLT fallback: use the newest available SDK
    SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1)
fi

if [ -z "${SDK}" ]; then
    echo "ERROR: No macOS SDK found. Run: xcode-select --install"
    exit 1
fi

echo "==> SDK: ${SDK}"

# Detect architecture
ARCH=$(uname -m)
if [ "${ARCH}" = "arm64" ]; then
    TARGET="arm64-apple-macos12"
else
    TARGET="x86_64-apple-macos12"
fi

SOURCES=(
    Sources/NTFSWriter/Models/NTFSDrive.swift
    Sources/NTFSWriter/Core/DependencyChecker.swift
    Sources/NTFSWriter/Core/DiskMonitor.swift
    Sources/NTFSWriter/Core/NTFSMounter.swift
    Sources/NTFSWriter/Core/Preferences.swift
    Sources/NTFSWriter/UI/MenuBarController.swift
    Sources/NTFSWriter/UI/SetupWindowController.swift
    Sources/NTFSWriter/AppDelegate.swift
    Sources/NTFSWriter/main.swift
)

echo "==> Compiling ${APP_NAME}…"
swiftc \
    -sdk "${SDK}" \
    -target "${TARGET}" \
    -O \
    -framework DiskArbitration \
    -framework AppKit \
    -framework Foundation \
    -I Sources/NTFSWriter/Bridges \
    "${SOURCES[@]}" \
    -o "/tmp/${APP_NAME}_bin"

echo "==> Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "/tmp/${APP_NAME}_bin" "${MACOS_DIR}/${APP_NAME}"
cp "Info.plist" "${CONTENTS}/Info.plist"
rm -f "/tmp/${APP_NAME}_bin"

echo "==> Signing (ad-hoc)…"
codesign --force --deep --sign - "${APP_DIR}"

echo ""
echo "✓ Done: ${APP_DIR}"
echo ""
echo "To install:  cp -r ${APP_DIR} /Applications/"
echo "To run now:  open ${APP_DIR}"
echo ""
echo "Prerequisites (install once if not done):"
echo "  brew install --cask macfuse"
echo "  brew install ntfs-3g-mac"
echo "  Then: System Settings → Privacy & Security → approve macFUSE → restart"
