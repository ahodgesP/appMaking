#!/bin/sh
set -eu

PACKAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INSTALL_DIR=${JOINTODO_CLI_INSTALL_DIR:-"$HOME/.local/bin"}

cd "$PACKAGE_DIR"
swift build --disable-sandbox -c release --product jointodo
mkdir -p "$INSTALL_DIR"
cp "$PACKAGE_DIR/.build/release/jointodo" "$INSTALL_DIR/jointodo"
chmod 755 "$INSTALL_DIR/jointodo"

echo "$INSTALL_DIR/jointodo"
