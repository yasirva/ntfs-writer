#!/usr/bin/env bash
# package_dmg.sh — Build NTFSWriter.app and package it into a distributable DMG
set -euo pipefail

APP_NAME="NTFSWriter"
DMG_NAME="${APP_NAME}.dmg"
DMG_TITLE="${APP_NAME}"
VOL_SIZE="20m"          # temporary writable image size (the app is small)
STAGING="/tmp/${APP_NAME}_dmg_staging"
TMP_DMG="/tmp/${APP_NAME}_tmp.dmg"

# ── 1. Build the .app ──────────────────────────────────────────────────────
echo "==> Building ${APP_NAME}.app…"
bash build_app.sh

# ── 2. Prepare staging folder ─────────────────────────────────────────────
echo "==> Preparing staging folder…"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cp -r "${APP_NAME}.app" "${STAGING}/"
# Symlink to /Applications so users can drag-and-drop to install
ln -s /Applications "${STAGING}/Applications"

# ── 3. Create a writable DMG from the staging folder ─────────────────────
echo "==> Creating temporary writable DMG…"
rm -f "${TMP_DMG}" "${DMG_NAME}"
hdiutil create \
    -volname "${DMG_TITLE}" \
    -srcfolder "${STAGING}" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,b=16" \
    -format UDRW \
    -size "${VOL_SIZE}" \
    "${TMP_DMG}"

# ── 4. Mount and customise the window appearance with Finder ──────────────
echo "==> Mounting and customising window…"
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "${TMP_DMG}" \
    | awk '/\/Volumes/{print $NF}')

# Give Finder a moment to register the volume
sleep 1

# Set window size, icon positions, hide toolbar via AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${DMG_TITLE}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 900, 480}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        -- Position the app icon (left side) and Applications alias (right side)
        set position of item "${APP_NAME}.app" of container window to {150, 130}
        set position of item "Applications" of container window to {350, 130}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Ensure Finder writes its .DS_Store
sync
sleep 2

# ── 5. Unmount, convert to compressed read-only DMG ───────────────────────
echo "==> Unmounting…"
hdiutil detach "${MOUNT_DIR}" -quiet

echo "==> Converting to compressed DMG…"
hdiutil convert "${TMP_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_NAME}"

# ── 6. Cleanup ────────────────────────────────────────────────────────────
rm -f "${TMP_DMG}"
rm -rf "${STAGING}"

echo ""
SIZE=$(du -sh "${DMG_NAME}" | cut -f1)
echo "✓ Done: ${DMG_NAME}  (${SIZE})"
echo ""
echo "Distribute this file. Users open it, drag NTFSWriter → Applications, done."
