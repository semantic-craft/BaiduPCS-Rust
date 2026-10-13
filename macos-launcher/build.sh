#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export CARGO_PROFILE_DEV_DEBUG=0
cargo test --locked --example desktop-config-check --manifest-path ../backend/Cargo.toml
cargo build --locked --example desktop-config-check --manifest-path ../backend/Cargo.toml
BUILD_DIR="$PWD/.build"
mkdir -p "$BUILD_DIR/module-cache"
xcrun swiftc -module-cache-path "$BUILD_DIR/module-cache" Core.swift Tests.swift -o "$BUILD_DIR/launcher-tests"
"$BUILD_DIR/launcher-tests"
APP="$BUILD_DIR/BaiduPCS.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -module-cache-path "$BUILD_DIR/module-cache" -framework AppKit -framework SwiftUI Core.swift Launcher.swift -o "$APP/Contents/MacOS/BaiduPCSLauncher"
cp ../backend/target/debug/examples/desktop-config-check "$APP/Contents/Resources/desktop-config-check"
cp Info.plist "$APP/Contents/Info.plist"
printf 'Built launcher only: %s\nNo backend bundled or executed.\n' "$APP"
