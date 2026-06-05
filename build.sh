#!/bin/bash
set -e

CONFIG="${1:-Release}"

# Normalize: accept "debug"/"release" as input but use proper case for Xcode
case "$(echo "$CONFIG" | tr '[:upper:]' '[:lower:]')" in
    debug) CONFIG="Debug" ;;
    *) CONFIG="Release" ;;
esac

echo "Building CalendarMirror ($CONFIG)..."
xcodebuild -project CalendarMirror.xcodeproj \
    -scheme CalendarMirror \
    -configuration "$CONFIG" \
    build 2>&1 | tail -5

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/CalendarMirror-*/Build/Products/"$CONFIG"/CalendarMirror.app -maxdepth 0 -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: Could not find built app"
    exit 1
fi

echo "Built: $APP_PATH"

if [ "$CONFIG" = "Release" ]; then
    echo "Installing to /Applications..."
    pkill -f "CalendarMirror.app" 2>/dev/null || true
    sleep 1
    rm -rf /Applications/CalendarMirror.app
    cp -R "$APP_PATH" /Applications/
    echo "Installed to /Applications/CalendarMirror.app"
    echo ""
    echo "Launch with: open /Applications/CalendarMirror.app"
else
    echo ""
    echo "Debug build complete (not installed)."
    echo "Run with: open \"$APP_PATH\""
fi
