#!/usr/bin/env zsh
set -euo pipefail
VER="5.2.10"
ZIP_URL="https://github.com/dschenyw/xuemei-optimizer/releases/download/v${VER}/Xuemei-Optimizer-v${VER}-Update.zip"
EXPECTED="4f9c3b9d27593c978b5961f0eac572d17d6d4dd51be86dee8e154c3366926e44"
CURRENT="$HOME/Applications/雪梅清理.app"
[[ -d "$CURRENT" ]] || CURRENT="/Applications/雪梅优化.app"
[[ -d "$CURRENT" ]] || { echo "STATUS=CURRENT_APP_NOT_FOUND"; exit 1; }
TMP="$(mktemp -d "$HOME/Library/Caches/xuemei-bridge.XXXXXX")"
cleanup(){ /bin/rm -rf "$TMP"; }
trap cleanup EXIT
/usr/bin/curl -fL --retry 3 -H "Cache-Control: no-cache, no-store, max-age=0" -H "Pragma: no-cache" "${ZIP_URL}?bridge=$(/bin/date +%s)" -o "$TMP/update.zip"
ACTUAL="$(/usr/bin/shasum -a 256 "$TMP/update.zip" | /usr/bin/awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "STATUS=SHA256_MISMATCH"; exit 2; }
/usr/bin/ditto -x -k "$TMP/update.zip" "$TMP/extract"
CANDIDATE="$(/usr/bin/find "$TMP/extract" -maxdepth 3 -type d -name "雪梅优化.app" -print -quit)"
[[ -n "$CANDIDATE" ]] || { echo "STATUS=APP_NOT_FOUND"; exit 3; }
PV="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)"
[[ "$PV" == "$VER" ]] || { echo "STATUS=VERSION_MISMATCH"; exit 4; }
/usr/bin/codesign --verify --deep --strict "$CANDIDATE" || { echo "STATUS=SIGNATURE_INVALID"; exit 5; }
BACKROOT="$HOME/Library/Application Support/雪梅清理/Backups"
/bin/mkdir -p "$BACKROOT"
BACK="$BACKROOT/雪梅优化_before_v${VER}_bridge_$(/bin/date +%Y%m%d_%H%M%S).app"
/usr/bin/ditto "$CURRENT" "$BACK"
PENDING="${CURRENT}.pending-v${VER}"
/bin/rm -rf "$PENDING"
/usr/bin/ditto "$CANDIDATE" "$PENDING"
/usr/bin/xattr -cr "$PENDING" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$PENDING" >/dev/null 2>&1 || true
PID="$(/usr/bin/pgrep -f "$CURRENT/Contents/MacOS/" | /usr/bin/head -1 || true)"
[[ -n "$PID" ]] && /bin/kill "$PID" 2>/dev/null || true
/bin/sleep 2
/bin/rm -rf "$CURRENT"
/bin/mv "$PENDING" "$CURRENT"
/usr/bin/open "$CURRENT"
echo "STATUS=SUCCESS"
echo "VERSION=$VER"
echo "BACKUP=$BACK"
