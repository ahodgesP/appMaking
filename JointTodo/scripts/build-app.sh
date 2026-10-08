#!/bin/sh
set -eu

PACKAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PACKAGE_DIR"

swift build --disable-sandbox -c release --product JointTodo

APP_DIR="$PACKAGE_DIR/dist/JointTodo.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PACKAGE_DIR/DistSupport/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PACKAGE_DIR/DistSupport/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PACKAGE_DIR/.build/release/JointTodo" "$APP_DIR/Contents/MacOS/JointTodo"
chmod 755 "$APP_DIR/Contents/MacOS/JointTodo"
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"
