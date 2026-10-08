#!/bin/sh
set -eu

PACKAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE_APP="$PACKAGE_DIR/dist/JointTodo.app"
APPLICATIONS_DIR="$HOME/Applications"
INSTALLED_APP="$APPLICATIONS_DIR/JointTodo.app"

if [ ! -d "$SOURCE_APP" ]; then
    echo "Build the app first with ./scripts/build-app.sh" >&2
    exit 1
fi

mkdir -p "$APPLICATIONS_DIR"
ditto "$SOURCE_APP" "$INSTALLED_APP"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$INSTALLED_APP"
mdimport "$INSTALLED_APP" >/dev/null 2>&1 || true

echo "$INSTALLED_APP"
