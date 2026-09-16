#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="雪梅优化.app"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
MACOS="$CONTENTS/MacOS"

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "This project builds on macOS only."
  exit 2
fi

CLANG="$(xcrun --find clang)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$RES" "$MACOS"
cp "$ROOT/app/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/src/main.m" "$RES/main.m"
cp "$ROOT/src/engine.sh" "$RES/engine.sh"
chmod +x "$RES/engine.sh"
cp "$ROOT/app/Resources/AppIcon.icns" "$RES/AppIcon.icns"
cp "$ROOT/app/Resources/AppIcon.png" "$RES/AppIcon.png"
cp "$ROOT/app/Resources/BrandCalligraphy.png" "$RES/BrandCalligraphy.png"

"$CLANG" \
  -fobjc-arc \
  -fmodules \
  -isysroot "$SDK" \
  -mmacosx-version-min=12.0 \
  -framework Cocoa \
  "$ROOT/src/main.m" \
  -o "$MACOS/XueMeiCleanerNative"
chmod +x "$MACOS/XueMeiCleanerNative"

PLIST_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")"
SOURCE_VER="$(grep -E 'XMCVersion = @\"[^\"]+\"' "$RES/main.m" | head -1 | sed -E 's/.*XMCVersion = @\"([^\"]+)\".*/\1/')"
ENGINE_VER="$(grep -E '^VERSION=\"[^\"]+\"' "$RES/engine.sh" | head -1 | sed -E 's/^VERSION=\"([^\"]+)\"/\1/')"

if [[ "$PLIST_VER" != "$SOURCE_VER" || "$PLIST_VER" != "$ENGINE_VER" ]]; then
  print -u2 "Version mismatch: plist=$PLIST_VER source=$SOURCE_VER engine=$ENGINE_VER"
  exit 3
fi

codesign --force --deep --sign - "$APP"
print "Built: $APP"
print "Version: $PLIST_VER"
